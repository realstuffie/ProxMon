#!/bin/bash

echo "Installing Proxmox Monitor Plasmoid..."

# Install plasmoid
kpackagetool6 -t Plasma/Applet -i . 2>/dev/null || \
kpackagetool6 -t Plasma/Applet -u .

# Install icons
mkdir -p ~/.local/share/icons/hicolor/scalable/apps/
cp icons/*.svg ~/.local/share/icons/hicolor/scalable/apps/

# Update icon cache
gtk-update-icon-cache ~/.local/share/icons/hicolor/ 2>/dev/null

echo ""
echo "Installation complete!"
echo ""
echo "To add the widget:"
echo "  1. Right-click on your panel"
echo "  2. Click 'Add Widgets'"
echo "  3. Search for 'Proxmox'"
echo "  4. Drag to panel"
echo ""
echo "You may need to restart Plasma:"
echo "  kquitapp6 plasmashell && kstart plasmashell"
