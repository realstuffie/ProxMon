#!/bin/bash
set -euo pipefail

printf '%s\n' "Installing Proxmox Monitor Plasmoid..."

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%s\n' "Missing required command: $1" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# run_root: run a command as root. Tries sudo, doas, su in order.
# ---------------------------------------------------------------------------
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

AUTO_DEPS=1
for arg in "$@"; do
  case "$arg" in
    --no-deps) AUTO_DEPS=0 ;;
    -h|--help)
      cat <<'EOF'
Usage: ./install.sh [--no-deps]

Options:
  --no-deps   Skip automatic dependency installation. Use this if you have
              already installed build dependencies or prefer to manage them
              yourself. By default, install.sh will attempt to install missing
              build/runtime dependencies using the system package manager
              (apt-get / zypper / dnf / pacman). Requires sudo/root.
EOF
      exit 0
      ;;
  esac
done

install_deps_best_effort() {
  if [ "$AUTO_DEPS" -ne 1 ]; then
    return 0
  fi

  printf '%s\n' "Attempting best-effort dependency install (pass --no-deps to skip)..."
  printf '%s\n' "NOTE: This is best-effort. Package names vary by distro and version."
  printf '%s\n' "NOTE: Any \"not found\" messages for optional packages are non-fatal and can be ignored if the build succeeds."

  # Helper to install a list of packages, but don't fail the whole script if some are missing.
  install_pkgs_best_effort() {
    local installer="$1"
    shift
    run_root "$installer" "$@" || true
  }

  # Attempt to resolve a package providing a given file/capability, then install it.
  install_provider_best_effort() {
    local provider_query="$1"

    if command -v zypper >/dev/null 2>&1; then
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
      true
    elif command -v pacman >/dev/null 2>&1; then
      true
    fi
  }

  if command -v apt-get >/dev/null 2>&1; then
    run_root apt-get update
    install_pkgs_best_effort apt-get install -y \
      cmake make g++ pkg-config \
      qt6-base-dev qt6-declarative-dev \
      libsecret-1-dev
    install_pkgs_best_effort apt-get install -y extra-cmake-modules || true
    install_pkgs_best_effort apt-get install -y libkf6package-bin || true
  elif command -v zypper >/dev/null 2>&1; then
    run_root zypper refresh
    install_pkgs_best_effort zypper install -y \
      cmake make gcc-c++ pkg-config \
      qt6-base-devel qt6-declarative-devel
    install_pkgs_best_effort zypper install -y extra-cmake-modules || true
    install_provider_best_effort "kpackagetool6"
    install_provider_best_effort "ECMConfig.cmake"
    install_provider_best_effort "KF6PlasmaConfig.cmake"
  elif command -v dnf >/dev/null 2>&1; then
    install_pkgs_best_effort dnf install -y \
      cmake make gcc-c++ pkgconf-pkg-config \
      qt6-qtbase-devel qt6-qtdeclarative-devel
    install_pkgs_best_effort dnf install -y extra-cmake-modules || true
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

# Run dep install first so kpackagetool6/cmake are available for the checks below.
install_deps_best_effort

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

# Ensure qtkeychain submodule is available when running from a git checkout.
if command -v git >/dev/null 2>&1 && [ -f .gitmodules ] && [ -d .git ]; then
  printf '%s\n' "Initializing git submodules (qtkeychain)..."
  git submodule update --init --recursive
fi

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

JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
cmake --build "$BUILD_DIR" -- -j"$JOBS" || exit 1

# ---------------------------------------------------------------------------
# Stage runtime QML module into the plasmoid package.
#
# main.qml uses a RELATIVE import: import "../lib/proxmox" as ProxMon
# (resolved from contents/ui/ → contents/lib/proxmox/)
# The .so must be co-located with the qmldir in contents/lib/proxmox/.
# kpackagetool6 installs all files under contents/ verbatim, so the .so
# will land at:
#   <plasmoid_dir>/contents/lib/proxmox/libproxmoxclientplugin.so
# which is exactly where the QML engine will look for it.
# ---------------------------------------------------------------------------
cp "$BUILD_DIR/libproxmoxclientplugin.so" contents/lib/proxmox/
printf '%s\n' "Native plugin staged: contents/lib/proxmox/libproxmoxclientplugin.so"

# ---------------------------------------------------------------------------
# Install plugin to the SYSTEM Qt6 QML dir (primary, most reliable method).
#
# Plasma 6's QML engine always searches Qt's built-in QmlImportsPath:
#   /usr/lib/<arch>/qt6/qml/   (Debian/Ubuntu)
#   /usr/lib64/qt6/qml/        (Fedora/RHEL)
#   /usr/lib/qt6/qml/          (generic)
#
# This is the same location KDE's own cmake installs to via
# ${KDE_INSTALL_QMLDIR}. It requires root/sudo but is the only approach
# that works reliably across all Plasma 6 builds.
# ---------------------------------------------------------------------------
detect_sys_qt6_qml_dir() {
  # 1. Try qtpaths6 / qt6-paths
  local qtpaths_out=""
  if command -v qtpaths6 >/dev/null 2>&1; then
    qtpaths_out="$(qtpaths6 --paths Qml2ImportsPath 2>/dev/null | tr ':' '\n' | grep '^/usr/' | head -1 || true)"
  fi
  if [ -z "${qtpaths_out:-}" ] && command -v qt6-paths >/dev/null 2>&1; then
    qtpaths_out="$(qt6-paths --paths Qml2ImportsPath 2>/dev/null | tr ':' '\n' | grep '^/usr/' | head -1 || true)"
  fi
  if [ -n "${qtpaths_out:-}" ]; then
    printf '%s' "$qtpaths_out"
    return
  fi

  # 2. Find from filesystem
  local d
  for d in \
      /usr/lib/x86_64-linux-gnu/qt6/qml \
      /usr/lib/aarch64-linux-gnu/qt6/qml \
      /usr/lib/arm-linux-gnueabihf/qt6/qml \
      /usr/lib64/qt6/qml \
      /usr/lib/qt6/qml; do
    if [ -d "$d" ]; then
      printf '%s' "$d"
      return
    fi
  done

  # 3. Generic find fallback
  find /usr/lib -maxdepth 5 -type d -name "qml" 2>/dev/null | grep 'qt6/qml$' | head -1 || true
}

SYS_QT6_QML_DIR="$(detect_sys_qt6_qml_dir)"

if [ -n "${SYS_QT6_QML_DIR:-}" ]; then
  SYS_MODULE_DIR="$SYS_QT6_QML_DIR/org/kde/plasma/proxmox"
  printf '%s\n' "Installing QML plugin to system Qt6 QML dir (requires sudo): $SYS_MODULE_DIR"
  run_root mkdir -p "$SYS_MODULE_DIR"
  run_root cp "$BUILD_DIR/libproxmoxclientplugin.so" "$SYS_MODULE_DIR/"
  run_root cp contents/lib/proxmox/qmldir "$SYS_MODULE_DIR/"
  printf '%s\n' "QML plugin installed to system: $SYS_MODULE_DIR"
else
  printf '%s\n' "WARNING: Could not detect system Qt6 QML dir. Plugin may not load." >&2
fi

# ---------------------------------------------------------------------------
# Also install to user-local path as a belt-and-suspenders secondary copy.
# ---------------------------------------------------------------------------
detect_qt6_qml_user_dir() {
  local arch_triplet=""
  if command -v dpkg-architecture >/dev/null 2>&1; then
    arch_triplet="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
  fi
  if [ -z "${arch_triplet:-}" ] && [ -n "${SYS_QT6_QML_DIR:-}" ]; then
    # Derive arch from system dir path: /usr/lib/x86_64-linux-gnu/qt6/qml → x86_64-linux-gnu
    local tmp="${SYS_QT6_QML_DIR#/usr/lib/}"
    arch_triplet="${tmp%%/*}"
  fi
  if [ -n "${arch_triplet:-}" ] && echo "$arch_triplet" | grep -q '-'; then
    printf '%s/.local/lib/%s/qt6/qml' "$HOME" "$arch_triplet"
  elif [ -n "${SYS_QT6_QML_DIR:-}" ] && echo "$SYS_QT6_QML_DIR" | grep -q '/lib64/'; then
    printf '%s/.local/lib64/qt6/qml' "$HOME"
  else
    printf '%s/.local/lib/qt6/qml' "$HOME"
  fi
}

QT6_QML_USER_DIR="$(detect_qt6_qml_user_dir)"
QML_MODULE_USER_DIR="$QT6_QML_USER_DIR/org/kde/plasma/proxmox"
mkdir -p "$QML_MODULE_USER_DIR"
cp "$BUILD_DIR/libproxmoxclientplugin.so" "$QML_MODULE_USER_DIR/"
cp contents/lib/proxmox/qmldir "$QML_MODULE_USER_DIR/"
printf '%s\n' "QML plugin also copied to user-local: $QML_MODULE_USER_DIR"

# Clean up any stale Plasma workspace env file from a previous install attempt
PLASMA_ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-workspace/env/proxmon-qml.sh"
if [ -f "$PLASMA_ENV_FILE" ]; then
  rm -f "$PLASMA_ENV_FILE"
fi

# Install plasmoid package
PKG_PATH="."
if "$KPACKAGETOOL" --help 2>/dev/null | grep -q -- '--type'; then
  "$KPACKAGETOOL" --type Plasma/Applet --install "$PKG_PATH" 2>/dev/null || \
  "$KPACKAGETOOL" --type Plasma/Applet --upgrade "$PKG_PATH"
else
  "$KPACKAGETOOL" -t Plasma/Applet -i "$PKG_PATH" 2>/dev/null || \
  "$KPACKAGETOOL" -t Plasma/Applet -u "$PKG_PATH"
fi

# Install icons
ICON_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
ICON_DIR="$ICON_BASE/hicolor/scalable/apps"
mkdir -p "$ICON_DIR"
if [ -d "icons" ]; then
  cp icons/*.svg "$ICON_DIR/"
elif [ -d "contents/icons" ]; then
  cp contents/icons/*.svg "$ICON_DIR/"
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache "$ICON_BASE/hicolor/" 2>/dev/null || true
fi
if command -v kbuildsycoca6 >/dev/null 2>&1; then
  kbuildsycoca6 >/dev/null 2>&1 || true
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
  kbuildsycoca5 >/dev/null 2>&1 || true
fi

printf '\n'
printf '%s\n' "Installation complete!"
printf '\n'
printf '%s\n' "You may need to restart Plasma:"
printf '%s\n' "  kquitapp6 plasmashell && kstart plasmashell"
printf '%s\n' "If that doesn't work on your distro, try:"
printf '%s\n' "  systemctl --user restart plasma-plasmashell.service"
printf '%s\n' "or log out/in."
printf '\n'
printf '%s\n' "To add the widget:"
printf '%s\n' "  1. Right-click on your panel"
printf '%s\n' "  2. Click 'Add Widgets'"
printf '%s\n' "  3. Search for 'Proxmox'"
printf '%s\n' "  4. Drag to panel"
