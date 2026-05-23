#!/bin/bash
set -euo pipefail


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
INSTALL_STANDALONE_QML_MODULE=0
for arg in "$@"; do
  case "$arg" in
    --no-deps) AUTO_DEPS=0 ;;
    --install-standalone-qml-module) INSTALL_STANDALONE_QML_MODULE=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: ./install.sh [--no-deps] [--install-standalone-qml-module]

Options:
  --no-deps   Skip automatic dependency installation. Use this if you have
              already installed build dependencies or prefer to manage them
              yourself. By default, install.sh will attempt to install missing
              build/runtime dependencies using the system package manager
              (apt-get / zypper / dnf / pacman). Requires sudo/root.
  --install-standalone-qml-module
              Also copy the native plugin/qmldir to your user-local Qt6 QML
              module path for compatibility on stricter distro/policy setups.
              Default behavior keeps runtime plugin location inside the
              plasmoid package only.
EOF
      exit 0
      ;;
  esac
done

install_deps_best_effort() {
  if [ "$AUTO_DEPS" -ne 1 ]; then
    return 0
  fi

  printf '%s\n' "[ deps ] Installing build dependencies..."
  printf '%s\n' "         Package names vary by distro — missing optional packages are non-fatal."

  # Detect package manager and set distro-specific variables
  local pm="" pm_update="" pm_install="" pm_provider_prefix=""
  local pkgs_build="" pkgs_ecm="" pkgs_kpackage=""

  if command -v apt-get >/dev/null 2>&1; then
    pm="apt-get"
    pm_update="apt-get update"
    pm_install="apt-get install -y"
    # libvncclient-dev: VNC console; qt6-websockets-dev + libqtermwidget6*-dev: LXC console.
    # libutf8proc-dev: pulled in transitively by qtermwidget6's headers.
    # libqtermwidget6 dev package is version-suffixed on some Ubuntu releases
    # (libqtermwidget6-2-dev), unsuffixed on others (libqtermwidget6-dev) —
    # both names are listed; install_pkgs_best_effort tolerates a missing one.
    # libvncserver-dev ships both libvncserver and libvncclient headers/pc files on Debian/Ubuntu.
    pkgs_build="cmake make g++ pkg-config qt6-base-dev qt6-declarative-dev qt6-websockets-dev libsecret-1-dev libvncserver-dev libutf8proc-dev qtermwidget6-data"
    pkgs_qtermwidget="libqtermwidget6-2-dev libqtermwidget6-dev"
    pkgs_ecm="extra-cmake-modules"
    pkgs_kpackage="libkf6package-bin"
  elif command -v zypper >/dev/null 2>&1; then
    pm="zypper"
    pm_update="zypper refresh"
    pm_install="zypper install -y"
    pkgs_build="cmake make gcc-c++ pkg-config qt6-base-devel qt6-declarative-devel qt6-websockets-devel libvncserver-devel utf8proc-devel"
    pkgs_qtermwidget="qtermwidget-qt6-devel"
    pkgs_ecm="extra-cmake-modules"
  elif command -v dnf >/dev/null 2>&1; then
    pm="dnf"
    pm_install="dnf install -y"
    pm_provider_prefix="*/"
    pkgs_build="cmake make gcc-c++ pkgconf-pkg-config qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtwebsockets-devel libvncserver-devel utf8proc-devel"
    pkgs_qtermwidget="qtermwidget-qt6-devel"
    pkgs_ecm="extra-cmake-modules"
  elif command -v pacman >/dev/null 2>&1; then
    pm="pacman"
    pm_install="pacman -Sy --noconfirm --needed"
    pkgs_build="cmake make gcc pkgconf qt6-base qt6-declarative qt6-websockets libvncserver libutf8proc"
    pkgs_qtermwidget="qtermwidget"
    pkgs_ecm="extra-cmake-modules"
  else
    printf '%s\n' "No supported package manager detected (apt-get/zypper/dnf/pacman). Skipping auto deps." >&2
    return 0
  fi

  # Helper to install a list of packages, don't fail the whole script if some are missing.
  install_pkgs_best_effort() {
    # shellcheck disable=SC2086
    run_root $pm_install "$@" || true
  }

  # Attempt to resolve a package providing a given file/capability, then install it.
  install_provider_best_effort() {
    local provider_query="$1"
    local pkg=""
    if [ "$pm" = "zypper" ]; then
      pkg="$(zypper --non-interactive se -x -f "$provider_query" 2>/dev/null | awk -F'|' 'NR>2 && $2 ~ /\S/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')" || true
    elif [ "$pm" = "dnf" ]; then
      pkg="$(dnf -q --cacheonly provides "$provider_query" 2>/dev/null | awk '/:/{print $1; exit}')" || true
    fi
    if [ -n "${pkg:-}" ]; then
      sudo -v 2>/dev/null || true
      install_pkgs_best_effort "$pkg"
    fi
  }

  # Run update if needed
  [ -n "$pm_update" ] && run_root $pm_update

  # Install core build deps
  # shellcheck disable=SC2086
  install_pkgs_best_effort $pkgs_build

  # Install ECM
  install_pkgs_best_effort "$pkgs_ecm"

  # qtermwidget6 dev package: try each candidate name in turn (apt versions
  # the dev pkg as libqtermwidget6-2-dev on Ubuntu 26+, libqtermwidget6-dev
  # elsewhere). Stop at the first one that's actually present in the index.
  if [ -n "${pkgs_qtermwidget:-}" ]; then
    for candidate in $pkgs_qtermwidget; do
      if [ "$pm" = "apt-get" ]; then
        if apt-cache show "$candidate" >/dev/null 2>&1; then
          install_pkgs_best_effort "$candidate"
          break
        fi
      else
        # zypper/dnf/pacman: just try; install_pkgs_best_effort tolerates failure
        install_pkgs_best_effort "$candidate" && break
      fi
    done
  fi

  # Install kpackage tool (apt has a direct package name, zypper/dnf use provider lookup)
  if [ -n "${pkgs_kpackage:-}" ]; then
    install_pkgs_best_effort "$pkgs_kpackage"
  else
    command -v kpackagetool6 >/dev/null 2>&1 || install_provider_best_effort "${pm_provider_prefix}kpackagetool6"
  fi

  # Install remaining providers (zypper/dnf only, skip if already present)
  if [ "$pm" = "zypper" ] || [ "$pm" = "dnf" ]; then
    rpm -q extra-cmake-modules >/dev/null 2>&1 || install_provider_best_effort "${pm_provider_prefix}ECMConfig.cmake"
    rpm -q kf6-plasma-devel >/dev/null 2>&1 || install_provider_best_effort "${pm_provider_prefix}KF6PlasmaConfig.cmake"
  fi

  if [ "$pm" = "dnf" ]; then
    printf '%s\n' "         (Fedora) sudo prompts may appear mid-output — this is normal."
  fi
}

# Prime sudo credentials upfront so the password prompt doesn't interrupt
# build output mid-stream. Only needed when auto dep install is enabled.
if [ "$AUTO_DEPS" -eq 1 ] && [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
  sudo -v
fi

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
  printf '%s\n' "[ git  ] Initializing submodules..."
  git submodule update --init --recursive
fi

require_cmd cmake
require_cmd mktemp
require_cmd getconf
require_cmd cp
require_cmd mkdir

printf '%s\n' "[ build] Compiling native plugin..."

# Build out-of-source to avoid polluting the repo with build artifacts
BUILD_DIR="$(mktemp -d -t proxmon-build-XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

cmake -S contents/lib -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release || exit 1

JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
BUILD_START="$(date +%s)"
cmake --build "$BUILD_DIR" -- -j"$JOBS" || exit 1
BUILD_END="$(date +%s)"
printf '%s\n' "[ build] Done in $(( BUILD_END - BUILD_START ))s"

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
printf '%s\n' "[ build] Plugin staged → contents/lib/proxmox/libproxmoxclientplugin.so"

# ---------------------------------------------------------------------------
# Detect user-local Qt6 QML dir for documentation/diagnostics only.
# Runtime plugin is shipped inside the plasmoid package at contents/lib/proxmox.
# ---------------------------------------------------------------------------
detect_qt6_qml_user_dir() {
  local arch_triplet=""
  if command -v dpkg-architecture >/dev/null 2>&1; then
    arch_triplet="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
  fi
  if [ -n "${arch_triplet:-}" ] && echo "$arch_triplet" | grep -q '-'; then
    printf '%s/.local/lib/%s/qt6/qml' "$HOME" "$arch_triplet"
  else
    printf '%s/.local/lib/qt6/qml' "$HOME"
  fi
}

QT6_QML_USER_DIR="$(detect_qt6_qml_user_dir)"
QML_MODULE_USER_DIR="$QT6_QML_USER_DIR/org/kde/plasma/proxmox"
if [ "$INSTALL_STANDALONE_QML_MODULE" -eq 1 ]; then
  mkdir -p "$QML_MODULE_USER_DIR"
  cp "$BUILD_DIR/libproxmoxclientplugin.so" "$QML_MODULE_USER_DIR/"
  cp contents/lib/proxmox/qmldir "$QML_MODULE_USER_DIR/"
  printf '%s\n' "[ qml  ] Standalone module copied → $QML_MODULE_USER_DIR"
fi

# Clean up any stale Plasma workspace env file from a previous install attempt
PLASMA_ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-workspace/env/proxmon-qml.sh"
if [ -f "$PLASMA_ENV_FILE" ]; then
  rm -f "$PLASMA_ENV_FILE"
fi

# Install plasmoid package
PKG_PATH="."
if "$KPACKAGETOOL" --help 2>/dev/null | grep -q -- '--type'; then
  "$KPACKAGETOOL" --type Plasma/Applet --install "$PKG_PATH" 2>/dev/null || \
  "$KPACKAGETOOL" --type Plasma/Applet --upgrade "$PKG_PATH" || true
else
  "$KPACKAGETOOL" -t Plasma/Applet -i "$PKG_PATH" 2>/dev/null || \
  "$KPACKAGETOOL" -t Plasma/Applet -u "$PKG_PATH" || true
fi

# Install icons from a single authoritative source
ICON_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
ICON_DIR="$ICON_BASE/hicolor/scalable/apps"
mkdir -p "$ICON_DIR"
if [ -d "contents/icons" ]; then
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

# ---------------------------------------------------------------------------
# install_autoupdate: resolves libplasma.so path at install time via ldconfig,
# generates a systemd path unit pointing at it, and installs a service unit
# that runs check-and-rebuild.sh when the path unit fires.
#
# Using a path unit (inotify-based) rather than a timer.
# ---------------------------------------------------------------------------
install_autoupdate() {
  if ! command -v systemctl >/dev/null 2>&1; then
    printf '%s\n' "systemctl not found — skipping auto-update watcher install."
    return 0
  fi

  local plasmoid_dir="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/org.kde.plasma.proxmox"
  local systemd_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

  mkdir -p "$plasmoid_dir" "$systemd_dir"

  # Copy check-and-rebuild.sh and install.sh into the plasmoid dir so the
  # setup is self-contained and survives the source repo being moved/deleted.
  if [ -f "check-and-rebuild.sh" ]; then
    cp check-and-rebuild.sh "$plasmoid_dir/check-and-rebuild.sh"
    chmod +x "$plasmoid_dir/check-and-rebuild.sh"
    # install.sh is needed by check-and-rebuild.sh for --no-deps rebuilds
    cp "$0" "$plasmoid_dir/install.sh"
    chmod +x "$plasmoid_dir/install.sh"
  else
    printf '%s\n' "WARNING: check-and-rebuild.sh not found — skipping auto-update install." >&2
    return 0
  fi

  # Copy the static service unit
  if [ -f "proxmox-plasmoid-rebuild.service" ]; then
    cp proxmox-plasmoid-rebuild.service "$systemd_dir/"
  else
    printf '%s\n' "WARNING: proxmox-plasmoid-rebuild.service not found — skipping auto-update install." >&2
    return 0
  fi

  # Resolve a library path via ldconfig, with a find fallback.
  resolve_lib() {
    local pattern="$1"
    local result
    result="$(ldconfig -p 2>/dev/null | grep -i "$pattern" | awk '{print $NF}' | head -1)" || true
    if [ -z "${result:-}" ]; then
      result="$(find /usr/lib64 /usr/lib /lib64 /lib -name "${pattern}*" 2>/dev/null | grep '\.so\.[0-9]*$' | head -1)" || true
    fi
    printf '%s' "${result:-}"
  }

  local libplasma_path libqt6core_path libvncclient_path libqtermwidget_path

  libplasma_path="$(resolve_lib 'libPlasma\.so\.')"
  if [ -z "${libplasma_path:-}" ]; then
    printf '%s\n' "WARNING: Could not resolve libplasma.so — skipping auto-update install." >&2
    return 0
  fi

  libqt6core_path="$(resolve_lib 'libQt6Core\.so\.')"
  libvncclient_path="$(resolve_lib 'libvncclient\.so\.')"
  libqtermwidget_path="$(resolve_lib 'libqtermwidget')"

  printf '%s\n' "[ watch] libplasma.so      → $libplasma_path"
  [ -n "${libqt6core_path:-}"    ] && printf '%s\n' "[ watch] libQt6Core.so     → $libqt6core_path"
  [ -n "${libvncclient_path:-}"  ] && printf '%s\n' "[ watch] libvncclient.so   → $libvncclient_path"
  [ -n "${libqtermwidget_path:-}" ] && printf '%s\n' "[ watch] libqtermwidget6   → $libqtermwidget_path"

  # Generate the path unit dynamically — watch all resolved libs.
  # A change to any of them (Qt update, VNC lib update, etc.) triggers a rebuild.
  {
    cat <<'EOF'
[Unit]
Description=Proxmox Plasmoid - watch runtime libraries for changes

[Path]
EOF
    printf 'PathChanged=%s\n' "$libplasma_path"
    [ -n "${libqt6core_path:-}"     ] && printf 'PathChanged=%s\n' "$libqt6core_path"
    [ -n "${libvncclient_path:-}"   ] && printf 'PathChanged=%s\n' "$libvncclient_path"
    [ -n "${libqtermwidget_path:-}" ] && printf 'PathChanged=%s\n' "$libqtermwidget_path"
    cat <<'EOF'

[Install]
WantedBy=default.target
EOF
  } > "$systemd_dir/proxmox-plasmoid-rebuild.path"

  systemctl --user daemon-reload
  systemctl --user enable --now proxmox-plasmoid-rebuild.path

  printf '%s\n' "[ watch] Auto-update watcher enabled."
}

install_autoupdate

# ---------------------------------------------------------------------------
# Write build fingerprint now that install succeeded, so the path unit's
# first trigger does not cause a redundant rebuild.
# ---------------------------------------------------------------------------
PLASMOID_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/org.kde.plasma.proxmox"
FINGERPRINT_FILE="$PLASMOID_DIR/.build_fingerprint"
{ ldconfig -p 2>/dev/null | grep -iE 'libplasma|libQt6' || true; } \
  | awk '{print $NF}' \
  | sort \
  | xargs -r md5sum 2>/dev/null \
  | md5sum \
  | cut -d' ' -f1 > "$FINGERPRINT_FILE"

printf '\n'
printf '%s\n' "Install complete."
printf '\n'
printf '%s\n' "  Restart Plasma to activate:"
printf '%s\n' "    kquitapp6 plasmashell && kstart plasmashell"
printf '%s\n' "    systemctl --user restart plasma-plasmashell.service"
printf '\n'
printf '%s\n' "  Add the widget:"
printf '%s\n' "    Right-click panel → Add Widgets → search 'Proxmox'"
printf '\n'
printf '%s\n' "  Auto-update watcher:"
printf '%s\n' "    systemctl --user status proxmox-plasmoid-rebuild.path"
printf '%s\n' "    tail -f $PLASMOID_DIR/rebuild.log"
printf '\n'