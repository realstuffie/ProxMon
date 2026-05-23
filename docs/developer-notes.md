# Developer Notes

## QML module packaging (native plugin)

`main.qml` uses a **relative** import rather than a URI-based one:

```qml
import "../lib/proxmox" as ProxMon
```

This resolves from `contents/ui/` to `contents/lib/proxmox/`, which must contain:

- `qmldir`
- `libproxmoxclientplugin.so`

`kpackagetool6` installs all files under `contents/` verbatim, so at runtime the plugin lives at:

```text
~/.local/share/plasma/plasmoids/org.kde.plasma.proxmox/contents/lib/proxmox/libproxmoxclientplugin.so
```

### Packaging verification

After install, verify:

```bash
ls ~/.local/share/plasma/plasmoids/org.kde.plasma.proxmox/contents/lib/proxmox/
# should show: libproxmoxclientplugin.so  qmldir
```

### Notes

- `kpackagetool6` can report success even if the `.so` is missing — always verify the file is present.
- The `--install-standalone-qml-module` flag copies the plugin to the user-local Qt6 QML path as a fallback for distros that block loading from the plasmoid package path.

## Install script

### Flags

| Flag | Effect |
| ------ | -------- |
| *(none)* | Full install with best-effort dependency detection |
| `--no-deps` | Skip dependency install; build and install only. Use for subsequent installs for clean output. |
| `--install-standalone-qml-module` | Also copy the QML module to the user-local Qt6 QML path as a compatibility fallback for distros that block loading the packaged plugin path. |

### Build output and install policy

Build output is not committed to the repository. `install.sh` builds the native plugin in a temporary directory and stages the resulting `.so` into the plasmoid package at:

```text
contents/lib/proxmox/libproxmoxclientplugin.so
```

The script detects the user-local Qt6 QML path for diagnostics, but final runtime deployment is single-location via the plasmoid package in:

```text
~/.local/share/plasma/plasmoids/org.kde.plasma.proxmox/contents/lib/proxmox/
```

No secondary standalone QML module install is performed unless `--install-standalone-qml-module` is passed.

### Manual installation (without install.sh)

```bash
git clone https://github.com/realstuffie/ProxMon.git
cd ProxMon

# Install the plasmoid
kpackagetool6 -t Plasma/Applet -i .

# Install icons
mkdir -p ~/.local/share/icons/hicolor/scalable/apps/
cp contents/icons/*.svg ~/.local/share/icons/hicolor/scalable/apps/

# Update icon cache
gtk-update-icon-cache ~/.local/share/icons/hicolor/ 2>/dev/null || true
```

### Manual uninstall

```bash
kpackagetool6 -t Plasma/Applet -r org.kde.plasma.proxmox
rm -f ~/.local/share/icons/hicolor/scalable/apps/proxmox-monitor.svg
rm -f ~/.local/share/icons/hicolor/scalable/apps/lxc.svg
rm -rf ~/.config/proxmox-plasmoid/
```

## Proxmox API — privilege separation

If an API token is created with **Privilege Separation** enabled (`-privsep 1`), the token does **not** automatically inherit the user's ACLs. Per Proxmox docs, effective permissions are the **intersection** of user permissions and token permissions. You must grant roles to both the user and the token, or disable privilege separation.

Example:

```bash
# Create token with separated privileges
pveum user token add joe@pve monitoring -privsep 1

# Grant read-only role to the token (ensure the user also has it)
pveum acl modify /vms -token 'joe@pve!monitoring' -role PVEAuditor
```

Proxmox ships built-in roles: `PVEAuditor` (read-only) and `PVEVMUser` (includes `VM.PowerMgmt`). Minimal custom roles can also be created.

Recommended pattern:

- Keep a read-only monitoring token with `Sys.Audit` + `VM.Audit`
- Create a separate token/user for power actions with `VM.PowerMgmt` (+ `Sys.PowerMgmt` only if required by your ACL/role setup) at the minimum scope needed

## Configuration internals

### Connection tab

- **Host**: Proxmox IP or hostname (e.g. `192.168.1.100`)
- **Port**: API port (default: `8006`)
- **API Token ID**: Format `user@realm!tokenname` (e.g. `root@pam!plasma-monitor`)
- **API Token Secret**: The secret from token creation
- **Update Keyring**: Current known-viable approach is a transient KCM-to-runtime handoff. The secret is held briefly in memory, the widget runtime writes it to the system keyring after Apply, and the temporary handoff is then cleared. Direct KCM writes via the runtime plugin namespace does **not** work in the KCM load path.
- **Forget**: Clears the secret field. Does **not** delete existing keyring entries.
- **Refresh Interval**: Update frequency in seconds (default: `30`)
- **Ignore SSL**: Enable for self-signed certificates

### Behavior tab

- **Default Sorting**: How to sort VMs/CTs (status, name, or ID)
- **Notifications**: Configure state change alerts

### Notification privacy (redaction)

By default, sensitive identity fragments are redacted from notification text (e.g. within task UPIDs):

- **Behavior tab → Privacy → Redact user@realm and token ID in notifications** (default: enabled)
- Replaces patterns like `user@realm!tokenid` with `REDACTED@realm!REDACTED`

## UI internals

### Panel view (compact)

- Shows average CPU usage across all nodes
- Animated icon during refresh
- Click to expand

### Expanded view

- **Node cards**: CPU, memory, uptime per node
- **Click node**: Expand/collapse VM and container lists
- **Status indicators**: Green = running, gray = stopped
- **Power actions**: Icon buttons (Start/Shutdown/Reboot) on each VM/CT — requires `VM.PowerMgmt`
- **Footer**: Quick stats and last update time

### Developer mode

Triple-click the footer to enable:

- Verbose logging to internal memory
- Anonymized data (for screenshots)
- Test notification button

### VNC console — black screen on guest VMs running a full desktop (e.g. Kubuntu)

**Symptom:** The VNC console goes black and appears unresponsive. The screen is also black in Proxmox's own noVNC console, ruling out a bug in this widget's VNC client.

**Cause:** KDE Plasma's Energy Saving feature blanks the display after a period of inactivity. Because the VM has no physical monitor attached, no hardware signal ever wakes it. This affects any full desktop environment running inside a VM that has display power management enabled.

**Fix (on the guest):**

- System Settings → Power Management → Energy Saving → set screen blanking and display power management to **Never**
- This is a per-user KDE setting; apply it for any user account that runs the desktop session

**Screen lock (SDDM) is not affected** — if the KDE screen locker fires, it renders the SDDM lock screen through VNC, which remains visible and interactive. Only Energy Saving (blank/off) causes the unrecoverable black screen.

**Note:** This applies to any VM running a KDE desktop (Kubuntu, KDE Neon, openSUSE KDE, etc.). Other desktop environments have equivalent settings under different names (GNOME: Settings → Power, XFCE: Power Manager).

## Shelved feature ideas

### Favourites / pinned rows

Pin specific VMs or LXCs to the top of their type section (VMs or LXCs) within their node card. Favourites stay scoped per-node to avoid cross-node VMID collisions. In multi-host mode the key would be `sessionKey::nodeName:vmid`, mirroring the existing action/state key pattern. A star toggle on `VmRow`/`LxcRow` (visible on hover, always visible when starred) would persist the favourites set to config. `getVmsForNode` / `getLxcForNode` (and multi-host equivalents) would partition favourites to the top, sort the remainder normally, then concatenate. No conflict with existing `defaultSorting` options since favourites float within — not above — the type group.

### Desktop planar compact indicator (StatusNotifierItem)

When the widget is placed on the desktop (planar formFactor), the full representation is always shown. Ideally, it would also auto-register a compact indicator (icon + status mode text e.g. CPU%) in the bottom panel via the **StatusNotifierItem** D-Bus interface. Requires new C++ code in the plugin to register/deregister the SNI when planar mode is detected, and dynamic icon rendering to include the status text. Shelved due to complexity

### Known bugs / limitations

- **VncWsProxy local port race (known limitation, intentionally not fixed):** `VncWsProxy` binds to `127.0.0.1:0` and emits `ready(port)` before libvncclient calls `connect()`. During that window another local process can grab the slot.

Residual threat is DoS only. The Proxmox VNC ticket lives in this process and is never echoed to the loopback client, so an attacker grabbing the slot cannot read it. The PVE auth header is sent outbound on the WebSocket and is never echoed either. Without the ticket the attacker fails the RFB auth handshake, the WS server tears down, and the user gets an error and retries. No data or credentials leak.

`SO_PEERCRED` is **not** a viable check here — it is documented for AF_UNIX only, and on AF_INET returns `ENOPROTOOPT` on Linux (0/0/0 on some older kernels).

- If you configured the widget in older versions, your API token secret may have been stored under a slightly different keyring key (e.g. due to host casing/whitespace). Newer versions auto-migrate legacy keys, but if the widget shows "Missing Token Secret", re-enter the secret in settings and click **Update Keyring**, then wait a moment.

### Compact representation click handling

`Kirigami.Icon` silently absorbs mouse events in custom `compactRepresentation` items,
preventing a parent `MouseArea` from receiving clicks over the icon area (KDE bug 518024,
unresolved as of Plasma 6.6.3). Workaround: add a second `MouseArea` directly inside the
`Kirigami.Icon` in addition to the root item's `MouseArea`.

`activationTogglesExpanded` is not used — both `MouseArea` handlers call
`root.expanded = !root.expanded` directly to avoid double-toggle.

A `HoverHandler` nested inside the root `MouseArea` provides hover highlighting passively
without consuming click events. The root `MouseArea` is bounded to `compactLayout` rather
than `parent` to avoid overlapping adjacent applet click areas. A `TextMetrics` item
measuring `"99%"` provides a stable minimum label width to prevent layout shifting as CPU
values change between one and two digits.
