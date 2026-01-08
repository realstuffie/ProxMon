#!/bin/bash
set -euo pipefail

printf '%s\n' "Installing Proxmox Monitor Plasmoid..."

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%s\n' "Missing required command: $1" >&2
    exit 1
  fi
}

AUTO_DEPS=0
for arg in "$@"; do
  case "$arg" in
    --install-deps) AUTO_DEPS=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: ./install.sh [--install-deps]

Options:
  --install-deps   Attempt to install build/runtime dependencies using the detected package manager.
                  Requires sudo/root and is best-effort (package names vary by distro).
EOF
      exit 0
      ;;
  esac
done

install_deps_best_effort() {
  if [ "$AUTO_DEPS" -ne 1 ]; then
    return 0
  fi

  printf '%s\n' "Auto-install deps enabled (--install-deps). Attempting best-effort dependency install..."
  printf '%s\n' "NOTE: This is best-effort. Package names vary by distro and version."
  printf '%s\n' "NOTE: Any \"not found\" messages for optional packages are non-fatal and can be ignored if the build succeeds."

  # If already root, run directly. Otherwise prefer sudo, then doas, then su.
  run_root() {
    if [ "$(id -u)" -eq 0 ]; then
      "$@"
    elif command -v sudo >/dev/null 2>&1; then
      sudo "$@"
    elif command -v doas >/dev/null 2>&1; then
      doas "$@"
    else
      su -c "$(printf '%q ' "$@")"
    fi
  }

  # Helper to install a list of packages, but don't fail the whole script if some are missing.
  install_pkgs_best_effort() {
    local installer="$1"
    shift
    run_root "$installer" "$@" || true
  }

  # Attempt to resolve a package providing a given file/capability, then install it.
  # (Different distros use different "what-provides" mechanisms.)
  install_provider_best_effort() {
    local provider_query="$1"

    if command -v zypper >/dev/null 2>&1; then
      # zypper: try "search by file"
      local pkg
      pkg="$(zypper --non-interactive se -x -f "$provider_query" 2>/dev/null | awk -F'|' 'NR>2 && $2 ~ /\\S/ {gsub(/^[ \\t]+|[ \\t]+$/, "", $2); print $2; exit}')"
      if [ -n "${pkg:-}" ]; then
        install_pkgs_best_effort zypper "install" "-y" "$pkg"
      fi
    elif command -v dnf >/dev/null 2>&1; then
      local pkg
      pkg="$(dnf -q provides "$provider_query" 2>/dev/null | awk '/:/{print $1; exit}')"
      if [ -n "${pkg:-}" ]; then
        install_pkgs_best_effort dnf "install" "-y" "$pkg"
      fi
    elif command -v apt-get >/dev/null 2>&1; then
      # No reliable "provides by file" without apt-file (not default). Skip.
      true
    elif command -v pacman >/dev/null 2>&1; then
      # Could use pkgfile on Arch, but not default. Skip.
      true
    fi
  }

  # Identify package manager and install a minimal baseline + then try to resolve key extras by provider.
  if command -v apt-get >/dev/null 2>&1; then
    run_root apt-get update
    install_pkgs_best_effort apt-get install -y \
      cmake make g++ pkg-config \
      qt6-base-dev qt6-declarative-dev
    # ECM/KF6 package names vary; leave as optional hints:
    install_pkgs_best_effort apt-get install -y extra-cmake-modules || true
  elif command -v zypper >/dev/null 2>&1; then
    run_root zypper refresh
    install_pkgs_best_effort zypper install -y \
      cmake make gcc-c++ pkg-config \
      qt6-base-devel qt6-declarative-devel

    # Try common names, but don't fail if absent.
    install_pkgs_best_effort zypper install -y extra-cmake-modules || true

    # Try to resolve common tools/configs by provider (more reliable than hardcoding *-devel names).
    install_provider_best_effort "kpackagetool6"
    install_provider_best_effort "ECMConfig.cmake"
    install_provider_best_effort "KF6PlasmaConfig.cmake"
  elif command -v dnf >/dev/null 2>&1; then
    install_pkgs_best_effort dnf install -y \
      cmake make gcc-c++ pkgconf-pkg-config \
      qt6-qtbase-devel qt6-qtdeclarative-devel
    install_pkgs_best_effort dnf install -y extra-cmake-modules || true
    # Try to resolve by common files if repositories provide them.
    install_provider_best_effort "*/kpackagetool6"
    install_provider_best_effort "*/ECMConfig.cmake"
    install_provider_best_effort "*/KF6PlasmaConfig.cmake"
  elif command -v pacman >/dev/null 2>&1; then
    install_pkgs_best_effort pacman -Sy --noconfirm \
      cmake make gcc pkgconf \
      qt6-base qt6-declarative
    install_pkgs_best_effort pacman -Sy --noconfirm extra-cmake-modules || true
  else
    printf '%s\n' "No supported package manager detected (apt-get/zypper/dnf/pacman). Skipping auto deps." >&2
    return 0
  fi
}

# Prefer kpackagetool6 (Plasma 6), fallback to kpackagetool5 (Plasma 5)
KPACKAGETOOL=""
if command -v kpackagetool6 >/dev/null 2>&1; then
  KPACKAGETOOL="kpackagetool6"
elif command -v kpackagetool5 >/dev/null 2>&1; then
  KPACKAGETOOL="kpackagetool5"
else
  printf '%s\n' "Could not find kpackagetool6 or kpackagetool5. Install KDE Plasma packaging tools." >&2
  exit 1
fi

install_deps_best_effort

require_cmd cmake
require_cmd mktemp
require_cmd getconf
require_cmd cp
require_cmd mkdir

printf '%s\n' "Building native Proxmox API plugin..."

# Build out-of-source to avoid polluting the repo with build artifacts
BUILD_DIR="$(mktemp -d -t proxmon-build-XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

cmake -S contents/lib -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release || exit 1

# Build in parallel (CMake will choose a sensible default; we also pass an explicit -j as a hint)
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
cmake --build "$BUILD_DIR" -- -j"$JOBS" || exit 1

# Stage runtime QML module into the plasmoid package
#
# NOTE: For Plasma 6, custom QML modules are most reliably discovered when shipped under:
#   contents/qml/<module-uri-path>/
mkdir -p contents/qml/org/kde/plasma/proxmox

# qmldir is already in the package (see contents/lib/proxmox/qmldir). This script stages the .so here.
cp "$BUILD_DIR/libproxmoxclientplugin.so" contents/qml/org/kde/plasma/proxmox/

printf '%s\n' "Native plugin staged: contents/qml/org/kde/plasma/proxmox/libproxmoxclientplugin.so"

# Install plasmoid
#
# Use user-local install location by default for portability across distros:
# - Plasma applets: ${XDG_DATA_HOME:-~/.local/share}/plasma/plasmoids/
#
# Not all kpackagetool builds support --packageroot. Detect support and fallback.
# Prefer modern long options (--type/--install/--upgrade); fall back to short options.
# Also, only use --packageroot if supported.
# kpackagetool6 uses "install <path>" / "upgrade <path>" options that REQUIRE a value.
# Our previous invocation passed "." without binding it to --install/--upgrade, which
# results in errors like:
#   Error: Plugin  is not installed.
#   "One of install, remove, upgrade or list is required."
PKG_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}"
PKG_PATH="."

# Prefer long options if available, else use short options.
if "$KPACKAGETOOL" --help 2>/dev/null | grep -q -- '--type'; then
  if "$KPACKAGETOOL" --help 2>/dev/null | grep -q -- '--packageroot'; then
    "$KPACKAGETOOL" --type Plasma/Applet --install "$PKG_PATH" --packageroot "$PKG_ROOT" 2>/dev/null || \
    "$KPACKAGETOOL" --type Plasma/Applet --upgrade "$PKG_PATH" --packageroot "$PKG_ROOT"
  else
    "$KPACKAGETOOL" --type Plasma/Applet --install "$PKG_PATH" 2>/dev/null || \
    "$KPACKAGETOOL" --type Plasma/Applet --upgrade "$PKG_PATH"
  fi
else
  if "$KPACKAGETOOL" --help 2>/dev/null | grep -q -- '--packageroot'; then
    "$KPACKAGETOOL" -t Plasma/Applet -i "$PKG_PATH" --packageroot "$PKG_ROOT" 2>/dev/null || \
    "$KPACKAGETOOL" -t Plasma/Applet -u "$PKG_PATH" --packageroot "$PKG_ROOT"
  else
    "$KPACKAGETOOL" -t Plasma/Applet -i "$PKG_PATH" 2>/dev/null || \
    "$KPACKAGETOOL" -t Plasma/Applet -u "$PKG_PATH"
  fi
fi

# Install icons (user-local; portable via XDG)
# Plasma resolves KPlugin.Icon via the icon theme, not from the plasmoid package.
# Our icon sources live in this repo under contents/icons/.
ICON_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
ICON_DIR="$ICON_BASE/hicolor/scalable/apps"
mkdir -p "$ICON_DIR"

if [ -d "icons" ]; then
  cp icons/*.svg "$ICON_DIR/"
elif [ -d "contents/icons" ]; then
  cp contents/icons/*.svg "$ICON_DIR/"
else
  printf '%s\n' "No icon source dir found (expected ./icons or ./contents/icons). Skipping icon install." >&2
fi

# Update icon cache (best-effort; command availability differs by distro/DE)
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache "$ICON_BASE/hicolor/" 2>/dev/null || true
fi

# Some distros/DEs rely on KDE's icon cache; refresh if kbuildsycoca6 exists.
if command -v kbuildsycoca6 >/dev/null 2>&1; then
  kbuildsycoca6 >/dev/null 2>&1 || true
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
  kbuildsycoca5 >/dev/null 2>&1 || true
fi

printf '\n'
printf '%s\n' "Installation complete!"
printf '\n'
printf '%s\n' "To add the widget:"
printf '%s\n' "  1. Right-click on your panel"
printf '%s\n' "  2. Click 'Add Widgets'"
printf '%s\n' "  3. Search for 'Proxmox'"
printf '%s\n' "  4. Drag to panel"
printf '\n'
printf '%s\n' "You may need to restart Plasma:"
printf '%s\n' "  kquitapp6 plasmashell && kstart plasmashell"
printf '%s\n' "If that doesn't work on your distro, try:"
printf '%s\n' "  systemctl --user restart plasma-plasmashell.service"
printf '%s\n' "or log out/in."

