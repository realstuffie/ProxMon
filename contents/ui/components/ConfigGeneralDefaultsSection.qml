import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property var saveExec: null
    property var loadExec: null
    property var escapeForShell: null
    property var singleHostSection: null
    property var refreshField: null
    property var ignoreSslCheck: null
    property var enableNotificationsCheck: null
    property string cfg_apiTokenSecret: ""
    property string saveStatusText: ""
    property color saveStatusColor: Kirigami.Theme.textColor
    property string loadStatusText: ""
    property color loadStatusColor: Kirigami.Theme.textColor
    signal stashSecret(string secret)

    Layout.fillWidth: true
    spacing: 10

    Kirigami.Heading {
        text: "Default Settings"
        level: 2
    }

    QQC2.Label {
        text: "Save current settings as defaults for new widget instances"
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
                var settings = {
                    host: root.singleHostSection.hostText,
                    port: root.singleHostSection.portValue,
                    tokenId: root.singleHostSection.tokenIdText,
                    tokenSecret: "",
                    refreshInterval: root.refreshField.value,
                    ignoreSsl: root.ignoreSslCheck.checked,
                    enableNotifications: root.enableNotificationsCheck.checked
                }
                var json = JSON.stringify(settings)
                var safeJson = root.escapeForShell(json)
                safeJson = safeJson.replace(/[\r\n]+/g, " ")

                root.saveExec.connectSource("mkdir -p ~/.config/proxmox-plasmoid && printf '%s' '" + safeJson + "' > ~/.config/proxmox-plasmoid/settings.json")

                if (root.singleHostSection.tokenSecretText && root.singleHostSection.tokenSecretText.trim() !== "") {
                    root.stashSecret(root.singleHostSection.tokenSecretText)
                }
            }
        }

        QQC2.Label {
            text: root.saveStatusText
            color: root.saveStatusColor
        }

        Item { Layout.fillWidth: true }

        QQC2.Button {
            text: "Load Default"
            icon.name: "document-open"
            onClicked: {
                root.loadExec.connectSource("cat ~/.config/proxmox-plasmoid/settings.json 2>/dev/null")
            }
        }

        QQC2.Label {
            text: root.loadStatusText
            color: root.loadStatusColor
        }
    }
}
