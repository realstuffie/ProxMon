#!/bin/bash
set -euo pipefail

if command -v kpackagetool6 >/dev/null 2>&1; then
  kpackagetool6 -t Plasma/Applet -r org.kde.plasma.proxmox 2>/dev/null || true
elif command -v kpackagetool5 >/dev/null 2>&1; then
  kpackagetool5 -t Plasma/Applet -r org.kde.plasma.proxmox 2>/dev/null || true
fi
printf '%s\n' "[ pkg  ] Plasmoid package removed."

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
  printf '%s\n' "[ qml  ] Removing legacy standalone QML module..."
  rm -rf "$QML_MODULE_USER_DIR"
fi

PLASMA_ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-workspace/env/proxmon-qml.sh"
[ -f "$PLASMA_ENV_FILE" ] && rm -f "$PLASMA_ENV_FILE"

rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/proxmox-monitor.svg"
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/lxc.svg"
printf '%s\n' "[ icons] Icons removed."

rm -rf "${HOME}/.config/proxmox-plasmoid" || true

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user disable --now proxmox-plasmoid-rebuild.path 2>/dev/null || true
  systemctl --user disable --now proxmox-plasmoid-rebuild.service 2>/dev/null || true
  systemctl --user daemon-reload
  rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/proxmox-plasmoid-rebuild.path"
  rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/proxmox-plasmoid-rebuild.service"
  printf '%s\n' "[ watch] Auto-update watcher disabled."
fi

rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/org.kde.plasma.proxmox"

printf '\n'
printf '%s\n' "Uninstall complete."
printf '\n'
printf '%s\n' "  Restart Plasma to remove the widget:"
printf '%s\n' "    kquitapp6 plasmashell && kstart plasmashell"
printf '%s\n' "    or simply log out and back in."
printf '\n'
