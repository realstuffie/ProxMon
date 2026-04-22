import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

GridLayout {
    id: root

    property alias hostText: hostField.text
    property alias portValue: portField.value
    property alias tokenIdText: tokenIdField.text
    property alias tokenSecretText: tokenSecretField.text
    property var controller: null
    property alias pbsEnabled: pbsEnabledCheck.checked
    property alias pbsHostText: pbsHostField.text
    property alias pbsPortValue: pbsPortField.value
    property alias pbsTokenIdText: pbsTokenIdField.text
    property alias pbsIgnoreSsl: pbsIgnoreSslCheck.checked
    property alias pbsWarningDays: pbsWarningDaysField.value
    property alias pbsStaleDays: pbsStaleDaysField.value
    property int pbsRefreshInterval: 3600
    signal stashSecret(string secret)
    signal forgetSecret()
    signal stashPbsSecret(string secret)
    signal testPbsConnection(string host, int port, string tokenId, bool ignoreSslErrors)

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
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        QQC2.TextField {
            id: tokenSecretField
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: "Stored in keyring after Apply"
        }

        QQC2.Button {
            text: "Update Keyring"
            icon.name: "dialog-password"
            enabled: tokenSecretField.text && tokenSecretField.text.trim() !== ""
            onClicked: {
                root.stashSecret(tokenSecretField.text)
                tokenSecretField.text = ""
            }

            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: "Stores the secret in the keyring immediately."
        }

        QQC2.Button {
            text: "Forget"
            icon.name: "edit-clear"
            onClicked: {
                tokenSecretField.text = ""
                root.forgetSecret()
            }

            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: "Clears the locally entered secret. This does not delete existing keyring entries."
        }
    }

    Item {
        Layout.columnSpan: 2
        Layout.fillWidth: true
        implicitHeight: 8
    }

    QQC2.Label {
        text: "Proxmox Backup Server"
        font.bold: true
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
    }

    QQC2.CheckBox {
        id: pbsEnabledCheck
        text: checked ? "Enabled" : "Disabled"
    }

    ColumnLayout {
        Layout.columnSpan: 2
        Layout.fillWidth: true
        visible: pbsEnabledCheck.checked
        spacing: 10

        GridLayout {
            columns: 2
            columnSpacing: 15
            rowSpacing: 10
            Layout.fillWidth: true

            QQC2.Label { text: "PBS Host:" }
            QQC2.TextField {
                id: pbsHostField
                Layout.fillWidth: true
                placeholderText: "backup-server or IP"
            }

            QQC2.Label { text: "PBS Port:" }
            QQC2.SpinBox {
                id: pbsPortField
                from: 1
                to: 65535
                value: 8007
                editable: true
            }

            QQC2.Label { text: "PBS Token ID:" }
            QQC2.TextField {
                id: pbsTokenIdField
                Layout.fillWidth: true
                placeholderText: "user@pbs!tokenname"
            }

            QQC2.Label { text: "PBS Token Secret:" }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                QQC2.TextField {
                    id: pbsTokenSecretField
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    placeholderText: "Stored in keyring after Apply"
                }

                QQC2.Button {
                    text: "Update Keyring"
                    enabled: pbsTokenSecretField.text && pbsTokenSecretField.text.trim() !== ""
                    onClicked: {
                        root.stashPbsSecret(pbsTokenSecretField.text)
                        pbsTokenSecretField.text = ""
                    }
                }
            }

            QQC2.Label { text: "SSL Verification:" }
            QQC2.CheckBox {
                id: pbsIgnoreSslCheck
                text: "Ignore SSL errors"
            }

            QQC2.Label { text: "PBS Refresh:" }
            QQC2.ComboBox {
                id: pbsRefreshField
                Layout.fillWidth: true
                model: [
                    { text: "30 min", value: 1800 },
                    { text: "1 hour", value: 3600 },
                    { text: "3 hours", value: 10800 },
                    { text: "6 hours", value: 21600 },
                    { text: "12 hours", value: 43200 },
                    { text: "24 hours", value: 86400 }
                ]
                textRole: "text"
                valueRole: "value"
                onActivated: root.pbsRefreshInterval = currentValue
                Component.onCompleted: {
                    var intervals = [1800, 3600, 10800, 21600, 43200, 86400]
                    var idx = intervals.indexOf(root.pbsRefreshInterval)
                    currentIndex = idx >= 0 ? idx : 1
                }
            }

            QQC2.Label { text: "Warning threshold:" }
            QQC2.SpinBox {
                id: pbsWarningDaysField
                from: 1
                to: 30
                value: 7
                editable: true
            }

            QQC2.Label { text: "Stale threshold:" }
            QQC2.SpinBox {
                id: pbsStaleDaysField
                from: 1
                to: 90
                value: 14
                editable: true
            }
        }

        QQC2.Button {
            text: "Test PBS Connection"
            onClicked: root.testPbsConnection(pbsHostField.text, pbsPortField.value, pbsTokenIdField.text, pbsIgnoreSslCheck.checked)
        }
    }

}
