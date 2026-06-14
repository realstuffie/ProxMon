# ProxMon

A KDE Plasma 6 plasmoid to monitor your Proxmox VE servers directly from your desktop panel.

## Features

- **Real-time monitoring** — Node status (CPU, memory, uptime) with VM and LXC container tracking
- **VNC console** — GPU-accelerated in-widget VNC sessions for VMs with full keyboard, mouse, and scroll input
- **LXC terminal** — Native terminal emulator for containers with automatic resize
- **PBS backup status** — Inline backup results per VM/CT with configurable warning and stale thresholds
- **Multi-host support** — Monitor up to 5 Proxmox endpoints simultaneously
- **Power commands** — Start, stop, and restart VMs and containers
- **Desktop notifications** — State change alerts with rate limiting and filters
- **Secure** — API token auth, keychain integration, and trusted SSL certificate PEM/file support
- **Appearance controls** — Custom running, stopped, and node colors with live preview, card tint, and window opacity
- **Flexible compact label** — Show average CPU, running workloads, error state, or last update time in the panel
- **Theme integration** — Adapts to your Plasma theme with per-color fallback to theme defaults
- **Developer mode** — Triple-click footer for verbose logging

## Security

- **Keychain storage** — API token secrets are stored in your system keyring (Qtkeychain) and never written to disk in plaintext. They are read on demand and held in memory only for the duration of a request.
- **Isolated from the UI layer** — Credentials are never exposed to the QML/JavaScript layer. Auth tokens and VNC tickets are delivered directly between native C++ components and zeroed from memory immediately after use.
- **SSL/TLS** — Connections to Proxmox use HTTPS/WSS. You can supply your own CA certificate for self-signed setups. "Ignore SSL" disables all TLS verification and encryption — only enable it when **all** other options are exhausted.
- **Notification privacy** — Token identifiers are redacted from desktop notifications by default, so credentials don't appear in your notifications.
- **Known limitation** — The VNC console uses a local loopback socket to bridge between the native VNC client and the Proxmox WebSocket endpoint. There is a brief window where another local process could connect to that socket instead. In the worst case this causes a failed connection — no credentials can be extracted this way.

## Screenshots

### Expanded View

<p align="center">
  <img src="screenshots/widget-expanded.png" alt="Expanded View" />
</p>

<p align="center"><em>Expanded view showing nodes, VMs, and containers</em></p>

### Panel View

<p align="center">
  <img src="screenshots/widget-pannel.png" alt="Panel View" width="420" />
</p>

<p align="center"><em>Compact panel view showing CPU usage</em></p>

### Settings

<p align="center">
  <img src="screenshots/Settings.png" alt="Settings" />
</p>

## Requirements

- KDE Plasma 6.0+
- Proxmox VE 7.0+ with API access

### Known bugs / limitations

- If you configured the widget in older versions, your API token secret may have been stored under a slightly different keyring key (e.g. due to host casing/whitespace). Newer versions auto-migrate legacy keys, but if the widget shows "Missing Token Secret", re-enter the secret in settings and click **Update Keyring**, then wait a moment.

- **VNC console — resize down not honoured**: shrinking the console window sends a VNC `SetDesktopSize` request, but QEMU's VNC server does not honour shrink requests regardless of the video backend. The display will scale to fit the smaller window (letterboxed) while the remote framebuffer stays at the previous resolution. Resize up works correctly. A workaround using the QEMU guest agent is planned.

- **LXC terminal — resize reflow not guaranteed**: resizing the terminal window sends `SIGWINCH` to the running process, but reflow behaviour varies by application. Some programs (e.g. shells and editors) will redraw correctly; others may not reflow their output until the next render or keypress or not at all. This is a quirk of most terminal emulators and is not specific to ProxMon.

## Installation

```bash
git clone https://github.com/realstuffie/ProxMon.git
cd ProxMon
bash install.sh
```

The script handles dependencies, builds the native plugin, installs the plasmoid, and sets up an auto-rebuild watcher that detects library changes (e.g. libplasma soname bumps) and rebuilds automatically.

Re-run with `--no-deps` to skip dependency installation on subsequent installs.

### Upgrading

```bash
cd ProxMon
git pull
bash install.sh --no-deps
```

## Proxmox API Token Setup

1. Go to **Datacenter → Permissions → API Tokens → Add**
2. Set a user and token ID (e.g. `root@pam` / `plasma-monitor`)
3. Copy the secret immediately — shown only once

### Minimum Permissions

| Permission          | Path                 | Purpose                              |
|---------------------|----------------------|--------------------------------------|
| `Sys.Audit`         | `/`                  | Read node status                     |
| `VM.Audit`          | `/vms`               | Read VM & container status           |

### Power Action Permissions

| Permission      | Path   | Purpose                         |
|-----------------|--------|---------------------------------|
| `VM.PowerMgmt`  | `/vms` | Start/stop/reboot VMs and CTs   |
| `Sys.PowerMgmt` | `/`    | Required in some role setups    |

### Console Permissions

| Permission      | Path   | Purpose                              |
|-----------------|--------|--------------------------------------|
| `VM.Console`    | `/vms` | Open VNC console for VMs             |
| `VM.Console`    | `/vms` | Open terminal for LXC containers     |

> **Privilege Separation note:** If your token has privilege separation enabled, effective permissions are the *intersection* of user and token permissions. You must grant roles to both, or disable privilege separation.

### Example: Dedicated Monitoring User

```bash
pveum user add monitor@pve -comment "Plasma Monitor"
pveum aclmod / -user monitor@pve -role PVEAuditor
pveum user token add monitor@pve plasma-monitor
```

## Proxmox Backup Server API Token Setup

1. Go to **Configuration → Access Control → Users → Add** and create a user e.g. `proxmon@pbs`
2. Go to **Configuration → Access Control → API Tokens → Add**, select the user and set a token name
3. Go to **Configuration → Access Control → Permissions → Add**
   - Path: `/datastore/YourDatastoreName`
   - Role: `DatastoreReader`
   - Copy the token secret — shown only once

### Minimum PBS Permissions

| Role                         | Path                | Purpose                              |
|------------------------------|---------------------|--------------------------------------|
| `DatastoreReader` (built-in) | `/datastore/<name>` | Read datastore and snapshot listings |

Token ID format: `user@pbs!tokenname`

## Configuration

1. Right-click the widget → **Configure Proxmox Monitor**
2. **Connection tab**: Host, Port, Token ID (`user@realm!tokenname`), Token Secret, SSL verification, trusted cert PEM or file path, Refresh Interval
   - Click **Update Keyring** after changing the secret
3. **Behavior tab**: Sorting, compact panel label mode (Avg CPU, running workloads, error state, or last update time), Notifications, Rate Limiting, Privacy (redact token fragments in notifications)
4. **Appearance tab**: Custom running/stopped/node colors, per-color hex or RGB input, card tint opacity, window opacity, and a live preview with one-click theme defaults

## Troubleshooting

### Connection errors / "!" indicator

- Verify token ID format: `user@realm!tokenname`
- For self-signed Proxmox certs, prefer adding the Proxmox root CA PEM (usually `/etc/pve/pve-root-ca.pem`) in widget settings before using **Ignore SSL**.
- Trusted certs only fix issuer trust; the configured host must still match a hostname or IP SAN on the server certificate.
- If your Proxmox cert is valid only for an internal hostname, add local DNS or an `/etc/hosts` entry and use that hostname in the widget instead of the raw IP.
- Check port 8006 is accessible.

### Icons not showing

```bash
cp contents/icons/*.svg ~/.local/share/icons/hicolor/scalable/apps/
gtk-update-icon-cache ~/.local/share/icons/hicolor/
quitapp6 plasmashell && kstart plasmashell
```

### Widget not appearing after install

```bash
kquitapp6 plasmashell && kstart plasmashell
```

If your distro blocks loading the packaged native plugin path:

```bash
bash install.sh --install-standalone-qml-module
```

### Logs

```bash
journalctl --user -f | grep -i proxmox
```

### Auto-rebuild watcher

```bash
systemctl --user status proxmox-plasmoid-rebuild.path
tail -f ~/.local/share/plasma/plasmoids/org.kde.plasma.proxmox/rebuild.log
```

## Uninstall

```bash
./uninstall.sh
```

Or manually:

```bash
kpackagetool6 -t Plasma/Applet -r org.kde.plasma.proxmox
rm -f ~/.local/share/icons/hicolor/scalable/apps/proxmox-monitor.svg
rm -f ~/.local/share/icons/hicolor/scalable/apps/lxc.svg
```

## Contributing

Open an issue with your KDE Plasma version (`plasmashell --version`), Proxmox VE version, steps to reproduce, and relevant log output.

## License

GPL-3.0 or later. See [LICENSE](LICENSE) for details.

## Changelog

### v0.7.3

- Refactor: node card header — status pill replaces computer icon, always-visible VM/CT counts
- Refactor: uptime now shows alarm icon, JetBrains Mono font, right-aligned in stats row
- Chore: remove legacy secret key candidate fallback chain
- Fix: isolate task poll requests from refresh cancellation to prevent stuck busy spinner
- Fix: clear busy spinner via checkStateChanges safety-net when onActionReply never fires
- Fix: UI alignment and field sizing across all config tabs for consistent cross-distro rendering
- Fix: move SSL toggles into single/multi-host sections; hide PBS fields when disabled
- Fix: add Delete Default button to connection defaults section
- Fix: label and dropdown alignment in Behavior and Appearance tabs
- Refactor: drop VNC remote resize (SetDesktopSize); simplify encoding string
- Fix: ctrl+key keysym recovery in VNC console when modifiers suppress text
- Fix: use explicit_bzero for ticket zeroization; null client-data slot before free
- Chore: update lxc/vm icons

### v0.7.2

- Fix: bundle JetBrains Mono for consistent cross-distro font metrics
- Fix: monospace text vertical centering in VM and LXC rows

Tested on Ubuntu 26 (KDE 6.6.4), Fedora 44 (KDE 6.6.5), Manjaro (KDE 6.6.5), openSUSE Tumbleweed (KDE 6.6.5)

### v0.7.1

- Fix: normalize row spacing, monospace stats labels, vertical centering in VM and LXC rows
- Fix: tighten stats block and mem label width to close visual gap between cpu/mem and PBS column
- Fix: add left margin to power buttons; reduce row left margin 8→4px
- Fix: extend backup age display to weeks (7d+) and years (52w+)
- Fix: checksum-based install sync; skip kpackagetool re-register if already installed
- Fix: move notification toggle to Behavior tab; bind via bool prop
- Fix: treat task WARNINGS as non-fatal

### v0.7.0

- Power actions toggle — enable/disable start/stop/restart buttons per endpoint
- LXC terminal: reworked data path with copy/paste support
- SSL warning text now uses bright red; security warnings added to ignore SSL toggles
- Renamed Console section to Features in behavior settings
- Install: extended auto-rebuild watcher to cover Qt6, libvncclient, qtermwidget6
- Install: added `--no-watcher` flag to skip auto-rebuild watcher setup
- Build: mold linker support

### v0.6.1

- Fix: closing the VNC console window during connection no longer crashes plasmashell (use-after-free + deadlock in teardown path)
- Fix: PBS in-flight requests are now correctly aborted by `cancelAll()` alongside PVE requests
- Fix: per-endpoint SSL certificate is now correctly passed to VNC and TTY proxy requests in multi-host mode
- Docs: added Security section to README

### v0.6.0

- VNC console for VMs — GPU-accelerated rendering, full keyboard/mouse/scroll, dynamic resize, auto-reconnect
- LXC terminal — native terminal emulator with automatic resize and wake support for silent containers
- Credentials handled securely in C++ — tickets and auth headers never exposed to QML
- Multi-host trusted cert toggle — shared or per-endpoint
- Various config and stability fixes
- Bump bundled QtKeychain

### Credits

- [Proxmox VE](https://www.proxmox.com/) - Virtualization platform
- [KDE Plasma](https://kde.org/plasma-desktop/) - Desktop environment
- [noVNC](https://github.com/novnc/noVNC) — DOM key table ported from `core/input/domkeytable.js`, licensed under MPL 2.0
- [QTermWidget](https://github.com/lxqt/qtermwidget) — LXC terminal emulator widget, licensed under LGPL-2.0+
- [LibVNCClient](https://github.com/LibVNC/libvncserver) — VNC client support, licensed under LGPL-2.1
- [QtKeychain](https://github.com/frankosterfeld/qtkeychain) — secure credential storage, licensed under MIT
