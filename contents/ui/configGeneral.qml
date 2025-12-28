import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kcmutils as KCM
/*
  NOTE:
  Config QML (KCM) runs in a separate context than the plasmoid itself and
  should not depend on the native plugin being loadable. Otherwise the entire
  Connection tab may fail to load if the plugin can't be resolved.
*/

KCM.SimpleKCM {
    id: root

    // Connection properties (aliased to UI controls)
    property alias cfg_proxmoxHost: hostField.text
    property alias cfg_proxmoxPort: portField.value
    property alias cfg_apiTokenId: tokenIdField.text
    property alias cfg_apiTokenSecret: tokenSecretField.text
    property alias cfg_refreshInterval: refreshField.value
    property alias cfg_ignoreSsl: ignoreSslCheck.checked
    property alias cfg_enableNotifications: enableNotificationsCheck.checked

    // Default values for Plasma
    property string cfg_proxmoxHostDefault: ""
    property int cfg_proxmoxPortDefault: 8006
    property string cfg_apiTokenIdDefault: ""
    property string cfg_apiTokenSecretDefault: ""
    property int cfg_refreshIntervalDefault: 30
    property bool cfg_ignoreSslDefault: true
    property bool cfg_enableNotificationsDefault: true

    // DataSource for saving settings to file
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
            saveStatusTimer.restart()
            disconnectSource(source)
        }
    }

    // DataSource for loading settings from file
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
            } else {
                loadStatus.text = "No defaults saved"
                loadStatus.color = Kirigami.Theme.neutralTextColor
            }
            loadStatusTimer.restart()
            disconnectSource(source)
        }
    }

    // Timers to clear status messages
    Timer {
        id: saveStatusTimer
        interval: 3000
        onTriggered: saveStatus.text = ""
    }

    Timer {
        id: loadStatusTimer
        interval: 3000
        onTriggered: loadStatus.text = ""
    }

    // Helper function to escape JSON for shell
    function escapeForShell(str) {
        return str.replace(/\\/g, "\\\\").replace(/'/g, "'\\''")
    }

    /*
      Keyring handling is done by the plasmoid runtime (main.qml), which can load the
      native plugin. Keep the KCM simple and always loadable.
      The secret field here is treated as an input that will be migrated into keyring
      when the widget runs.
    */

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 15

        // Connection Settings Section
        Kirigami.Heading {
            text: "Connection Settings"
            level: 2
        }

        GridLayout {
            columns: 2
            columnSpacing: 15
            rowSpacing: 12
            Layout.fillWidth: true

            QQC2.Label {
                text: "Host:"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            QQC2.TextField {
                id: hostField
                Layout.fillWidth: true
                placeholderText: "192.168.1.100 or proxmox.local"
            }

            QQC2.Label {
                text: "Port:"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            QQC2.SpinBox {
                id: portField
                from: 1
                to: 65535
                value: 8006
                editable: true
            }

            QQC2.Label {
                text: "API Token ID:"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            QQC2.TextField {
                id: tokenIdField
                Layout.fillWidth: true
                placeholderText: "user@realm!tokenname"
            }

            QQC2.Label {
                text: "API Token Secret:"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            QQC2.TextField {
                id: tokenSecretField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: "Stored in keyring after Apply"
            }

            QQC2.Label {
                text: "Refresh Interval:"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            RowLayout {
                spacing: 8
                QQC2.SpinBox {
                    id: refreshField
                    from: 5
                    to: 3600
                    value: 30
                    editable: true
                }
                QQC2.Label {
                    text: "seconds"
                    opacity: 0.7
                }
            }

            QQC2.Label {
                text: "SSL Verification:"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            QQC2.CheckBox {
                id: ignoreSslCheck
                checked: true
                text: "Ignore SSL certificate errors"
            }

            QQC2.Label {
                text: "Notifications:"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            QQC2.CheckBox {
                id: enableNotificationsCheck
                checked: true
                text: "Enable desktop notifications"
            }
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
                text: "Notifications are sent when VMs, containers, or nodes change state. Configure filters in the Behavior tab."
                font.pixelSize: 11
                opacity: 0.7
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.3
        }

        // Default Settings Section
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
                        host: hostField.text,
                        port: portField.value,
                        tokenId: tokenIdField.text,
                        // Intentionally do not store secrets in plaintext defaults
                        tokenSecret: "",
                        refreshInterval: refreshField.value,
                        ignoreSsl: ignoreSslCheck.checked,
                        enableNotifications: enableNotificationsCheck.checked
                    }
                    var json = JSON.stringify(settings)
                    var safeJson = escapeForShell(json)

                    // Use printf (more predictable than echo) and avoid newlines
                    safeJson = safeJson.replace(/[\r\n]+/g, " ")

                    // Persist non-secret defaults to file
                    saveExec.connectSource("mkdir -p ~/.config/proxmox-plasmoid && printf '%s' '" + safeJson + "' > ~/.config/proxmox-plasmoid/settings.json")

                    // Store secret in config temporarily; plasmoid runtime will migrate to keyring and clear it.
                    // This keeps the KCM dependency-free while still letting users enter/update the secret.
                    if (tokenSecretField.text && tokenSecretField.text.trim() !== "") {
                        Plasmoid.configuration.apiTokenSecret = tokenSecretField.text
                    }
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
                    // Secret is not loaded via the KCM anymore.
                }
            }

            QQC2.Label {
                id: loadStatus
                text: ""
            }
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.3
            Layout.topMargin: 10
        }

        // API Token Help
        Kirigami.Heading {
            text: "How to Create an API Token"
            level: 3
        }

        QQC2.Label {
            text: "1. Log into Proxmox web interface\n" +
                  "2. Go to Datacenter → Permissions → API Tokens\n" +
                  "3. Click 'Add' and create a token\n" +
                  "4. Uncheck 'Privilege Separation' for full access\n" +
                  "5. Copy the Token ID and Secret"
            font.pixelSize: 11
            opacity: 0.7
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
