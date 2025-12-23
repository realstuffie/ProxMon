#!/bin/bash

echo "Installing Proxmox Monitor Plasmoid..."

echo "Building native Proxmox API plugin..."

mkdir -p contents/lib/build
cmake -S contents/lib -B contents/lib/build -DCMAKE_BUILD_TYPE=Release || exit 1
cmake --build contents/lib/build || exit 1

# Stage runtime QML module into the plasmoid package
mkdir -p contents/lib/proxmox
cp contents/lib/proxmox/qmldir contents/lib/proxmox/qmldir || exit 1
cp contents/lib/build/libproxmoxclientplugin.so contents/lib/proxmox/ || exit 1

echo "Native plugin staged: contents/lib/proxmox/libproxmoxclientplugin.so"

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
