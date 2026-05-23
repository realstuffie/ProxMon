#!/bin/bash
set -euo pipefail

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%s\n' "Missing required command: $1" >&2
    exit 1
  fi
}

# Run a command as root — tries sudo, doas, su in order.
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
INSTALL_WATCHER=1
for arg in "$@"; do
  case "$arg" in
    --no-deps) AUTO_DEPS=0 ;;
    --no-watcher) INSTALL_WATCHER=0 ;;
    --install-standalone-qml-module) INSTALL_STANDALONE_QML_MODULE=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: ./install.sh [--no-deps] [--no-watcher] [--install-standalone-qml-module]

Options:
  --no-deps     Skip automatic dependency installation.
  --no-watcher  Skip auto-update watcher install.
  --install-standalone-qml-module
                Also copy the native plugin/qmldir to the user-local Qt6 QML
                module path for stricter distro/policy setups.
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

  local pm="" pm_update="" pm_install="" pm_provider_prefix=""

  if command -v apt-get >/dev/null 2>&1; then
    pm="apt-get"
    pm_update="apt-get update"
    pm_install="apt-get install -y"
    # libvncserver-dev ships both libvncserver and libvncclient headers on Debian/Ubuntu.
    # libqtermwidget6 dev pkg is version-suffixed on some releases — both names listed.
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

  install_pkgs_best_effort() {
    # shellcheck disable=SC2086
    run_root $pm_install "$@" || true
  }

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

  [ -n "$pm_update" ] && run_root $pm_update

  # shellcheck disable=SC2086
  install_pkgs_best_effort $pkgs_build
  install_pkgs_best_effort "$pkgs_ecm"

  # Try each qtermwidget6 dev candidate; stop at the first available one.
  if [ -n "${pkgs_qtermwidget:-}" ]; then
    for candidate in $pkgs_qtermwidget; do
      if [ "$pm" = "apt-get" ]; then
        if apt-cache show "$candidate" >/dev/null 2>&1; then
          install_pkgs_best_effort "$candidate"
          break
        fi
      else
        install_pkgs_best_effort "$candidate" && break
      fi
    done
  fi

  if [ -n "${pkgs_kpackage:-}" ]; then
    install_pkgs_best_effort "$pkgs_kpackage"
  else
    command -v kpackagetool6 >/dev/null 2>&1 || install_provider_best_effort "${pm_provider_prefix}kpackagetool6"
  fi

  if [ "$pm" = "zypper" ] || [ "$pm" = "dnf" ]; then
    rpm -q extra-cmake-modules >/dev/null 2>&1 || install_provider_best_effort "${pm_provider_prefix}ECMConfig.cmake"
    rpm -q kf6-plasma-devel >/dev/null 2>&1 || install_provider_best_effort "${pm_provider_prefix}KF6PlasmaConfig.cmake"
  fi

  if [ "$pm" = "dnf" ]; then
    printf '%s\n' "         (Fedora) sudo prompts may appear mid-output — this is normal."
  fi
}

# Prime sudo upfront so the password prompt doesn't interrupt build output.
if [ "$AUTO_DEPS" -eq 1 ] && [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
  sudo -v
fi

install_deps_best_effort

KPACKAGETOOL=""
if command -v kpackagetool6 >/dev/null 2>&1; then
  KPACKAGETOOL="kpackagetool6"
elif command -v kpackagetool5 >/dev/null 2>&1; then
  KPACKAGETOOL="kpackagetool5"
else
  printf '%s\n' "Could not find kpackagetool6 or kpackagetool5. Install KDE Plasma packaging tools." >&2
  exit 1
fi

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

BUILD_DIR="$(mktemp -d -t proxmon-build-XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

cmake -S contents/lib -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release || exit 1

JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
BUILD_START="$(date +%s)"
cmake --build "$BUILD_DIR" -- -j"$JOBS" || exit 1
BUILD_END="$(date +%s)"
printf '%s\n' "[ build] Done in $(( BUILD_END - BUILD_START ))s"

# Stage .so into the plasmoid package — main.qml uses a relative import
# resolved to contents/lib/proxmox/, which kpackagetool installs verbatim.
cp "$BUILD_DIR/libproxmoxclientplugin.so" contents/lib/proxmox/
printf '%s\n' "[ build] Plugin staged → contents/lib/proxmox/libproxmoxclientplugin.so"

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

# Remove stale env file from older installs.
PLASMA_ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-workspace/env/proxmon-qml.sh"
if [ -f "$PLASMA_ENV_FILE" ]; then
  rm -f "$PLASMA_ENV_FILE"
fi

PKG_PATH="."
if "$KPACKAGETOOL" --help 2>/dev/null | grep -q -- '--type'; then
  "$KPACKAGETOOL" --type Plasma/Applet --install "$PKG_PATH" 2>/dev/null || \
  "$KPACKAGETOOL" --type Plasma/Applet --upgrade "$PKG_PATH" || true
else
  "$KPACKAGETOOL" -t Plasma/Applet -i "$PKG_PATH" 2>/dev/null || \
  "$KPACKAGETOOL" -t Plasma/Applet -u "$PKG_PATH" || true
fi

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

# Installs a systemd path unit that watches runtime libs and triggers a rebuild
# via check-and-rebuild.sh when any of them change (e.g. after a Qt update).
install_autoupdate() {
  if ! command -v systemctl >/dev/null 2>&1; then
    printf '%s\n' "systemctl not found — skipping auto-update watcher install."
    return 0
  fi

  local plasmoid_dir="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/org.kde.plasma.proxmox"
  local systemd_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

  mkdir -p "$plasmoid_dir" "$systemd_dir"

  if [ -f "check-and-rebuild.sh" ]; then
    cp check-and-rebuild.sh "$plasmoid_dir/check-and-rebuild.sh"
    chmod +x "$plasmoid_dir/check-and-rebuild.sh"
    cp "$0" "$plasmoid_dir/install.sh"
    chmod +x "$plasmoid_dir/install.sh"
  else
    printf '%s\n' "WARNING: check-and-rebuild.sh not found — skipping auto-update install." >&2
    return 0
  fi

  if [ -f "proxmox-plasmoid-rebuild.service" ]; then
    cp proxmox-plasmoid-rebuild.service "$systemd_dir/"
  else
    printf '%s\n' "WARNING: proxmox-plasmoid-rebuild.service not found — skipping auto-update install." >&2
    return 0
  fi

  # Resolve a lib path via ldconfig with a find fallback.
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
  [ -n "${libqt6core_path:-}"     ] && printf '%s\n' "[ watch] libQt6Core.so     → $libqt6core_path"
  [ -n "${libvncclient_path:-}"   ] && printf '%s\n' "[ watch] libvncclient.so   → $libvncclient_path"
  [ -n "${libqtermwidget_path:-}" ] && printf '%s\n' "[ watch] libqtermwidget6   → $libqtermwidget_path"

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

if [ "$INSTALL_WATCHER" -eq 1 ]; then
  install_autoupdate
fi

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
printf '%s\n' "    or simply log out and back in."
printf '\n'
printf '%s\n' "  Add the widget:"
printf '%s\n' "    Right-click panel → Add Widgets → search 'Proxmox'"
printf '\n'
printf '%s\n' "  Auto-update watcher:"
printf '%s\n' "    systemctl --user status proxmox-plasmoid-rebuild.path"
printf '%s\n' "    tail -f $PLASMOID_DIR/rebuild.log"
printf '\n'
