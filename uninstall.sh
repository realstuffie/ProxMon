#!/bin/bash
set -euo pipefail

printf '%s\n' "Uninstalling Proxmox Monitor Plasmoid..."

# Remove plasmoid package
if command -v kpackagetool6 >/dev/null 2>&1; then
  kpackagetool6 -t Plasma/Applet -r org.kde.plasma.proxmox 2>/dev/null || true
elif command -v kpackagetool5 >/dev/null 2>&1; then
  kpackagetool5 -t Plasma/Applet -r org.kde.plasma.proxmox 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Detect user-local Qt6 QML path for legacy cleanup only.
# Current install keeps runtime plugin inside the plasmoid package.
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
if [ -d "$QML_MODULE_USER_DIR" ]; then
  printf '%s\n' "Removing legacy standalone QML plugin from user-local: $QML_MODULE_USER_DIR"
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

printf '\n'
printf '%s\n' "Uninstallation complete!"
printf '\n'
printf '%s\n' "You may need to restart Plasma for the widget to disappear:"
printf '%s\n' "  kquitapp6 plasmashell && kstart plasmashell"
printf '%s\n' "If that doesn't work on your distro, try:"
printf '%s\n' "  systemctl --user restart plasma-plasmashell.service"
printf '%s\n' "or log out/in."
printf '\n'
