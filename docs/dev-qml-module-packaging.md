# Dev note: QML module packaging (native plugin)
This plasmoid uses a **native QML plugin** (a C++ `.so`) exported as a QML module.

## Module URI
- `org.kde.plasma.proxmox`

`contents/ui/main.qml` contains:
```qml
import org.kde.plasma.proxmox
```

## Packaging rule
For Qt/Plasma to resolve the import above, the module must exist under a QML import root with a directory layout matching the URI:

- `org/kde/plasma/proxmox/qmldir`
- `org/kde/plasma/proxmox/libproxmoxclientplugin.so`

### Plasma 6 rule of thumb
Ship custom QML modules under:
- `contents/qml/org/kde/plasma/proxmox/`

Plasma reliably adds `contents/qml` to the QML import path.

Staging the module under `contents/lib` is **not reliably** picked up by `plasmashell` as a QML import root and can produce:
```
module "org.kde.plasma.proxmox" is not installed
```

## Verification checklist
After installing the plasmoid, verify:
- `~/.local/share/plasma/plasmoids/org.kde.plasma.proxmox/contents/qml/org/kde/plasma/proxmox/qmldir`
- `~/.local/share/plasma/plasmoids/org.kde.plasma.proxmox/contents/qml/org/kde/plasma/proxmox/libproxmoxclientplugin.so`

Then restart Plasma:
```bash
kquitapp6 plasmashell && kstart plasmashell
```

## Notes
- `kpackagetool6` can install a plasmoid even if the QML module cannot be resolved at runtime.
- `qml` CLI can be made to work with manual `-I` import paths; `plasmashell` has different import-path behavior.
