# Local qmllint notes (machine-specific)

## Why VS Code shows many lint errors

`qmllint` on this machine is broken and points to a missing Qt5 binary.

```bash
which qmllint
# /usr/bin/qmllint

qmllint --version
# qmllint: could not exec '/usr/lib/qt5/bin/qmllint': No such file or directory
```

Errors like “Failed to import QtQuick” are environment/tooling issues, not code issues.

---

## Current workspace mitigation

File: `.vscode/settings.json`

- `"qml.lint.enabled": false` (prevents noisy false diagnostics)
- QML import paths are still configured for later
- Qt6 import root is included:

```json
"-I", "/usr/lib/x86_64-linux-gnu/qt6/qml"
```

---

## Re-enable linting later

1. Install working Qt6 lint tools (Debian/Ubuntu: `qt6-declarative-dev-tools`)
2. Verify:

```bash
qmllint --version
```

Must succeed and must not reference `/usr/lib/qt5/bin/qmllint`.

1. Re-enable linting:

```json
"qml.lint.enabled": true
```

---

## If `QtQuick` still fails after fixing qmllint

Linting can still fail outside a built Qt environment.

1. Build once so generated QML metadata/artifacts exist.
2. If needed, set import paths manually:

```bash
export QML2_IMPORT_PATH=/usr/lib/x86_64-linux-gnu/qt6/qml
export QML_IMPORT_PATH=/usr/lib/x86_64-linux-gnu/qt6/qml
```

Optional with project paths:

```bash
export QML2_IMPORT_PATH=/usr/lib/x86_64-linux-gnu/qt6/qml:$PWD/contents/qml:$PWD/contents/lib
```

---

## Quick health check

```bash
which qmllint; qmllint --version 2>&1; ls -d /usr/lib/*/qt6/qml /usr/lib/qt6/qml /usr/share/qt6/qml 2>/dev/null
```

Healthy setup:

- `qmllint --version` succeeds
- At least one Qt6 QML path exists (here: `/usr/lib/x86_64-linux-gnu/qt6/qml`)
