# Changelog

## v0.7.3
- fix(main): add action busy guard on status change — clears spinner via checkStateChanges if onActionReply never fires
- fix(config): UI alignment and field sizing across all config tabs for consistent cross-distro rendering
- fix(configGeneral): move SSL toggles into single/multi-host sections; PBS fields hidden when disabled
- fix(configGeneral): add Delete Default button to defaults section
- fix(configBehavior): align labels and dropdowns consistently
- fix(configAppearance): fix label vertical alignment against spinboxes

## v0.7.2
- fix(VmRow/LxcRow): bundle JetBrains Mono for consistent cross-distro font metrics
- fix(VmRow/LxcRow): fix monospace text vertical centering

Tested on Ubuntu 26 (KDE 6.6.4), Fedora 44 (KDE 6.6.5), Manjaro (KDE 6.6.5), openSUSE Tumbleweed (KDE 6.6.5)

## v0.7.1
- fix(VmRow/LxcRow): normalize row spacing, monospace stats labels at 12px, wider containers, vertical centering
- fix(VmRow/LxcRow): add left margin to power buttons; reduce row left margin 8→4px
- fix(VmRow/LxcRow): tighten stats block (90→80px) and mem label (46→34px) to close PBS-to-stats gap
- fix(proxmoxcontroller): extend backup age display to weeks (7d+) and years (52w+)
- fix(install): checksum-based sync; skip kpackagetool re-register if already installed
- fix(configGeneral): remove notification toggle; bind via bool prop
- fix(proxmoxclient): treat task WARNINGS as non-fatal
- chore(main.qml): comment cleanup and dead code removal
- docs(README): tighten security and SSL wording

## v0.7.0
- Feat: power actions toggle — enable/disable start/stop/restart buttons per endpoint
- Fix: collapse backup status row layout when hidden (VmRow, LxcRow)
- Fix: TapHandler hitbox by setting explicit width/height on compact representation root
- LXC terminal: rework data path and add copy/paste support
- UI: SSL warning text now uses bright red; security warnings added to ignore SSL toggles
- UI: rename Console section to Features in behavior settings
- Install: extend auto-rebuild watcher to cover Qt6, libvncclient, qtermwidget6, and additional libraries
- Install: add `--no-watcher` flag to skip auto-rebuild watcher setup
- Build: add mold linker support
- Docs: script cleanup and security section trimmed to keychain and loopback limitation
- Docs: add LXC terminal resize reflow known limitation

## v0.6.1

- Fixed VNC crash and deadlock when closing console mid-connection
- Fixed PBS in-flight request abort on cancelAll()
- Fixed per-endpoint certificate passing to VNC/TTY proxy in multi-host mode
- Gated verbose debug logging behind developer mode

## v0.6.0

- Added VNC console and LXC terminal support
- Added PBS (Proxmox Backup Server) backup status integration
- Added per-endpoint SSL certificate support for multi-host mode
- Added tag and VMID exclusion filters for PBS
- Refactored plasmoid controller logic from QML to C++
- Added GPU-accelerated frame renderer for VNC
- Hardened secret storage and keyring handoff
- Added journalctl-based debug log capture
- Fixed multi-host notification batching

## v0.5.1

- Added PBS backup status integration
- Added tag and VMID exclusion filters for PBS
- Added PBS trusted cert config fields and error surface path
- Fixed PBS startup race condition, double-fetch, and cancelAll bugs
- Fixed PBS config reload and interval default causing breakage

## v0.5.0

- Refactored plasmoid controller logic from QML to C++
- Shifted secret, refresh, and action orchestration into C++ controller
- Hardened secret storage and keyring handoff
- Added basic appearance color controls and config tab icons
- Added per-host enable toggle for multi-host mode
- Fixed multi-host notification batching and compact time display
- Fixed action task follow-through to final success or failure
- Fixed KWallet qdbus fallback to be fully asynchronous
- Fixed keyring write confirmation before marking secrets ready
- Removed legacy plaintext secret migration paths

## v0.4.3

- Fixed multi-host key autodetect stability and label preservation
- Fixed multi-host config refresh and key migration alignment
- Fixed notification and endpoint namespace collisions
- Fixed compact CPU%, wildcard regex, and keyring error path
- Fixed verbose debug logging gated behind developer mode
- Fixed node header text overflow and empty state label centering
- Added transfer timeout for stalled connections

## v0.4.1

- Added two-click action confirmation overlay
- Added identity redaction toggle for notifications
- Added warning hint for host/token refresh issues
- Pinned VM action buttons with tooltips and hover state
- Fixed CPU/RAM label alignment
- Fixed in-flight reply handling

## v0.4.0

- Added multi-host mode with per-host enable toggle (up to 5 hosts)
- Added notification filtering with whitelist/blacklist and wildcard support
- Added KWallet auto-restore on widget re-add
- Added auto-retry with exponential backoff
- Added low latency mode for LAN setups
- Added graceful per-node failure handling
- Added two-click power action confirmation
- Fixed compact representation click area
- Fixed scrollbar gutter overlap with action buttons
- Fixed cfg_* key bindings for config persistence

## v0.3.3

- Added QtKeychain secure credential storage
- Added DBus notifier for state change notifications
- Improved HTTP error reporting
- Fixed KCM/native plugin decoupling
- Dropped plaintext secret storage

## v0.3.2

- Added compact representation with animation
- Added developer mode for verbose logging
- Added logging levels and timestamps
- Improved height calculation and layout
- Fixed icon animations

## v0.3.1
- Added Kirigami migration for Plasma 6.6.2 compatibility
- Fixed PlasmaCore.Units/Theme deprecation warnings

## v0.3.0

- Added AppArmor documentation
- Added cross-distro install script with auto dependency detection
- Added auto-update mechanism with systemd integration
- Added visual tokens and refined theming

## v0.2.0

- Added remote power actions (start, stop, reboot, suspend)
- Added KWallet/QtKeychain secure credential storage
- Added SSL certificate trust support
- Added per-node request failure tolerance

## v0.1.0

- Initial release
- Basic Proxmox VE node, VM, and LXC monitoring
- Single-host connection with API token authentication
