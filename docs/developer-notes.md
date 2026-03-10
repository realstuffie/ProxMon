# Developer Notes

## QML module packaging (native plugin)

This plasmoid uses a native QML plugin (`.so`) exposed as:

- `org.kde.plasma.proxmox`

Used in `contents/ui/main.qml`:

```qml
import org.kde.plasma.proxmox
```

### Required install layout

To resolve `org.kde.plasma.proxmox`, files must exist under a QML import root matching the URI:

- `org/kde/plasma/proxmox/qmldir`
- `org/kde/plasma/proxmox/libproxmoxclientplugin.so`

For Plasma 6, place custom modules under:

- `contents/qml/org/kde/plasma/proxmox/`

`plasmashell` reliably includes `contents/qml` in import paths.  
`contents/lib` is not a reliable QML import root and can cause:

```text
module "org.kde.plasma.proxmox" is not installed
```

### Packaging verification

After install, verify:

- `~/.local/share/plasma/plasmoids/org.kde.plasma.proxmox/contents/qml/org/kde/plasma/proxmox/qmldir`
- `~/.local/share/plasma/plasmoids/org.kde.plasma.proxmox/contents/qml/org/kde/plasma/proxmox/libproxmoxclientplugin.so`

Restart Plasma:

```bash
kquitapp6 plasmashell && kstart plasmashell
```

### Notes

- `kpackagetool6` can install even if runtime import resolution still fails.
- `qml` CLI import behavior can differ from `plasmashell`.

---

## Local dev environment note (26.04-dev)

`qmllint` on this machine points to a missing Qt5 binary:

```bash
which qmllint
# /usr/bin/qmllint

qmllint --version
# qmllint: could not exec '/usr/lib/qt5/bin/qmllint': No such file or directory
```

So "Failed to import QtQuick" can be tooling/environment noise.

### Current workspace mitigation

In `.vscode/settings.json`:

- `"qml.lint.enabled": false`
- QML import paths remain configured for future use
- Qt6 root import path is included:

```json
"-I", "/usr/lib/x86_64-linux-gnu/qt6/qml"
```

### Re-enable linting later

1. Install Qt6 lint tools (`qt6-declarative-dev-tools` on Debian/Ubuntu)
2. Verify:

```bash
qmllint --version
```

Must succeed and must not reference `/usr/lib/qt5/bin/qmllint`.

1. Re-enable:

```json
"qml.lint.enabled": true
```

### If `QtQuick` still fails after fixing qmllint

1. Build once so generated QML metadata/artifacts exist.
2. If needed, export import paths:

```bash
export QML2_IMPORT_PATH=/usr/lib/x86_64-linux-gnu/qt6/qml
export QML_IMPORT_PATH=/usr/lib/x86_64-linux-gnu/qt6/qml
```

Optional with project paths:

```bash
export QML2_IMPORT_PATH=/usr/lib/x86_64-linux-gnu/qt6/qml:$PWD/contents/qml:$PWD/contents/lib
```

### Quick health check

```bash
which qmllint; qmllint --version 2>&1; ls -d /usr/lib/*/qt6/qml /usr/lib/qt6/qml /usr/share/qt6/qml 2>/dev/null
```

Healthy result:

- `qmllint --version` succeeds
- At least one Qt6 QML path exists (here: `/usr/lib/x86_64-linux-gnu/qt6/qml`)

---

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

---

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

---

## Configuration internals

### Connection tab

- **Host**: Proxmox IP or hostname (e.g. `192.168.1.100`)
- **Port**: API port (default: `8006`)
- **API Token ID**: Format `user@realm!tokenname` (e.g. `root@pam!plasma-monitor`)
- **API Token Secret**: The secret from token creation
- **Update Keyring**: If the secret is changed, click **Update Keyring**. The widget stores it temporarily and migrates it into the system keyring on next load. The widget refreshes shortly after config changes (debounced). If it still doesn't pick up new auth settings, restart Plasma or remove/re-add the widget to force a full reload.
- **Forget**: Clears the secret field. Does **not** delete existing keyring entries.
- **Refresh Interval**: Update frequency in seconds (default: `30`)
- **Ignore SSL**: Enable for self-signed certificates

### Behavior tab

- **Default Sorting**: How to sort VMs/CTs (status, name, or ID)
- **Notifications**: Configure state change alerts

### Notification rate limiting

To reduce notification spam during flapping or frequent refresh/retry cycles:

- Enable/disable in **Behavior tab → Rate Limiting**
- Configure the minimum interval in seconds between duplicates (default: 120s)

### Notification privacy (redaction)

By default, sensitive identity fragments are redacted from notification text (e.g. within task UPIDs):

- **Behavior tab → Privacy → Redact user@realm and token ID in notifications** (default: enabled)
- Replaces patterns like `user@realm!tokenid` with `REDACTED@realm!REDACTED`

---

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

- Verbose logging to journal (`journalctl --user -f`)
- Anonymized data (for screenshots)
- Test notification button

---

## Features — planned / known issues

### Planned

- [ ] Resource usage graphs
- [ ] Storage monitoring
- [ ] Backup status
- [ ] KDE Plasma 5 compatible version

### Known bugs / limitations

- If you configured the widget in older versions, your API token secret may have been stored under a slightly different keyring key (e.g. due to host casing/whitespace). Newer versions auto-migrate legacy keys, but if the widget shows "Missing Token Secret", re-enter the secret in settings and click **Update Keyring**, then wait a moment.
- On Fedora/openSUSE, the completion banner on first install may be hidden above the prompt due to package manager output. The install completes successfully — run `systemctl --user status proxmox-plasmoid-rebuild.path` to confirm, or re-run with `--no-deps` for clean output.
