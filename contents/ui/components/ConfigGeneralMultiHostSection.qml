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
                width: parent ? parent.width : implicitWidth
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

            contentItem: GridLayout {
                columns: 2
                columnSpacing: 15
                rowSpacing: 12
                width: parent ? parent.width : implicitWidth

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
            }
        }
    }
}
