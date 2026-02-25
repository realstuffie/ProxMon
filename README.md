A KDE Plasma 6 plasmoid to monitor your Proxmox VE servers directly from your desktop panel.

## Features

- 📊 **Real-time monitoring** - Node status (CPU, Memory, Uptime)
- 🖥️ **Virtual Machine tracking** - See all VMs and their status
- 📦 **LXC Container support** - Monitor containers alongside VMs
- 🖧 **Multi-node clusters** - Support for multiple Proxmox nodes
- 🔄 **Auto-refresh** - Configurable refresh interval
- 🔔 **Desktop notifications** - Alerts when VMs/CTs change state (optional rate limiting to reduce spam)
- 🎯 **Notification filters** - Whitelist/blacklist specific VMs/CTs
- ↕️ **Flexible sorting** - Sort by status, name, or ID
- 🔒 **Secure** - API token authentication with SSL support
- 🎨 **Theme integration** - Adapts to your Plasma theme
- ⚙️ **Easy configuration** - GUI-based setup
- 🔧 **Developer mode** - Triple-click footer for verbose logging
- 🔌 **Remote Power Commands** Start, Stop, Restart 

### Planned Features
- [ ] Resource usage graphs
- [ ] Storage monitoring
- [ ] Backup status
- [ ] Kde5 Compatible Version

### Known Bugs/Limitations

- If you configured the widget in older versions, your API token secret may have been stored under a slightly different keyring key (e.g., due to host casing/whitespace). Newer versions auto-migrate legacy keys, but if the widget shows “Missing Token Secret”, re-enter the secret in the settings and click **Update Keyring**, then wait a moment (the widget refreshes shortly after config changes).

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
| `VM.Audit` | `/vms` | Read VM & container status (QEMU + LXC) |

### Optional: Permissions for Start/Stop/Reboot actions

If you want to use the widget’s power actions (Start/Shutdown/Reboot), audit permissions are **not** sufficient. Grant power-management privileges:

| Permission | Path | Purpose |
|------------|------|---------|
| `VM.PowerMgmt` | `/vms` (or more specific) | Start/stop/reboot VMs and containers (QEMU + LXC) |
| `Sys.PowerMgmt` | `/` (or more specific) | Required for power actions in some setups/roles |

Recommended approach:
- Keep a read-only monitoring token with `Sys.Audit` + `VM.Audit`
- Create a separate token/user for actions with `VM.PowerMgmt` (+ `Sys.PowerMgmt` only if required in your ACL/role setup) at the minimum scope you want

Note: Proxmox ships built-in roles like `PVEAuditor` (read-only) and `PVEVMUser` (includes `VM.PowerMgmt`). You can also create minimal custom roles.

#### Note on Privilege Separation (common misconfiguration)

If you create the API token with **Privilege Separation** enabled (`-privsep 1`), the token will *not* automatically inherit the user's ACLs.

Per Proxmox docs, the effective permissions are the **intersection** of the user permissions and the token permissions. This means you must grant roles to both the **user** and the **token** (or disable privilege separation for “full privileges”).

Example:
```bash
# Create token with separated privileges
pveum user token add joe@pve monitoring -privsep 1

# Grant read-only role to the token (and ensure the user also has it)
pveum acl modify /vms -token 'joe@pve!monitoring' -role PVEAuditor
```

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
   - **Update Keyring**: If you changed the secret, click **Update Keyring**. The widget stores it temporarily and migrates it into the system keyring on next load. The widget will refresh shortly after config changes (debounced).
     - If the widget still doesn’t pick up new auth settings, restart Plasma (plasmashell) or remove/re-add the widget to force a full reload.
   - **Forget**: Clears the secret field (does **not** delete existing keyring entries).
   - **Refresh Interval**: Update frequency in seconds (default: `30`)
   - **Ignore SSL**: Enable for self-signed certificates
4. **Behavior tab**:
   - **Default Sorting**: How to sort VMs/CTs
   - **Notifications**: Configure state change alerts

### Notification Rate Limiting

To reduce notification spam during flapping or frequent refresh/retry cycles, you can rate limit repeated notifications:
- Enable/disable in **Behavior tab → Rate Limiting**
- Configure the minimum interval in seconds between duplicates (default: 120s)

### Notification Privacy (redaction)

By default, notifications will redact sensitive identity fragments if they appear in text (for example within task UPIDs):
- **Behavior tab → Privacy → Redact user@realm and token ID in notifications** (default: enabled)
- Replaces patterns like `user@realm!tokenid` with `REDACTED@realm!REDACTED`

## Usage

### Panel View (Compact)
- Shows average CPU usage across all nodes
- Animated icon during refresh
- Click to expand

### Expanded View
- **Node cards**: CPU, memory, uptime for each node
- **Click node**: Expand/collapse VM and container lists
- **Status indicators**: Green = running, gray = stopped
- **Power actions**: Icon buttons (Start/Shutdown/Reboot) on each running VM/CT (requires `VM.PowerMgmt`)
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

### v0.4.1
- Packaging: native QML plugin is now staged under `contents/qml/org/kde/plasma/proxmox/` (more reliable module discovery on Plasma 6)
- Install script: cross-distro improvements (kpackagetool 5/6 support, safer option detection, XDG icon paths)
- Install script: optional `--install-deps` mode with root escalation via root/sudo/doas/su (best-effort, distro-dependent package names)
- Docs: added dev notes on QML module packaging and verification
- UI: VM/CT row layout polish (CPU|Mem alignment + tighter spacing)
- UI: Power action buttons now use icon ToolButtons with tooltips + subtle hover highlight
- UI: Right-aligned action buttons with protection from overlay scrollbar overlap
- Notifications: add privacy toggle to redact `user@realm!tokenid` fragments (default: on)

### v0.4.0
- Reliability: cancel/abort in-flight requests during refresh/timeouts
- Credentials: keyring secret lookup normalized + legacy key auto-migration
- Notifications: rate limiting to reduce spam
- Various UI/behavior improvements
