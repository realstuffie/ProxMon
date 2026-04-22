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
    property var controller: null
    signal updateSecretsJson(string value)

    Layout.fillWidth: true
    spacing: 12

    QQC2.Label {
        text: "Configure up to 5 Proxmox endpoints. Secrets are stored in the system keyring after Apply. Trusted cert PEM/file settings from the Connection tab are shared across all endpoints."
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
            property var entry: (root.ensureMultiHostsLen(5)[idx])

            header: RowLayout {
                spacing: 12

                Kirigami.Heading {
                    text: "Endpoint " + (idx + 1)
                    level: 4
                }

                Item { Layout.fillWidth: true }

                QQC2.Switch {
                    text: checked ? "Enabled" : "Disabled"
                    checked: entry.enabled !== false
                    onToggled: {
                        var arr = root.ensureMultiHostsLen(5)
                        arr[idx].enabled = checked
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
                    }
                    QQC2.TextField {
                        Layout.fillWidth: true
                        text: entry.name || ""
                        placeholderText: "e.g. Home / Work"
                        onTextChanged: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[idx].name = text
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "Host:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    }
                    QQC2.TextField {
                        Layout.fillWidth: true
                        text: entry.host || ""
                        placeholderText: "192.168.1.100 or proxmox.local"
                        onTextChanged: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[idx].host = text
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "Port:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    }
                    QQC2.SpinBox {
                        from: 1
                        to: 65535
                        value: entry.port || 8006
                        editable: true
                        onValueModified: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[idx].port = value
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "API Token ID:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    }
                    QQC2.TextField {
                        Layout.fillWidth: true
                        text: entry.tokenId || ""
                        placeholderText: "user@realm!tokenname"
                        onTextChanged: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[idx].tokenId = text
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "API Token Secret:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
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
                                var entryNow = arr[idx]
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

                    QQC2.Label {
                        text: "PBS Enabled:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    }
                    QQC2.CheckBox {
                        checked: entry.pbsEnabled === true
                        text: checked ? "Enabled" : "Disabled"
                        onToggled: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[idx].pbsEnabled = checked
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "PBS Host:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    }
                    QQC2.TextField {
                        Layout.fillWidth: true
                        text: entry.pbsHost || ""
                        placeholderText: "backup-server or IP"
                        onTextChanged: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[idx].pbsHost = text
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "PBS Port:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    }
                    QQC2.SpinBox {
                        from: 1
                        to: 65535
                        value: entry.pbsPort || 8007
                        editable: true
                        onValueModified: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[idx].pbsPort = value
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "PBS Token ID:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    }
                    QQC2.TextField {
                        Layout.fillWidth: true
                        text: entry.pbsTokenId || ""
                        placeholderText: "user@pbs!tokenname"
                        onTextChanged: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[idx].pbsTokenId = text
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "PBS Token Secret:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    }
                    RowLayout {
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
                                var entryNow = arr[idx]
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
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    }
                    QQC2.CheckBox {
                        checked: entry.pbsIgnoreSsl === true
                        text: "Ignore SSL errors"
                        onToggled: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[idx].pbsIgnoreSsl = checked
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "PBS Warning Days:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    }
                    QQC2.SpinBox {
                        from: 1
                        to: 30
                        value: entry.pbsBackupWarningDays || 7
                        editable: true
                        onValueModified: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[idx].pbsBackupWarningDays = value
                            root.saveMultiHosts(arr)
                        }
                    }

                    QQC2.Label {
                        text: "PBS Stale Days:"
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    }
                    QQC2.SpinBox {
                        from: 1
                        to: 90
                        value: entry.pbsBackupStaleDays || 14
                        editable: true
                        onValueModified: {
                            var arr = root.ensureMultiHostsLen(5)
                            arr[idx].pbsBackupStaleDays = value
                            root.saveMultiHosts(arr)
                        }
                    }

                    Item {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        implicitHeight: 1
                    }

                    QQC2.Button {
                        Layout.columnSpan: 2
                        text: "Test PBS Connection"
                        onClicked: {
                            var arr = root.ensureMultiHostsLen(5)
                            var entryNow = arr[idx]
                            if (!root.controller) return
                            root.controller.testPBSConnection(entryNow.pbsHost || "", entryNow.pbsPort || 8007, entryNow.pbsTokenId || "", entryNow.pbsIgnoreSsl === true)
                        }
                    }
                }
            }
        }
    }
}
