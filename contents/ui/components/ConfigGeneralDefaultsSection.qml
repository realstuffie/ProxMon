import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtCore
import org.kde.kirigami as Kirigami
import "configportability.mjs" as CP

// "Default Settings" — saves a startup-defaults seed to a fixed file that
// main.qml reads to pre-fill a fresh widget instance. This is a DIFFERENT
// feature from Backup/Restore (which writes to a user-chosen path), but both
// share ONE file format: the versioned export envelope from
// configportability.mjs (full 46-key config, no secrets). The file is written
// via a base64 payload into mktemp(0600) + atomic mv. Legacy flat-format
// files are still understood on read (see CP.parseLegacyDefaults) and are
// rewritten in the envelope format the next time Save is pressed.
ColumnLayout {
    id: root

    property var saveExec: null
    property var loadExec: null
    // Supplied by configGeneral.qml:
    //   collectValues()           -> map of whitelisted cfg_* values
    //   reportStatus(text, isErr) -> surfaces a transient status next to the buttons
    property var collectValues: null
    property var reportStatus: null
    property string saveStatusText: ""
    property color saveStatusColor: Kirigami.Theme.textColor
    property string loadStatusText: ""
    property color loadStatusColor: Kirigami.Theme.textColor

    // Absolute path to the seed file (~/.config/proxmox-plasmoid/settings.json),
    // resolved from StandardPaths so it never relies on shell tilde expansion.
    readonly property string configDir:
        CP.urlToLocalPath(StandardPaths.writableLocation(StandardPaths.GenericConfigLocation)) + "/proxmox-plasmoid"
    readonly property string defaultsPath: configDir + "/settings.json"

    Layout.fillWidth: true
    spacing: 10

    Kirigami.Heading {
        text: "Default Settings"
        level: 2
    }

    QQC2.Label {
        text: "Save all current settings as the defaults applied to new widget instances (same format as Backup/Restore; secrets stay in the keychain)"
        font.pixelSize: 11
        opacity: 0.7
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        QQC2.Button {
            text: "Save as Default"
            icon.name: "document-save"
            onClicked: {
                var res = CP.buildExportEnvelope(
                    (typeof root.collectValues === "function") ? root.collectValues() : {})
                if (!res.ok) {
                    if (typeof root.reportStatus === "function") root.reportStatus(res.error, true)
                    return
                }
                // Ensure the directory exists, then hand off to the module's
                // secure atomic writer (base64 payload, mktemp 0600, atomic mv).
                var cmd = "mkdir -p " + CP.shq(root.configDir) + "; "
                        + CP.buildAtomicWriteCommand(root.defaultsPath, res.jsonText)
                root.saveExec.connectSource(cmd)
            }
        }

        QQC2.Button {
            text: "Load Default"
            icon.name: "document-open"
            onClicked: {
                root.loadExec.connectSource(CP.buildReadCommand(root.defaultsPath))
            }
        }

        QQC2.Button {
            text: "Delete Default"
            icon.name: "edit-delete"
            onClicked: {
                root.saveExec.connectSource("rm -f " + CP.shq(root.defaultsPath))
            }
        }

        QQC2.Label {
            text: root.saveStatusText || root.loadStatusText
            color: root.saveStatusText ? root.saveStatusColor : root.loadStatusColor
        }

        Item { Layout.fillWidth: true }
    }
}
