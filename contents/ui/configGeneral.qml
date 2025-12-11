import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

Item {
    id: root
    width: parent?.width ?? 400
    height: parent?.height ?? 400

    property string title: "Connection"

    property alias cfg_proxmoxHost: hostField.text
    property alias cfg_proxmoxPort: portField.value
    property alias cfg_apiTokenId: tokenIdField.text
    property alias cfg_apiTokenSecret: tokenSecretField.text
    property alias cfg_refreshInterval: refreshField.value
    property alias cfg_ignoreSsl: ignoreSslCheck.checked

    // Required properties for Plasma
    property bool cfg_expanding: false
    property int cfg_length: 0
    property bool cfg_expandingDefault: false
    property int cfg_lengthDefault: 0

    // Sorting properties (shared with configBehavior.qml)
    property string cfg_defaultSorting: "status"
    property string cfg_defaultSortingDefault: "status"

    property string cfg_proxmoxHostDefault: ""
    property int cfg_proxmoxPortDefault: 8006
    property string cfg_apiTokenIdDefault: ""
    property string cfg_apiTokenSecretDefault: ""
    property int cfg_refreshIntervalDefault: 30
    property bool cfg_ignoreSslDefault: true

    Plasma5Support.DataSource {
        id: saveExec
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            if (data["exit code"] === 0) {
                saveStatus.text = "✓ Saved!"
                saveStatus.color = Kirigami.Theme.positiveTextColor
            } else {
                saveStatus.text = "✗ Failed"
                saveStatus.color = Kirigami.Theme.negativeTextColor
            }
            disconnectSource(source)
        }
    }

    Plasma5Support.DataSource {
        id: loadExec
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            if (data["exit code"] === 0 && data["stdout"]) {
                try {
                    var s = JSON.parse(data["stdout"])
                    if (s.host) hostField.text = s.host
                    if (s.port) portField.value = s.port
                    if (s.tokenId) tokenIdField.text = s.tokenId
                    if (s.tokenSecret) tokenSecretField.text = s.tokenSecret
                    if (s.refreshInterval) refreshField.value = s.refreshInterval
                    if (s.ignoreSsl !== undefined) ignoreSslCheck.checked = s.ignoreSsl
                    if (s.enableNotifications !== undefined) enableNotificationsCheck.checked = s.enableNotifications
                    loadStatus.text = "✓ Loaded!"
                    loadStatus.color = Kirigami.Theme.positiveTextColor
                } catch (e) {
                    loadStatus.text = "No defaults saved"
                    loadStatus.color = Kirigami.Theme.neutralTextColor
                }
            }
            disconnectSource(source)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15

        GridLayout {
            columns: 2
            columnSpacing: 15
            rowSpacing: 12
            Layout.fillWidth: true

            QQC2.Label { text: "Host:" }
            QQC2.TextField {
                id: hostField
                Layout.fillWidth: true
                placeholderText: "192.168.1.100"
            }

            QQC2.Label { text: "Port:" }
            QQC2.SpinBox {
                id: portField
                from: 1
                to: 65535
                value: 8006
                editable: true
            }

            QQC2.Label { text: "API Token ID:" }
            QQC2.TextField {
                id: tokenIdField
                Layout.fillWidth: true
                placeholderText: "user@realm!tokenname"
            }

            QQC2.Label { text: "API Token Secret:" }
            QQC2.TextField {
                id: tokenSecretField
                Layout.fillWidth: true
                echoMode: TextInput.Password
            }

            QQC2.Label { text: "Refresh (sec):" }
            QQC2.SpinBox {
                id: refreshField
                from: 5
                to: 3600
                value: 30
                editable: true
            }

            QQC2.Label { text: "Ignore SSL:" }
            QQC2.CheckBox {
                id: ignoreSslCheck
                checked: true
                text: "Skip certificate verification"
            }

        // Notification info
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Kirigami.Icon {
                source: "dialog-information"
                implicitWidth: 16
                implicitHeight: 16
                opacity: 0.7
            }

            QQC2.Label {
                text: "Notifications are sent when VMs, containers, or nodes change state"
                font.pixelSize: 11
                opacity: 0.7
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.3
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            QQC2.Button {
                text: "Save as Default"
                icon.name: "document-save"
                onClicked: {
                    var json = JSON.stringify({
                        host: hostField.text,
                        port: portField.value,
                        tokenId: tokenIdField.text,
                        tokenSecret: tokenSecretField.text,
                        refreshInterval: refreshField.value,
                        ignoreSsl: ignoreSslCheck.checked,
                        enableNotifications: enableNotificationsCheck.checked
                    })
                    saveExec.connectSource("mkdir -p ~/.config/proxmox-plasmoid && echo '" + json + "' > ~/.config/proxmox-plasmoid/settings.json")
                }
            }

            QQC2.Label {
                id: saveStatus
                text: ""
            }

            Item { Layout.fillWidth: true }

            QQC2.Button {
                text: "Load Default"
                icon.name: "document-open"
                onClicked: {
                    loadExec.connectSource("cat ~/.config/proxmox-plasmoid/settings.json 2>/dev/null")
                }
            }

            QQC2.Label {
                id: loadStatus
                text: ""
            }
        }

        QQC2.Label {
            text: "Click 'Save as Default' to remember settings for new widgets"
            font.pixelSize: 11
            opacity: 0.6
        }

        Item { Layout.fillHeight: true }
    }
}
