pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property var ensureMultiHostsLen: null
    property var saveMultiHosts: null
    property var multiHostSecretKey: null
    property string trustedCertPem: ""
    property string trustedCertPath: ""
    property string cfg_multiHostSecretsJson: "{}"
    property bool multiHostSharedCert: true
    property var controller: null
    signal updateSecretsJson(string value)
    signal pveCertPemEdited(string value)
    signal pveCertPathEdited(string value)
    signal multiHostSharedCertToggled(bool value)

    Layout.fillWidth: true
    spacing: 12

    QQC2.Label {
        text: "Configure up to 5 Proxmox endpoints. Secrets are stored in the system keyring after Apply."
        font.pixelSize: 11
        opacity: 0.7
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        QQC2.CheckBox {
            id: sharedCertToggle
            checked: root.multiHostSharedCert
            text: "Use shared trusted certificate for all endpoints"
            onToggled: root.multiHostSharedCertToggled(checked)
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: sharedCertToggle.checked
        spacing: 8

        GridLayout {
            columns: 2
            columnSpacing: 15
            rowSpacing: 10
            Layout.fillWidth: true

            QQC2.Label {
                text: "Trusted Proxmox VE PEM:"
                Layout.alignment: Qt.AlignRight | Qt.AlignTop
                horizontalAlignment: Text.AlignRight
            }
            QQC2.TextArea {
                id: sharedCertPemArea
                Layout.preferredWidth: 500
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
                id: sharedCertPathField
                implicitWidth: Math.max(160, contentWidth + leftPadding + rightPadding + 20)
                text: root.trustedCertPath
                placeholderText: "/etc/pve/pve-root-ca.pem"
                onTextChanged: {
                    if (root.trustedCertPath !== text) root.pveCertPathEdited(text)
                }
            }
        }
    }

    Repeater {
        model: 5

        delegate: Kirigami.Card {
            id: card
            Layout.fillWidth: true

            required property int index
            property var entry: (root.ensureMultiHostsLen(5)[index])

            header: RowLayout {
                spacing: 12

                Kirigami.Heading {
                    text: "Endpoint " + (card.index + 1)
                    level: 4
                }

                Item { Layout.fillWidth: true }

                QQC2.Switch {
                    text: checked ? "Enabled" : "Disabled"
                    checked: card.entry.enabled !== false
                    onToggled: {
                        var arr = root.ensureMultiHostsLen(5)
                        arr[card.index].enabled = checked
                        root.saveMultiHosts(arr)
                    }
                }
            }

            contentItem: Item {
                implicitWidth: delegateLayout.implicitWidth
                implicitHeight: delegateLayout.implicitHeight

                GridLayout {
                    id: delegateLayout
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.right: parent.right
                    columns: 2
                    columnSpacing: 15
                    rowSpacing: 12

                    QQC2.Label {
                        text: "Label:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                    QQC2.TextField {
                        Layout.fillWidth: true
                        text: card.entry.name || ""
                        placeholderText: "e.g. Home / Work"
                        onTextChanged: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[card.index].name = text
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "Host:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                    QQC2.TextField {
                        Layout.fillWidth: true
                        text: card.entry.host || ""
                        placeholderText: "192.168.1.100 or proxmox.local"
                        onTextChanged: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[card.index].host = text
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "Port:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                    QQC2.SpinBox {
                        from: 1
                        to: 65535
                        value: card.entry.port || 8006
                        editable: true
                        onValueModified: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[card.index].port = value
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "API Token ID:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                    QQC2.TextField {
                        Layout.fillWidth: true
                        text: card.entry.tokenId || ""
                        placeholderText: "user@realm!tokenname"
                        onTextChanged: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[card.index].tokenId = text
                            root.saveMultiHosts(arr)
                        }
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
                                var arr = root.ensureMultiHostsLen(5)
                                var entryNow = arr[card.index]
                                var key = root.multiHostSecretKey(entryNow)
                                if (!key) return

                                var map = {}
                                try { map = JSON.parse(root.cfg_multiHostSecretsJson || "{}") } catch (e) { map = {} }
                                map[key] = mhSecretField.text
                                root.updateSecretsJson(JSON.stringify(map))
                                mhSecretField.text = ""
                            }
                        }

                        QQC2.Button {
                            text: "Forget"
                            icon.name: "edit-clear"
                            onClicked: {
                                mhSecretField.text = ""
                            }

                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: "Clears the locally entered secret. This does not delete existing keyring entries."
                        }
                    }

                    // Per-endpoint cert fields (only shown when shared cert is disabled)
                    QQC2.Label {
                        text: "Trusted Proxmox VE PEM:"
                        visible: !sharedCertToggle.checked
                        Layout.alignment: Qt.AlignRight | Qt.AlignTop
                        horizontalAlignment: Text.AlignRight
                    }
                    QQC2.TextArea {
                        visible: !sharedCertToggle.checked
                        Layout.preferredWidth: 500
                        Layout.preferredHeight: 80
                        text: card.entry.trustedCertPem || ""
                        placeholderText: "Paste PEM certificate here (optional)"
                        font.family: "JetBrains Mono"
                        wrapMode: TextEdit.Wrap
                        onTextChanged: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[card.index].trustedCertPem = text
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "Trusted Proxmox VE File:"
                        visible: !sharedCertToggle.checked
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                    QQC2.TextField {
                        visible: !sharedCertToggle.checked
                        implicitWidth: Math.max(160, contentWidth + leftPadding + rightPadding + 20)
                        text: card.entry.trustedCertPath || ""
                        placeholderText: "/etc/pve/pve-root-ca.pem (optional)"
                        onTextChanged: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[card.index].trustedCertPath = text
                            root.saveMultiHosts(arr)
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
                            checked: card.entry.ignoreSsl === true
                            text: "Ignore SSL certificate errors"
                            onToggled: {
                                var arr = root.ensureMultiHostsLen(5)
                                arr[card.index].ignoreSsl = checked
                                root.saveMultiHosts(arr)
                            }
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

                    QQC2.Label {
                        text: "PBS Enabled:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                    QQC2.CheckBox {
                        id: pbsEnabledCheck
                        checked: card.entry.pbsEnabled === true
                        text: checked ? "Enabled" : "Disabled"
                        onToggled: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[card.index].pbsEnabled = checked
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "PBS Host:"
                        visible: pbsEnabledCheck.checked
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                    QQC2.TextField {
                        visible: pbsEnabledCheck.checked
                        Layout.fillWidth: true
                        text: card.entry.pbsHost || ""
                        placeholderText: "backup-server or IP"
                        onTextChanged: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[card.index].pbsHost = text
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "PBS Port:"
                        visible: pbsEnabledCheck.checked
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                    QQC2.SpinBox {
                        visible: pbsEnabledCheck.checked
                        from: 1
                        to: 65535
                        value: card.entry.pbsPort || 8007
                        editable: true
                        onValueModified: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[card.index].pbsPort = value
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "PBS Token ID:"
                        visible: pbsEnabledCheck.checked
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                    QQC2.TextField {
                        visible: pbsEnabledCheck.checked
                        Layout.fillWidth: true
                        text: card.entry.pbsTokenId || ""
                        placeholderText: "user@pbs!tokenname"
                        onTextChanged: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[card.index].pbsTokenId = text
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "PBS Token Secret:"
                        visible: pbsEnabledCheck.checked
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                    RowLayout {
                        visible: pbsEnabledCheck.checked
                        Layout.fillWidth: true
                        spacing: 8

                        QQC2.TextField {
                            id: pbsSecretField
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            placeholderText: "Stored in keyring after Apply"
                        }

                        QQC2.Button {
                            text: "Update Keyring"
                            enabled: pbsSecretField.text && pbsSecretField.text.trim() !== ""
                            onClicked: {
                                var arr = root.ensureMultiHostsLen(5)
                                var entryNow = arr[card.index]
                                var host = String(entryNow.pbsHost || "").trim()
                                if (!host) return

                                var map = {}
                                try { map = JSON.parse(root.cfg_multiHostSecretsJson || "{}") } catch (e) { map = {} }
                                map["pbsTokenSecret:" + host] = pbsSecretField.text
                                root.updateSecretsJson(JSON.stringify(map))
                                pbsSecretField.text = ""
                            }
                        }
                    }

                    QQC2.Label {
                        text: "PBS SSL:"
                        visible: pbsEnabledCheck.checked
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                    ColumnLayout {
                        visible: pbsEnabledCheck.checked
                        spacing: 2
                        QQC2.CheckBox {
                            id: pbsIgnoreSslCheck
                            checked: card.entry.pbsIgnoreSsl === true
                            text: "Ignore SSL errors"
                            onToggled: {
                                var arr = root.ensureMultiHostsLen(5)
                                arr[card.index].pbsIgnoreSsl = checked
                                root.saveMultiHosts(arr)
                            }
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

                    QQC2.Label {
                        text: "PBS Warning Days:"
                        visible: pbsEnabledCheck.checked
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                    QQC2.SpinBox {
                        visible: pbsEnabledCheck.checked
                        from: 1
                        to: 30
                        value: card.entry.pbsBackupWarningDays || 7
                        editable: true
                        onValueModified: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[card.index].pbsBackupWarningDays = value
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "PBS Stale Days:"
                        visible: pbsEnabledCheck.checked
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                    QQC2.SpinBox {
                        visible: pbsEnabledCheck.checked
                        from: 1
                        to: 90
                        value: card.entry.pbsBackupStaleDays || 14
                        editable: true
                        onValueModified: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[card.index].pbsBackupStaleDays = value
                            root.saveMultiHosts(arr)
                        }
                    }

                    Item {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        implicitHeight: 1
                    }

                }
            }
        }
    }
}
