#!/bin/bash

printf '%s\n' "Installing Proxmox Monitor Plasmoid..."

printf '%s\n' "Building native Proxmox API plugin..."

# Build out-of-source to avoid polluting the repo with build artifacts
BUILD_DIR="$(mktemp -d -t proxmon-build-XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

cmake -S contents/lib -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release || exit 1
cmake --build "$BUILD_DIR" || exit 1

# Stage runtime QML module into the plasmoid package
mkdir -p contents/lib/proxmox
cp contents/lib/proxmox/qmldir contents/lib/proxmox/qmldir || exit 1
cp "$BUILD_DIR/libproxmoxclientplugin.so" contents/lib/proxmox/ || exit 1

printf '%s\n' "Native plugin staged: contents/lib/proxmox/libproxmoxclientplugin.so"

# Install plasmoid
kpackagetool6 -t Plasma/Applet -i . 2>/dev/null || \
kpackagetool6 -t Plasma/Applet -u .

# Install icons
mkdir -p ~/.local/share/icons/hicolor/scalable/apps/
cp icons/*.svg ~/.local/share/icons/hicolor/scalable/apps/

# Update icon cache
gtk-update-icon-cache ~/.local/share/icons/hicolor/ 2>/dev/null || true

printf '\n'
printf '%s\n' "Installation complete!"
printf '\n'
printf '%s\n' "To add the widget:"
printf '%s\n' "  1. Right-click on your panel"
printf '%s\n' "  2. Click 'Add Widgets'"
printf '%s\n' "  3. Search for 'Proxmox'"
printf '%s\n' "  4. Drag to panel"
printf '\n'
printf '%s\n' "You may need to restart Plasma:"
printf '%s\n' "  kquitapp6 plasmashell && kstart plasmashell"
