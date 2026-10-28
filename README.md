<div align="center">

<img src="icons/proxmox-monitor.svg" width="88" alt="ProxMon logo" />

<h1>ProxMon</h1>

<p><strong>Monitor your Proxmox VE servers straight from the KDE Plasma panel.</strong></p>

<p>Live node, VM &amp; container stats · in-widget VNC &amp; LXC consoles · PBS backup status · multi-host.</p>

<p>
  <img src="https://img.shields.io/badge/version-0.9.2-1d99f3" alt="Version" />
  <img src="https://img.shields.io/badge/license-GPL--3.0--or--later-4caf50" alt="License" />
  <img src="https://img.shields.io/badge/KDE%20Plasma-6.0%2B-1d99f3?logo=kde&amp;logoColor=white" alt="KDE Plasma 6" />
  <img src="https://img.shields.io/badge/Proxmox%20VE-7.0%2B-e57000?logo=proxmox&amp;logoColor=white" alt="Proxmox VE 7+" />
  <img src="https://img.shields.io/badge/built%20with-C%2B%2B%20%2F%20QML-00599C?logo=qt&amp;logoColor=white" alt="C++ / QML" />
  <img src="https://img.shields.io/badge/platform-Linux-333?logo=linux&amp;logoColor=white" alt="Linux" />
  <a href="https://launchpad.net/~realstuffie/+archive/ubuntu/proxmon"><img src="https://img.shields.io/badge/Ubuntu%2026.04-PPA-e95420?logo=ubuntu&amp;logoColor=white" alt="Ubuntu 26.04 PPA" /></a>
  <a href="https://github.com/realstuffie/ProxMon/wiki"><img src="https://img.shields.io/badge/docs-wiki-1d99f3?logo=gitbook&amp;logoColor=white" alt="Documentation wiki" /></a>
</p>

<p>
  <a href="#quick-start">Install</a> ·
  <a href="https://github.com/realstuffie/ProxMon/wiki">Wiki</a> ·
  <a href="#security">Security</a> ·
  <a href="#troubleshooting">Troubleshooting</a>
</p>

</div>

---

<div align="center">
<table>
  <tr>
    <td rowspan="2" align="center" valign="middle"><div align="center">
      <img src="screenshots/widget-expanded-v0.8.4.png" alt="Expanded view" width="330" /><br />
      <em>Expanded view: nodes, VMs &amp; containers</em>
    </div></td>
    <td align="center" valign="top"><div align="center">
      <img src="screenshots/widget-pannel.png" alt="Compact panel label" width="360" /><br />
      <em>Compact panel label</em>
    </div></td>
  </tr>
  <tr>
    <td align="center" valign="top"><div align="center">
      <img src="screenshots/Settings.png" alt="Configuration" width="360" /><br />
      <em>Configuration</em>
    </div></td>
  </tr>
</table>
</div>

---

## Features

| | |
| --- | --- |
| **Real-time monitoring** | Node status (CPU, memory, uptime) with VM and LXC container tracking |
| **VNC console** | GPU-accelerated in-widget VNC sessions with full keyboard, mouse, and scroll input |
| **LXC terminal** | Native terminal emulator for containers with automatic resize |
| **PBS backup status** | Inline backup results per VM/CT with configurable warning and stale thresholds |
| **Storage usage** | Per-node disk bars, the fullest store by default or the ones you name |
| **Multi-host** | Monitor up to 5 Proxmox endpoints simultaneously |
| **Power commands** | Start, stop, and restart VMs and containers |
| **Desktop notifications** | State-change alerts with rate limiting and filters |
| **Security controls** | API token auth, keychain storage, custom CA support, [scope and limitations below](#security) |
| **Appearance controls** | Custom running/stopped/node colors with live preview, card tint, window opacity |
| **Flexible panel label** | Show average CPU, running workloads, error state, or last update time |
| **Theme integration** | Adapts to your Plasma theme with per-color fallback to theme defaults |
| **Developer mode** | Triple-click the footer for verbose logging |

## Requirements

- KDE Plasma 6.0+
- Proxmox VE 7.0+ with API access

## Quick start

**Ubuntu 26.04.** The PPA has packages for `amd64` and `amd64v3`:

```bash
sudo add-apt-repository ppa:realstuffie/proxmon
sudo apt install proxmon
```

**Other distributions.** The script installs dependencies, builds the plugin and installs the widget:

```bash
git clone --recurse-submodules https://github.com/realstuffie/ProxMon.git
cd ProxMon
bash install.sh
```

Then restart Plasma with `kquitapp6 plasmashell && kstart plasmashell`, or log out and back in. If you installed with `install.sh` before and now want the package, run `bash uninstall.sh` first. Upgrading, uninstalling and the script options are on the [Installation](https://github.com/realstuffie/ProxMon/wiki/Installation) page.

## Set it up

1. **Create an API token** in Proxmox under **Datacenter → Permissions → API Tokens → Add**, and copy the secret. A read-only token needs `Sys.Audit` on `/` and `VM.Audit` on `/vms`. The full list, including power actions, consoles and Proxmox Backup Server, is on the [Proxmox Setup](https://github.com/realstuffie/ProxMon/wiki/Proxmox-Setup) page.
2. **Add the widget.** Right-click the panel, choose **Add Widgets** and search for "Proxmox".
3. **Configure it.** Right-click the widget and choose **Configure Proxmox Monitor**. Enter the host, port, token ID (`user@realm!tokenname`) and token secret.

## Configuration

| Tab | What it controls |
| --- | --- |
| **Connection** | Host, port, token ID and secret, SSL verification, trusted certificate, refresh interval |
| **Storage usage** | Node disk bars on or off per endpoint, and which storages are monitored |
| **Behavior** | Sorting, panel label mode, notifications, rate limiting, privacy |
| **Appearance** | Running, stopped and node colors, card tint, window opacity, live preview |
| **Keyring** | Where token secrets are stored: KWallet by default, or [KeePassXC](https://github.com/realstuffie/ProxMon/wiki/Using-KeePassXC) |

Every option is described in the [Configuration reference](https://github.com/realstuffie/ProxMon/wiki/Configuration-Reference).

## Security

- Token secrets go to your system keyring through QtKeychain, never to the plaintext configuration. They are read on demand and handled in C++, outside QML values.
- Connections use HTTPS and WSS. For a self-signed server, add its CA certificate. Turning on "Ignore SSL" skips certificate checks and allows impersonation.
- Token identifiers are redacted from desktop notifications by default.
- ProxMon does not isolate credentials from other processes running as your user, or from malicious code inside plasmashell.

The [Security model](https://github.com/realstuffie/ProxMon/wiki/Security-Model) page has the details and the limits.

## Documentation

All guides are in the [wiki](https://github.com/realstuffie/ProxMon/wiki):

- [Installation](https://github.com/realstuffie/ProxMon/wiki/Installation)
- [Proxmox Setup](https://github.com/realstuffie/ProxMon/wiki/Proxmox-Setup): API token, permissions, Proxmox Backup Server
- [Configuration reference](https://github.com/realstuffie/ProxMon/wiki/Configuration-Reference)
- [Using KeePassXC](https://github.com/realstuffie/ProxMon/wiki/Using-KeePassXC)
- [Security model](https://github.com/realstuffie/ProxMon/wiki/Security-Model)
- [Troubleshooting](https://github.com/realstuffie/ProxMon/wiki/Troubleshooting)
- [Developer Setup](https://github.com/realstuffie/ProxMon/wiki/Developer-Setup)

## Troubleshooting

- **"!" indicator or connection errors.** Check that the token ID looks like `user@realm!tokenname`, that port 8006 is reachable, and that a self-signed server's CA is added in the widget settings.
- **Widget missing after install.** Restart Plasma: `kquitapp6 plasmashell && kstart plasmashell`.
- **Logs.** `journalctl --user -f | grep -i proxmox`

More fixes are on the [Troubleshooting](https://github.com/realstuffie/ProxMon/wiki/Troubleshooting) page.

## Contributing

Open an issue with your KDE Plasma version (`plasmashell --version`), Proxmox VE version, steps to reproduce, and relevant log output. The [Developer Setup](https://github.com/realstuffie/ProxMon/wiki/Developer-Setup) page covers building and running the unit tests, and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) describes the design.

## Credits

- [Proxmox VE](https://www.proxmox.com/), virtualization platform
- [KDE Plasma](https://kde.org/plasma-desktop/), desktop environment
- [noVNC](https://github.com/novnc/noVNC), DOM key table ported from `core/input/domkeytable.js` (MPL 2.0)
- [QTermWidget](https://github.com/lxqt/qtermwidget), LXC terminal emulator widget (LGPL-2.0+)
- [LibVNCClient](https://github.com/LibVNC/libvncserver), VNC client support (GPL-2.0-or-later)
- [QtKeychain](https://github.com/frankosterfeld/qtkeychain), secure credential storage (BSD-3-Clause)

## License

GPL-3.0 or later. See [LICENSE](License) for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the release history, and the [Releases](https://github.com/realstuffie/ProxMon/releases) page for downloads.
