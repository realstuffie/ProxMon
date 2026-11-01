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

- `kpackagetool6` can report success even if the `.so` is missing, so always verify the file is present.
- The `--install-standalone-qml-module` flag copies the plugin to the user-local Qt6 QML path as a fallback for distros that block loading from the plasmoid package path.

## Install script

### Flags

| Flag | Effect |
| ---------------------------------- | ------- |
| *(none)* | Full install with best-effort dependency detection |
| `--no-deps` | Skip dependency install; build and install only. Use for subsequent installs for clean output. |
| `--no-watcher` | Skip auto-update watcher install. |
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

## Proxmox API privilege separation

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
- **Update Keyring**: The configuration flow passes the entered secret from the KCM to the widget runtime, which writes it to the system keyring after Apply and clears the handoff. The secret passes through QML during configuration; clearing the field or handoff does not guarantee memory erasure. Direct KCM writes via the runtime plugin namespace do **not** work in the KCM load path. See the [credential security model](ARCHITECTURE.md#credential-security-model).
- **Forget**: Clears the secret field. Does **not** delete existing keyring entries.
- **Refresh Interval**: Update frequency in seconds (default: `30`)
- **Ignore SSL**: Bypasses certificate verification and permits server impersonation. Use a trusted CA certificate for self-signed setups instead. HTTPS/WSS encryption remains enabled.

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
- **Power actions**: Icon buttons (Start/Shutdown/Reboot) on each VM/CT; requires `VM.PowerMgmt`
- **Footer**: Quick stats and last update time

### Developer mode

Triple-click the footer to enable:

- Verbose logging to internal memory
- Anonymized data (for screenshots)
- Test notification button

### VNC console: black screen on guest VMs running a full desktop (e.g. Kubuntu)

**Symptom:** The VNC console goes black and appears unresponsive. The screen is also black in Proxmox's own noVNC console, ruling out a bug in this widget's VNC client.

**Cause:** KDE Plasma's Energy Saving feature blanks the display after a period of inactivity. Because the VM has no physical monitor attached, no hardware signal ever wakes it. This affects any full desktop environment running inside a VM that has display power management enabled.

**Fix (on the guest):**

- System Settings → Power Management → Energy Saving → set screen blanking and display power management to **Never**
- This is a per-user KDE setting; apply it for any user account that runs the desktop session

**Screen lock (SDDM) is not affected.** If the KDE screen locker fires, it renders the SDDM lock screen through VNC, which remains visible and interactive. Only Energy Saving (blank/off) causes the unrecoverable black screen.

**Note:** This applies to any VM running a KDE desktop (Kubuntu, KDE Neon, openSUSE KDE, etc.). Other desktop environments have equivalent settings under different names (GNOME: Settings → Power, XFCE: Power Manager).

## Shelved feature ideas

### Favourites / pinned rows

Pin specific VMs or LXCs to the top of their type section (VMs or LXCs) within their node card. Favourites stay scoped per-node to avoid cross-node VMID collisions. In multi-host mode the key would be `sessionKey::nodeName:vmid`, mirroring the existing action/state key pattern. A star toggle on `VmRow`/`LxcRow` (visible on hover, always visible when starred) would persist the favourites set to config. `getVmsForNode` / `getLxcForNode` (and multi-host equivalents) would partition favourites to the top, sort the remainder normally, then concatenate. No conflict with existing `defaultSorting` options since favourites float within the type group, not above it.

### Desktop planar compact indicator (StatusNotifierItem)

When the widget is placed on the desktop (planar formFactor), the full representation is always shown. Ideally, it would also auto-register a compact indicator (icon + status mode text e.g. CPU%) in the bottom panel via the **StatusNotifierItem** D-Bus interface. Requires new C++ code in the plugin to register/deregister the SNI when planar mode is detected, and dynamic icon rendering to include the status text. Shelved due to complexity

### Known bugs / limitations

- **VncWsProxy local port race (known limitation, intentionally not fixed):** `VncWsProxy` binds to `127.0.0.1:0` and emits `ready(port)` before libvncclient calls `connect()`. During that window another local process can grab the slot.

A process that wins this race can disrupt the legitimate console connection.
The bridge sends the PVE authorization header to the remote WebSocket endpoint,
not the loopback peer, and does not echo the ticket to that peer. The RFB
authentication step still requires the ticket. These protocol properties do
not provide isolation from other processes or prevent credential access
through the wallet or process memory. See the [credential security model](ARCHITECTURE.md#credential-security-model).

`SO_PEERCRED` is **not** a viable check here. It's documented for AF_UNIX only, and on AF_INET returns `ENOPROTOOPT` on Linux (0/0/0 on some older kernels).

- If you configured the widget in older versions, your API token secret may have been stored under a slightly different keyring key (e.g. due to host casing/whitespace). Legacy keys are **no longer auto-migrated** (removed in v0.7.3) and can leave the widget showing "Missing Token Secret": remove any ProxMon-related entries in KWallet, re-enter the secret in settings, and click **Update Keyring**. Wait a moment, or restart plasmashell.

### Compact representation click handling

Expansion is driven from two places that complement each other: `activationTogglesExpanded: true` on the `PlasmoidItem` in main.qml lets Plasma toggle the popup on activation, and a `TapHandler` in CompactRepresentation.qml calls `root.expanded = !root.expanded` on direct taps. `root` resolves through the component creation context at tap time.

One known cosmetic quirk: the handler's `enabled: !Plasmoid.editMode` binding cannot resolve `Plasmoid` inside that component and logs one harmless `ReferenceError: Plasmoid is not defined` per plasmashell load. The handler is load-bearing; do not remove it to silence the warning (tap-to-expand stops working; verified at runtime). A `HoverHandler` provides passive hover highlighting. `Kirigami.Icon` absorbs plain `MouseArea` clicks over the icon area (KDE bug 518024), which is why the handler sits at the root item level.

## Code style

`.editorconfig` sets 4 spaces per indent level, with no tabs and no trailing whitespace. YAML uses 2 spaces, because the keys of a list item line up two columns after its dash.

`./check-style.sh` checks these rules and runs in CI. It also requires shell scripts to indent in multiples of 4 and YAML in multiples of 2. C++ and QML are not checked for multiples, because continuation lines line up under the code above them. Heredoc bodies in shell scripts are skipped, since they print as written.

## Settings pages

Plasma injects every setting from `contents/config/main.xml` into every settings page as `cfg_<name>` and `cfg_<name>Default`. A page that doesn't declare one logs "Setting initial properties failed" when the dialog opens. When you add a setting, add its two properties to each of the four pages. `./check-config-pages.sh` lists what is missing and runs in CI.

Settings pages shouldn't depend on the native plugin. The Keyring tab is the exception, because it has to ask the plugin which keyrings exist. It loads that section through a `Loader`, so a plugin that fails to load shows a message on that tab and leaves the others working.

## Sharp icons and pixel alignment

Icons and thin lines go soft unless they sit on whole screen pixels and are shown at a size their art was drawn for. The node card hit every one of these, one after another.

- **Size.** Draw icon art on a grid and show it at that size or an even multiple of it. Use 16, the theme's standard small size, which doubles to 32 and halves to 8. Sizes such as 13 or 14 are scaled by the renderer and come out soft, and so does a theme icon asked for at a size the theme doesn't ship. The node card's own icons are drawn on a 16 x 16 grid in `contents/ui/icons/`. The section headers and the footer use the same icons. The 14 x 14 icons in `contents/icons/` are for the icon theme and the app, not for the panel.
- **Strokes.** In SVG, put 1 px strokes on half-pixel coordinates such as `x="7.5"` and fills on whole ones. In QML, give rectangles and 1 px lines whole-number `x`, `y`, `width` and `height`.
- **Fills.** Never write `fill="rgba(...)"` in an SVG. Qt's SVG renderer reads it as black. Write `fill="#FFFFFF" fill-opacity="0.2"`.
- **Positions.** A layout can leave half a pixel. Centering by `(width - content) / 2` does it on an odd width, and so does any item after a label with a fractional width. Place crisp items by hand with `Math.round`, as the node card does for `nameRow.inset` and `detailRow.x`. `Layout.alignment: Qt.AlignHCenter` does not round.
- **Scale.** Do not put icons inside an item that uses `scale`. The node card's facts line shrinks with `scale`, which is safe only because the panel's minimum width of 380 px keeps it at 1. If you lower that minimum, the icons will blur.

Two layout pitfalls came up in the same work. A binding must not set a property it also reads, which Qt reports as a binding loop, so measure a text width once and multiply, and don't assign the text of a shared `TextMetrics` inside the binding. A layout that switches between one row and two must compare against its parent's width, because its own width is not known on the first pass and Qt aborts with "recursive rearrange".

### Checking it without a desktop

A screenshot at one width proves little, because the fuzz depends on the panel width. Measure instead.

1. Run `/usr/lib/qt6/bin/qmltestrunner`. `/usr/bin/qml` is the Qt 5 chooser and does nothing useful. Use `QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software`, and pass `-maxwarnings 0`, or the runner stops printing once it has seen enough warnings and hides your output.
2. In a `TestCase`, create the component with `Qt.createComponent`, walk its children, and read `item.mapToItem(null, 0, 0)` for each icon, dot and label. Anything with a fraction other than `.00` is soft.
3. Sweep every width from the minimum (380) to the maximum (520). An even width can look fine while an odd one does not.
4. To see the pixels, call `grabToImage` and magnify with `magick in.png -filter point -resize 400% out.png`. Smoothing hides the blur. `QT_SCALE_FACTOR=2` shows the 2x result.

Software rendering has no shaders, so it cannot show effects that need them, such as `Kirigami.Icon` with `isMask: true`. Set the `Kirigami.Theme` colors on a parent item with `inherit: false`, or the card renders in whatever the test machine's theme is.
