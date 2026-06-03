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
    property string trustedCertPem: ""
    property string trustedCertPath: ""
    property alias pbsEnabled: pbsEnabledCheck.checked
    property alias pbsHostText: pbsHostField.text
    property alias pbsPortValue: pbsPortField.value
    property alias pbsTokenIdText: pbsTokenIdField.text
    property alias ignoreSsl: ignoreSslCheck.checked
    property alias pbsIgnoreSsl: pbsIgnoreSslCheck.checked
    property alias pbsTrustedCertPem: pbsTrustedCertPemField.text
    property alias pbsTrustedCertPath: pbsTrustedCertPathField.text
    property alias pbsWarningDays: pbsWarningDaysField.value
    property alias pbsStaleDays: pbsStaleDaysField.value
    property int pbsRefreshInterval: 3600
    signal stashSecret(string secret)
    signal forgetSecret()
    signal stashPbsSecret(string secret)
    signal pveCertPemEdited(string value)
    signal pveCertPathEdited(string value)

    columns: 2
    columnSpacing: 15
    rowSpacing: 12
    Layout.fillWidth: true

    QQC2.Label {
        text: "Host:"
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        horizontalAlignment: Text.AlignRight
    }
    QQC2.TextField {
        id: hostField
        Layout.fillWidth: true
        placeholderText: "192.168.1.100 or proxmox.local"
    }

    QQC2.Label {
        text: "Port:"
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        horizontalAlignment: Text.AlignRight
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
        horizontalAlignment: Text.AlignRight
    }
    QQC2.TextField {
        id: tokenIdField
        Layout.fillWidth: true
        placeholderText: "user@realm!tokenname"
    }

    QQC2.Label {
        text: "API Token Secret:"
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        horizontalAlignment: Text.AlignRight
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

    QQC2.Label {
        text: "Trusted Proxmox VE PEM:"
        Layout.alignment: Qt.AlignRight | Qt.AlignTop
        horizontalAlignment: Text.AlignRight
    }
    QQC2.TextArea {
        id: pveTrustedCertPemArea
        Layout.fillWidth: true
        Layout.preferredHeight: 90
        text: root.trustedCertPem
        placeholderText: "Paste PEM certificate here. If set, this takes precedence over cert file path."
        wrapMode: TextEdit.Wrap
        font.family: "JetBrains Mono"
        onTextChanged: {
            if (root.trustedCertPem !== text) root.pveCertPemEdited(text)
        }
    }

    QQC2.Label {
        text: "Trusted Proxmox VE File:"
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        horizontalAlignment: Text.AlignRight
    }
    QQC2.TextField {
        id: pveTrustedCertPathField2
        Layout.fillWidth: true
        text: root.trustedCertPath
        placeholderText: "/etc/pve/pve-root-ca.pem"
        onTextChanged: {
            if (root.trustedCertPath !== text) root.pveCertPathEdited(text)
        }
    }

    QQC2.Label {
        text: "SSL Verification:"
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        horizontalAlignment: Text.AlignRight
    }
    ColumnLayout {
        spacing: 2
        QQC2.CheckBox {
            id: ignoreSslCheck
            text: "Ignore SSL certificate errors"
        }
        QQC2.Label {
            text: "⚠ Disables certificate validation. Only use on trusted networks with self-signed certs."
            visible: ignoreSslCheck.checked
            font.pixelSize: 11
            color: "#ff3333"
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.leftMargin: 24
        }
    }

    Item {
        Layout.columnSpan: 2
        Layout.fillWidth: true
        implicitHeight: 8
    }

    QQC2.Label {
        text: "Proxmox Backup Server:"
        font.bold: true
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        horizontalAlignment: Text.AlignRight
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

            QQC2.Label { text: "PBS Host:"; Layout.alignment: Qt.AlignRight | Qt.AlignVCenter; horizontalAlignment: Text.AlignRight }
            QQC2.TextField {
                id: pbsHostField
                Layout.fillWidth: true
                placeholderText: "backup-server or IP"
            }

            QQC2.Label { text: "PBS Port:"; Layout.alignment: Qt.AlignRight | Qt.AlignVCenter; horizontalAlignment: Text.AlignRight }
            QQC2.SpinBox {
                id: pbsPortField
                from: 1
                to: 65535
                value: 8007
                editable: true
            }

            QQC2.Label { text: "PBS Token ID:"; Layout.alignment: Qt.AlignRight | Qt.AlignVCenter; horizontalAlignment: Text.AlignRight }
            QQC2.TextField {
                id: pbsTokenIdField
                Layout.fillWidth: true
                placeholderText: "user@pbs!tokenname"
            }

            QQC2.Label { text: "PBS Token Secret:"; Layout.alignment: Qt.AlignRight | Qt.AlignVCenter; horizontalAlignment: Text.AlignRight }
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

            QQC2.Label { text: "SSL Verification:"; Layout.alignment: Qt.AlignRight | Qt.AlignVCenter; horizontalAlignment: Text.AlignRight }
            ColumnLayout {
                spacing: 2
                QQC2.CheckBox {
                    id: pbsIgnoreSslCheck
                    text: "Ignore SSL errors"
                }
                QQC2.Label {
                    text: "⚠ Disables certificate validation. Only use on trusted networks with self-signed certs."
                    visible: pbsIgnoreSslCheck.checked
                    font.pixelSize: 11
                    color: "#ff3333"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.leftMargin: 24
                }
            }

            QQC2.Label { text: "PBS Trusted Cert PEM:"; Layout.alignment: Qt.AlignRight | Qt.AlignTop; horizontalAlignment: Text.AlignRight }
            QQC2.TextArea {
                id: pbsTrustedCertPemField
                Layout.fillWidth: true
                placeholderText: "Paste PEM certificate here (optional)"
                font.family: "JetBrains Mono"
                implicitHeight: 80
            }
            QQC2.Label { text: "PBS Trusted Cert Path:"; Layout.alignment: Qt.AlignRight | Qt.AlignVCenter; horizontalAlignment: Text.AlignRight }
            QQC2.TextField {
                id: pbsTrustedCertPathField
                Layout.fillWidth: true
                placeholderText: "/path/to/cert.pem (optional)"
            }
            QQC2.Label { text: "PBS Refresh:"; Layout.alignment: Qt.AlignRight | Qt.AlignVCenter; horizontalAlignment: Text.AlignRight }
            QQC2.ComboBox {
                id: pbsRefreshField
                implicitWidth: 90
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

            QQC2.Label { text: "Warning threshold:"; Layout.alignment: Qt.AlignRight | Qt.AlignVCenter; horizontalAlignment: Text.AlignRight }
            QQC2.SpinBox {
                id: pbsWarningDaysField
                from: 1
                to: 30
                value: 7
                editable: true
            }

            QQC2.Label { text: "Stale threshold:"; Layout.alignment: Qt.AlignRight | Qt.AlignVCenter; horizontalAlignment: Text.AlignRight }
            QQC2.SpinBox {
                id: pbsStaleDaysField
                from: 1
                to: 90
                value: 14
                editable: true
            }
        }

    }

}
