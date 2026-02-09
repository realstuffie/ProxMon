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

  ALSO:
  Do not access `Plasmoid` from a KCM page. The config dialog injects cfg_*
  properties; use those as the single source of truth. Accessing Plasmoid here
  causes "Plasmoid is not defined" and can prevent config pages from loading.
*/

KCM.SimpleKCM {
    id: root

    // Connection properties (aliased to UI controls)
    property alias cfg_proxmoxHost: hostField.text
    property alias cfg_proxmoxPort: portField.value
    property alias cfg_apiTokenId: tokenIdField.text
    // SECURITY: do not bind cfg_* to secrets (cfg_* are persisted by KCM on Apply).
    property string pendingApiTokenSecret: ""
    property alias cfg_refreshInterval: refreshField.value
    property alias cfg_ignoreSsl: ignoreSslCheck.checked
    property alias cfg_enableNotifications: enableNotificationsCheck.checked

    // Multi-host mode (cfg_* values are provided by the KCM engine)
    property string cfg_connectionMode: "single"
    property string cfg_multiHostsJson: "[]"
    // SECURITY: do not persist secrets in config
    property string pendingMultiHostSecretsJson: "{}"

    // Auto-retry (handled in main.qml)
    property alias cfg_autoRetry: autoRetryCheck.checked
    property alias cfg_retryStartSeconds: retryStartSpin.value
    property alias cfg_retryMaxSeconds: retryMaxSpin.value

    // Default values for Plasma
    property string cfg_proxmoxHostDefault: ""
    property int cfg_proxmoxPortDefault: 8006
    property string cfg_apiTokenIdDefault: ""
    property string cfg_apiTokenSecretDefault: ""

    property string cfg_connectionModeDefault: "single"
    property string cfg_multiHostsJsonDefault: "[]"
    property string cfg_multiHostSecretsJsonDefault: "{}"
    property int cfg_refreshIntervalDefault: 30
    property bool cfg_ignoreSslDefault: true
    property bool cfg_enableNotificationsDefault: true

    // Auto-retry defaults
    property bool cfg_autoRetryDefault: true
    property int cfg_retryStartSecondsDefault: 5
    property int cfg_retryMaxSecondsDefault: 300


    function parseMultiHosts() {
        try {
            var arr = JSON.parse(cfg_multiHostsJson || "[]")
            if (!Array.isArray(arr)) return []
            return arr.slice(0, 5)
        } catch (e) {
            return []
        }
    }

    function saveMultiHosts(arr) {
        cfg_multiHostsJson = JSON.stringify((arr || []).slice(0, 5))
    }

    function ensureMultiHostsLen(n) {
        var arr = parseMultiHosts()
        while (arr.length < n) {
            arr.push({ name: "", host: "", port: 8006, tokenId: "" })
        }
        return arr.slice(0, n)
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

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            QQC2.Label {
                text: "Mode:"
                Layout.alignment: Qt.AlignVCenter
            }

            QQC2.ComboBox {
                id: connectionModeCombo
                model: [
                    { text: "Single host", value: "single" },
                    { text: "Multi-host (up to 5)", value: "multiHost" }
                ]
                textRole: "text"
                valueRole: "value"
                Layout.fillWidth: true

                Component.onCompleted: {
                    var v = root.cfg_connectionMode || "single"
                    currentIndex = (v === "multiHost") ? 1 : 0
                }

                onActivated: {
                    cfg_connectionMode = model[currentIndex].value
                }
            }
        }

        GridLayout {
            id: singleHostGrid
            columns: 2
            columnSpacing: 15
            rowSpacing: 12
            Layout.fillWidth: true
            visible: (root.cfg_connectionMode || "single") === "single"

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
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                QQC2.TextField {
                    id: tokenSecretField
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    placeholderText: "Stored in keyring (not saved to config)"
                    onTextChanged: pendingApiTokenSecret = text
                }

                QQC2.Button {
                    text: "Update Keyring"
                    icon.name: "dialog-password"
                    enabled: tokenSecretField.text && tokenSecretField.text.trim() !== ""
                    onClicked: {
                        // SECURITY: keep secret in-memory only (this config UI must not persist secrets).
                        pendingApiTokenSecret = tokenSecretField.text
                        tokenSecretField.text = ""
                    }

                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: "Keeps the secret in-memory for this dialog session only. It is not stored in the config file."
                }

                QQC2.Button {
                    text: "Forget"
                    icon.name: "edit-clear"
                    onClicked: {
                        tokenSecretField.text = ""
                        pendingApiTokenSecret = ""
                    }

                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: "Clears the locally entered secret (in-memory only). This does not delete existing keyring entries."
                }
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

        // Multi-host configuration
        ColumnLayout {
            Layout.fillWidth: true
            visible: (root.cfg_connectionMode || "single") === "multiHost"
            spacing: 10

            QQC2.Label {
                text: "Configure up to 5 Proxmox endpoints. Secrets are stored in the system keyring after Apply."
                font.pixelSize: 11
                opacity: 0.7
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Repeater {
                model: 5

                delegate: Kirigami.Card {
                    Layout.fillWidth: true

                    property int idx: index
                    property var entry: (ensureMultiHostsLen(5)[idx])

                    contentItem: ColumnLayout {
                        spacing: 8

                        RowLayout {
                            spacing: 8
                            QQC2.Label { text: "Label:"; Layout.preferredWidth: 60 }
                            QQC2.TextField {
                                Layout.fillWidth: true
                                text: entry.name || ""
                                placeholderText: "e.g. Home / Work"
                                onTextChanged: {
                                    var arr = ensureMultiHostsLen(5)
                                    arr[idx].name = text
                                    saveMultiHosts(arr)
                                }
                            }
                        }

                        RowLayout {
                            spacing: 8
                            QQC2.Label { text: "Host:"; Layout.preferredWidth: 60 }
                            QQC2.TextField {
                                Layout.fillWidth: true
                                text: entry.host || ""
                                placeholderText: "192.168.1.100 or proxmox.local"
                                onTextChanged: {
                                    var arr = ensureMultiHostsLen(5)
                                    arr[idx].host = text
                                    saveMultiHosts(arr)
                                }
                            }
                        }

                        RowLayout {
                            spacing: 8
                            QQC2.Label { text: "Port:"; Layout.preferredWidth: 60 }
                            QQC2.SpinBox {
                                from: 1
                                to: 65535
                                value: entry.port || 8006
                                editable: true
                                onValueModified: {
                                    var arr = ensureMultiHostsLen(5)
                                    arr[idx].port = value
                                    saveMultiHosts(arr)
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            spacing: 8
                            QQC2.Label { text: "Token ID:"; Layout.preferredWidth: 60 }
                            QQC2.TextField {
                                Layout.fillWidth: true
                                text: entry.tokenId || ""
                                placeholderText: "user@realm!tokenname"
                                onTextChanged: {
                                    var arr = ensureMultiHostsLen(5)
                                    arr[idx].tokenId = text
                                    saveMultiHosts(arr)
                                }
                            }
                        }

                        RowLayout {
                            spacing: 8
                            QQC2.Label { text: "Secret:"; Layout.preferredWidth: 60 }
                            QQC2.TextField {
                                id: mhSecretField
                                Layout.fillWidth: true
                                echoMode: TextInput.Password
                                placeholderText: "Stored in keyring after Apply"
                            }

                            QQC2.Button {
                                text: "Update Keyring"
                                icon.name: "dialog-password"
                                enabled: mhSecretField.text && mhSecretField.text.trim() !== ""
                                onClicked: {
                                    // SECURITY: do not persist secrets in config. Keep in memory for this dialog session only.
                                    mhSecretField.text = ""
                                }
                            }
                        }
                    }
                }
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

        // Auth/config refresh hint (Plasma sometimes caches plasmoid runtime state)
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Kirigami.Icon {
                source: "dialog-warning"
                implicitWidth: 16
                implicitHeight: 16
                opacity: 0.7
            }

            QQC2.Label {
                text: "If updating Host/Token settings doesn’t take effect immediately, restart Plasma (plasmashell) or remove/re-add the widget to force a full reload."
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

        // Auto-retry Section
        Kirigami.Heading {
            text: "Auto-Retry"
            level: 2
        }

        QQC2.CheckBox {
            id: autoRetryCheck
            text: "Automatically retry on connection errors"
            checked: true
        }

        GridLayout {
            columns: 2
            columnSpacing: 15
            rowSpacing: 12
            Layout.fillWidth: true
            enabled: autoRetryCheck.checked
            opacity: enabled ? 1.0 : 0.6

            QQC2.Label {
                text: "Start delay:"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            RowLayout {
                spacing: 8
                QQC2.SpinBox {
                    id: retryStartSpin
                    from: 1
                    to: 300
                    value: 5
                    editable: true
                }
                QQC2.Label {
                    text: "seconds"
                    opacity: 0.7
                }
            }

            QQC2.Label {
                text: "Max delay:"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            RowLayout {
                spacing: 8
                QQC2.SpinBox {
                    id: retryMaxSpin
                    from: 5
                    to: 3600
                    value: 300
                    editable: true
                }
                QQC2.Label {
                    text: "seconds"
                    opacity: 0.7
                }
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
                  "4. Token ID must be in the format: user@realm!tokenname\n" +
                  "5. IMPORTANT: If you enable 'Privilege Separation', you must grant permissions to BOTH the user and the token.\n" +
                  "   Proxmox calculates effective permissions as the intersection of user + token ACLs.\n" +
                  "6. Copy the token secret immediately (it is shown only once)"
            font.pixelSize: 11
            opacity: 0.7
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
