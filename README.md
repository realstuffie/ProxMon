    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.


# Proxmox Monitor - KDE Plasma 6 Widget

A KDE Plasma 6 plasmoid to monitor your Proxmox VE servers directly from your desktop panel.

## Features

- 📊 Real-time node status (CPU, Memory, Uptime)
- 🖥️ Virtual Machine monitoring
- 📦 LXC Container monitoring
- 🔄 Auto-refresh with configurable interval
- ⚙️ Easy configuration via GUI
- 🎨 Dark theme support
- 🔒 SSL support (with option to skip verification)

### Screenshots

<p align="center">
  <img src="screenshots/widget-expanded.png" alt="Expanded View" width="400">
  <br>
  <em>Expanded view showing nodes, VMs, and containers</em>
</p>

<p align="center">
  <img src="screenshots/widget-pannel.png" alt="Panel View" width="200">
  <br>
  <em>Compact panel view showing CPU usage</em>
</p>

<p align="center">
  <img src="screenshots/settings.png" alt="Settings" width="400">
  <br>
  <em>Configuration dialog</em>
</p>






## Requirements

- KDE Plasma 6
- Proxmox VE server with API access
- `curl` installed

## Installation

### From Source

    # Clone the repository
    git clone https://github.com/YOUR_USERNAME/plasma-proxmox-monitor.git
    cd plasma-proxmox-monitor

    # Install the plasmoid
    kpackagetool6 -t Plasma/Applet -i .

    # Install icons
    mkdir -p ~/.local/share/icons/hicolor/scalable/apps/
    cp icons/*.svg ~/.local/share/icons/hicolor/scalable/apps/

### Manual Installation

    # Copy to plasmoids directory
    cp -r . ~/.local/share/plasma/plasmoids/org.kde.plasma.proxmox

    # Install icons
    mkdir -p ~/.local/share/icons/hicolor/scalable/apps/
    cp icons/*.svg ~/.local/share/icons/hicolor/scalable/apps/

## Proxmox API Token Setup

1. Log into your Proxmox web interface
2. Go to **Datacenter → Permissions → API Tokens**
3. Click **Add**
4. Select a user (e.g., `root@pam` or create a dedicated user)
5. Enter a Token ID (e.g., `monitoring`)
6. Uncheck **Privilege Separation** for full access (or configure specific permissions)
7. Click **Add** and copy the displayed secret (shown only once!)

### Minimum Required Permissions

If using privilege separation, the token needs these permissions:
- `Sys.Audit` on `/`
- `VM.Audit` on `/vms`

## Configuration

1. Add the widget to your panel
2. Right-click → **Configure Proxmox Monitor**
3. Enter your settings:
   - **Host**: Your Proxmox IP or hostname
   - **Port**: API port (default: 8006)
   - **API Token ID**: `user@realm!tokenname` format
   - **API Token Secret**: The secret from token creation
   - **Refresh Interval**: How often to update (seconds)
   - **Ignore SSL**: Check if using self-signed certificate


### Panel View
Shows CPU usage percentage in compact mode.

### Expanded View
Shows full server status including:
- Node status and resources
- List of VMs with status
- List of containers with status

## Troubleshooting

### Widget shows "ERR"
- Check your Proxmox host is reachable
- Verify API token credentials
- Check if SSL verification is causing issues

### Icons not showing

    # Reinstall icons
    cp icons/*.svg ~/.local/share/icons/hicolor/scalable/apps/
    gtk-update-icon-cache ~/.local/share/icons/hicolor/

### Test API connection

    curl -k -s 'https://YOUR_HOST:8006/api2/json/nodes' \
      -H 'Authorization: PVEAPIToken=user@realm!token=SECRET'

## Uninstall

    kpackagetool6 -t Plasma/Applet -r org.kde.plasma.proxmox
    rm ~/.local/share/icons/hicolor/scalable/apps/proxmox-monitor.svg
    rm ~/.local/share/icons/hicolor/scalable/apps/lxc.svg

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Credits

- Proxmox VE - https://www.proxmox.com/
- KDE Plasma - https://kde.org/plasma-desktop/
