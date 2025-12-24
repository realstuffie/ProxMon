#!/bin/bash
set -euo pipefail

printf '%s\n' "Uninstalling Proxmox Monitor Plasmoid..."

# Remove plasmoid
kpackagetool6 -t Plasma/Applet -r org.kde.plasma.proxmox 2>/dev/null || true

# Remove icons
rm -f ~/.local/share/icons/hicolor/scalable/apps/proxmox-monitor.svg
rm -f ~/.local/share/icons/hicolor/scalable/apps/lxc.svg

# Remove saved settings
rm -rf ~/.config/proxmox-plasmoid || true

printf '%s\n' "Uninstallation complete!"
