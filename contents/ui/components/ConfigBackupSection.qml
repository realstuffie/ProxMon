pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "configportability.mjs" as CP

// "Backup / Restore" section for the General config page.
//
// Security notes:
//  - The export file NEVER contains token secrets. The whitelist and the
//    secret-exclusion guard live in configportability.mjs; the keyring is
//    neither read on export nor written on import.
//  - File contents never touch the shell unencoded: writes go through a
//    base64 payload into mktemp(0600) + atomic mv.
ColumnLayout {
    id: root

    // Supplied by configGeneral.qml:
    //   collectValues()        -> map of whitelisted cfg_* values for export
    //   applyImportedConfig(m) -> assigns validated keys to the page's cfg_*
    property var collectValues: null
    property var applyImportedConfig: null

    // Validation result held between file pick and the confirm dialog.
    property var pendingImport: null
    property string lastExportPath: ""

    Layout.fillWidth: true
    spacing: 10

    function showStatus(type, text, autoHide) {
        statusMessage.type = type
        statusMessage.text = text
        statusMessage.visible = true
        if (autoHide) statusTimer.restart()
        else statusTimer.stop()
    }

    function openExportDialog() {
        if (typeof root.collectValues !== "function") {
            showStatus(Kirigami.MessageType.Error, "Export is not available on this page.", false)
            return
        }
        exportDialog.currentFolder = StandardPaths.writableLocation(StandardPaths.HomeLocation)
        exportDialog.currentFile = exportDialog.currentFolder + "/proxmon-config.json"
        exportDialog.open()
    }

    function finishExport(fileUrl) {
        var path = CP.urlToLocalPath(fileUrl)
        if (path === "") return
        if (!/\.json$/i.test(path)) path += ".json"
        var res = CP.buildExportEnvelope(root.collectValues())
        if (!res.ok) {
            showStatus(Kirigami.MessageType.Error, res.error, false)
            return
        }
        root.lastExportPath = path
        writeExec.connectSource(CP.buildAtomicWriteCommand(path, res.jsonText))
    }

    function finishImport(fileUrl) {
        var path = CP.urlToLocalPath(fileUrl)
        if (path === "") return
        readExec.connectSource(CP.buildReadCommand(path))
    }

    function handleImportText(text) {
        var res = CP.validateImportFile(text)
        if (!res.ok) {
            showStatus(Kirigami.MessageType.Error, "Import failed: " + res.error, false)
            return
        }
        root.pendingImport = res
        confirmDialog.open()
    }

    function applyPendingImport() {
        var res = root.pendingImport
        root.pendingImport = null
        if (!res || typeof root.applyImportedConfig !== "function") return
        root.applyImportedConfig(res.config)
        var msg = "Settings imported. Review the tabs, then press Apply to save them."
        if (res.needsSecrets)
            msg += " Token secrets are never part of an export — matching entries already in your keychain are picked up automatically."
        showStatus(Kirigami.MessageType.Information, msg, false)
    }

    Kirigami.Heading {
        text: "Backup / Restore"
        level: 2
    }

    QQC2.Label {
        text: "Export all settings to a JSON file, or restore them from a previous export. Token secrets are never included, they stay in the system keychain."
        font.pixelSize: 11
        opacity: 0.7
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        QQC2.Button {
            text: "Export configuration…"
            icon.name: "document-export"
            onClicked: root.openExportDialog()
        }

        QQC2.Button {
            text: "Import configuration…"
            icon.name: "document-import"
            onClicked: {
                importDialog.currentFolder = StandardPaths.writableLocation(StandardPaths.HomeLocation)
                importDialog.open()
            }
        }

        Item { Layout.fillWidth: true }
    }

    Kirigami.InlineMessage {
        id: statusMessage
        Layout.fillWidth: true
        visible: false
    }

    Timer {
        id: statusTimer
        interval: 8000
        onTriggered: statusMessage.visible = false
    }

    // Writes the export file (base64 payload -> mktemp 0600 -> atomic mv).
    Plasma5Support.DataSource {
        id: writeExec
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
            if (data["exit code"] === 0) {
                root.showStatus(Kirigami.MessageType.Positive,
                                "Configuration exported to " + root.lastExportPath, true)
            } else {
                root.showStatus(Kirigami.MessageType.Error,
                                "Export failed — check that the destination folder is writable.", false)
            }
        }
    }

    // Reads the picked import file.
    Plasma5Support.DataSource {
        id: readExec
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
            if (data["exit code"] !== 0) {
                root.showStatus(Kirigami.MessageType.Error, "Could not read the selected file.", false)
                return
            }
            root.handleImportText(data["stdout"] || "")
        }
    }

    FileDialog {
        id: exportDialog
        fileMode: FileDialog.SaveFile
        nameFilters: ["JSON (*.json)", "All files (*)"]
        onAccepted: root.finishExport(selectedFile)
    }

    FileDialog {
        id: importDialog
        fileMode: FileDialog.OpenFile
        nameFilters: ["JSON (*.json)", "All files (*)"]
        onAccepted: root.finishImport(selectedFile)
    }

    Kirigami.PromptDialog {
        id: confirmDialog
        title: "Import Configuration"
        subtitle: "This replaces the current settings on all tabs (nothing is saved until you press Apply). Token secrets are not part of the file; keychain entries keep working automatically."
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: root.applyPendingImport()
    }
}
