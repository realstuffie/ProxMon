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

For

`qmllint` on this machine points to a missing Qt5 binary:

```bash
which qmllint
# /usr/bin/qmllint

qmllint --version
# qmllint: could not exec '/usr/lib/qt5/bin/qmllint': No such file or directory
```

So “Failed to import QtQuick” can be tooling/environment noise.

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

3. Re-enable:

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