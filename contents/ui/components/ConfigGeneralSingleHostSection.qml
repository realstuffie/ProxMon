import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

GridLayout {
    id: root

    property alias hostText: hostField.text
    property alias portValue: portField.value
    property alias tokenIdText: tokenIdField.text
    property alias tokenSecretText: tokenSecretField.text
    signal stashSecret(string secret)
    signal forgetSecret()

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
            QQC2.ToolTip.text: "Stores the secret temporarily; the widget will move it into the keyring on next load."
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

}
