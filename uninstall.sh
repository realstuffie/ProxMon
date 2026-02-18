#!/bin/bash
set -euo pipefail

printf '%s\n' "Uninstalling Proxmox Monitor Plasmoid..."

# run_root: run a command as root
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

# Remove plasmoid package
if command -v kpackagetool6 >/dev/null 2>&1; then
  kpackagetool6 -t Plasma/Applet -r org.kde.plasma.proxmox 2>/dev/null || true
elif command -v kpackagetool5 >/dev/null 2>&1; then
  kpackagetool5 -t Plasma/Applet -r org.kde.plasma.proxmox 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Remove QML plugin from the system Qt6 QML dir (requires sudo)
# ---------------------------------------------------------------------------
detect_sys_qt6_qml_dir() {
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
  find /usr/lib -maxdepth 5 -type d -name "qml" 2>/dev/null | grep 'qt6/qml$' | head -1 || true
}

SYS_QT6_QML_DIR="$(detect_sys_qt6_qml_dir)"
if [ -n "${SYS_QT6_QML_DIR:-}" ]; then
  SYS_MODULE_DIR="$SYS_QT6_QML_DIR/org/kde/plasma/proxmox"
  if [ -d "$SYS_MODULE_DIR" ]; then
    printf '%s\n' "Removing QML plugin from system: $SYS_MODULE_DIR"
    run_root rm -rf "$SYS_MODULE_DIR"
  fi
fi

# ---------------------------------------------------------------------------
# Remove QML plugin from user-local path
# ---------------------------------------------------------------------------
detect_qt6_qml_user_dir() {
  local arch_triplet=""
  if command -v dpkg-architecture >/dev/null 2>&1; then
    arch_triplet="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
  fi
  if [ -z "${arch_triplet:-}" ] && [ -n "${SYS_QT6_QML_DIR:-}" ]; then
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
if [ -d "$QML_MODULE_USER_DIR" ]; then
  printf '%s\n' "Removing QML plugin from user-local: $QML_MODULE_USER_DIR"
  rm -rf "$QML_MODULE_USER_DIR"
fi

# Remove stale Plasma workspace env file (from older install versions)
PLASMA_ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-workspace/env/proxmon-qml.sh"
if [ -f "$PLASMA_ENV_FILE" ]; then
  printf '%s\n' "Removing Plasma env file: $PLASMA_ENV_FILE"
  rm -f "$PLASMA_ENV_FILE"
fi

# Remove icons
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/proxmox-monitor.svg"
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/lxc.svg"

# Remove saved settings
rm -rf "${HOME}/.config/proxmox-plasmoid" || true

printf '%s\n' "Uninstallation complete!"
