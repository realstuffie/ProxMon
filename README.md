A KDE Plasma 6 plasmoid to monitor your Proxmox VE servers directly from your desktop panel.

## Features

- 📊 **Real-time monitoring** - Node status (CPU, Memory, Uptime)
- 🖥️ **Virtual Machine tracking** - See all VMs and their status
- 📦 **LXC Container support** - Monitor containers alongside VMs
- 🖧 **Multi-node clusters** - Support for multiple Proxmox nodes
- 🔄 **Auto-refresh** - Configurable refresh interval
- 🔔 **Desktop notifications** - Alerts when VMs/CTs change state (optional rate limiting to reduce spam)
- 🎯 **Notification filters** - Whitelist/blacklist specific VMs/CTs
- ☰ **Flexible sorting** - Sort by status, name, or ID
- 🔒 **Secure** - API token authentication with SSL support
- 🎨 **Theme integration** - Adapts to your Plasma theme
- ⚙️ **Easy configuration** - GUI-based setup
- 🔧 **Developer mode** - Triple-click footer for verbose logging

### Planned Features

- [ ] Remote commands (Start, Stop, Restart)
- [ ] Resource usage graphs
- [ ] Storage monitoring
- [ ] Backup status
- [ ] Kde5 Compatible Version



### Known Bugs/Limitations

- If you configured the widget in older versions, your API token secret may have been stored under a slightly different keyring key (e.g., due to host casing/whitespace). Newer versions auto-migrate legacy keys, but if the widget shows “Missing Token Secret”, re-enter the secret in the settings and click Apply.

## Screenshots

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
  <img src="screenshots/Settings.png" alt="Settings" width="800">
  <br>
  <em>Configuration dialog</em>
</p>
## Requirements

- KDE Plasma 6.0+
- Proxmox VE 7.0+ with API access
- No external CLI tools required for API calls (uses native Qt networking)

## Installation

### Quick Install (Recommended)

```bash
# Clone the repository
git clone https://github.com/realstuffie/ProxMon.git
cd ProxMon

# Run the install script
bash install.sh
```

> Note: Build output is not committed to the repository. The install script builds the native plugin in a temporary directory and stages the resulting `.so` into the plasmoid package.

### Manual Installation

```bash
# Clone the repository
git clone https://github.com/realstuffie/ProxMon.git
cd ProxMon

# Install the plasmoid
kpackagetool6 -t Plasma/Applet -i .

# Install icons
mkdir -p ~/.local/share/icons/hicolor/scalable/apps/
cp icons/*.svg ~/.local/share/icons/hicolor/scalable/apps/

# Update icon cache
gtk-update-icon-cache ~/.local/share/icons/hicolor/ 2>/dev/null || true
```

### Upgrading

```bash
cd ProxMon
git pull
kpackagetool6 -t Plasma/Applet -u .
```

## Proxmox API Token Setup

1. Log into your Proxmox web interface
2. Go to **Datacenter → Permissions → API Tokens**
3. Click **Add**
4. Configure the token:
   - **User**: Select a user (e.g., `root@pam` or create a dedicated monitoring user)
   - **Token ID**: Enter a name (e.g., `plasma-monitor`)
   - **Privilege Separation**: Uncheck for full access, or configure specific permissions
5. Click **Add**
6. **Important**: Copy the displayed secret immediately (shown only once!)

### Minimum Required Permissions

If using privilege separation, the token needs:

| Permission | Path | Purpose |
|------------|------|---------|
| `Sys.Audit` | `/` | Read node status |
| `VM.Audit` | `/vms` | Read VM/CT status |

### Optional: Permissions for Start/Stop/Reboot actions

If you want to use the widget’s power actions (Start/Shutdown/Reboot), audit permissions are **not** sufficient. Grant power-management privileges:

| Permission | Path | Purpose |
|------------|------|---------|
| `VM.PowerMgmt` | `/vms` (or more specific) | Start/stop/reboot QEMU VMs |
| `Sys.PowerMgmt` | `/` (or more specific) | Required for power actions in some setups/roles |

Recommended approach:
- Keep a read-only monitoring token with `Sys.Audit` + `VM.Audit`
- Create a separate token/user for actions with `VM.PowerMgmt` + `Sys.PowerMgmt` at the minimum scope you want

### Example: Create a Dedicated Monitoring User

```bash
# On your Proxmox server
pveum user add monitor@pve -comment "Plasma Monitor"
pveum aclmod / -user monitor@pve -role PVEAuditor
pveum user token add monitor@pve plasma-monitor
```

## Configuration

1. **Add the widget** to your panel or desktop
2. **Right-click** → **Configure Proxmox Monitor**
3. **Connection tab**:
   - **Host**: Proxmox IP or hostname (e.g., `192.168.1.100`)
   - **Port**: API port (default: `8006`)
   - **API Token ID**: Format `user@realm!tokenname` (e.g., `root@pam!plasma-monitor`)
   - **API Token Secret**: The secret from token creation
   - **Update Keyring**: If you changed the secret, click **Update Keyring**. The widget stores it temporarily and migrates it into the system keyring on next load.
   - **Forget**: Clears the secret field (does **not** delete existing keyring entries).
   - **Refresh Interval**: Update frequency in seconds (default: `30`)
   - **Ignore SSL**: Enable for self-signed certificates
4. **Behavior tab**:
   - **Default Sorting**: How to sort VMs/CTs
   - **Notifications**: Configure state change alerts

### Notification Filtering

### Notification Rate Limiting
To reduce notification spam during flapping or frequent refresh/retry cycles, you can rate limit repeated notifications:
- Enable/disable in **Behavior tab → Rate Limiting**
- Configure the minimum interval in seconds between duplicates (default: 120s)

You can filter which VMs/CTs trigger notifications:

| Mode | Description |
|------|-------------|
| **All** | Notify for all state changes |
| **Whitelist** | Only notify for specified VMs/CTs |
| **Blacklist** | Notify for all except specified VMs/CTs |

Filter supports:
- Exact names: `web-server`
- VM/CT IDs: `100`
- Wildcards: `*-prod`, `db-*`, `*test*`

## Usage

### Panel View (Compact)
- Shows average CPU usage across all nodes
- Animated icon during refresh
- Click to expand

### Expanded View
- **Node cards**: CPU, memory, uptime for each node
- **Click node**: Expand/collapse VM and container lists
- **Status indicators**: Green = running, gray = stopped
- **Footer**: Quick stats and last update time

### Developer Mode
Triple-click the footer to enable developer mode:
- Verbose logging to journal (`journalctl --user -f`)
- Anonymized data (for screenshots)
- Test notification button

## Troubleshooting

### Widget shows "!" or connection error

1. **Verify credentials**:
   - Ensure token ID format is `user@realm!tokenname`
   - If you rotated the token secret, re-enter it and click **Update Keyring**, then reopen the widget

2. **SSL issues**: Enable "Ignore SSL" for self-signed certificates

3. **Firewall**: Ensure port 8006 is accessible

### Icons not showing

```bash
# Reinstall icons
cp icons/*.svg ~/.local/share/icons/hicolor/scalable/apps/
gtk-update-icon-cache ~/.local/share/icons/hicolor/

# Log out and back in, or restart Plasma
plasmashell --replace &
```

### Widget not appearing after install

```bash
# Restart Plasma
plasmashell --replace &

# Or log out and back in
```

### Check logs

```bash
# View plasmoid logs
journalctl --user -f | grep -i proxmox
```

## Uninstall

### Using Script

```bash
./uninstall.sh
```

### Manual Uninstall

```bash
# Remove plasmoid
kpackagetool6 -t Plasma/Applet -r org.kde.plasma.proxmox

# Remove icons
rm -f ~/.local/share/icons/hicolor/scalable/apps/proxmox-monitor.svg
rm -f ~/.local/share/icons/hicolor/scalable/apps/lxc.svg

# Remove saved settings (optional)
rm -rf ~/.config/proxmox-plasmoid/
```

## Contributing

Contributions are welcome! Please feel free to:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Reporting Bugs

Please open an issue with:
- KDE Plasma version (`plasmashell --version`)
- Proxmox VE version
- Steps to reproduce
- Relevant log output

## License

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version.

See [LICENSE](LICENSE) for details.

## Credits

- [Proxmox VE](https://www.proxmox.com/) - Virtualization platform
- [KDE Plasma](https://kde.org/plasma-desktop/) - Desktop environment

## Changelog

### v0.4.0
- Reliability: cancel/abort in-flight requests during refresh/timeouts
- Credentials: keyring secret lookup normalized + legacy key auto-migration
- Notifications: rate limiting to reduce spam
- Various UI/behavior improvements

### v0.3.3
- Repository hygiene: add/update `.gitignore`
- Minor README/install script improvements

### v0.3.2
- Refresh of screenshots
- Minor bug fixes

### v0.3.1
- minor bug fixes

### v0.3.0
- Added notification system with filtering
- Added whitelist/blacklist support for notifications
- Fixed security issues (shell injection)
- Improved theme integration
- Added developer mode

### v0.2.0
- Multi-node cluster support
- Collapsible node sections
- Improved UI

### v0.1.0
- Initial release
