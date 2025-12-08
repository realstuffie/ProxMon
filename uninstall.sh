#!/bin/bash

echo "Uninstalling Proxmox Monitor Plasmoid..."

# Remove plasmoid
kpackagetool6 -t Plasma/Applet -r org.kde.plasma.proxmox

# Remove icons
rm -f ~/.local/share/icons/hicolor/scalable/apps/proxmox-monitor.svg
rm -f ~/.local/share/icons/hicolor/scalable/apps/lxc.svg

# Remove saved settings
rm -rf ~/.config/proxmox-plasmoid

echo "Uninstallation complete!"
