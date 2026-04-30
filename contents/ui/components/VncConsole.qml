import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "../../lib/proxmox" as ProxMon

Window {
    id: consoleWindow

    property string vmName: ""
    property string nodeName: ""
    property int vmid: 0
    property string host: ""
    property int vncPort: 0
    property string vncTicket: ""

    title: "Console — " + vmName + " (" + nodeName + ")"
    width: 1024
    height: 768
    minimumWidth: 640
    minimumHeight: 480
    visible: true

    ProxMon.VncClient {
        id: vncClient

        onFrameUpdated: function(dataUrl) {
            vncCanvas.source = dataUrl
        }

        onStateChanged: {
            if (state === "error") {
                statusLabel.text = "Connection error"
            } else if (state === "connected") {
                statusLabel.text = ""
            } else if (state === "connecting") {
                statusLabel.text = "Connecting..."
            }
        }

        onErrorOccurred: function(message) {
            statusLabel.text = message
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#1a1a1a"

        Image {
            id: vncCanvas
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            smooth: true
            cache: false

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                hoverEnabled: true

                onClicked: function(mouse) {
                    vncCanvas.forceActiveFocus()
                }

                onPositionChanged: function(mouse) {
                    if (!vncClient || vncClient.state !== "connected") return
                    var scaleX = vncClient.frameWidth / vncCanvas.width
                    var scaleY = vncClient.frameHeight / vncCanvas.height
                    vncClient.sendPointerEvent(
                        Math.round(mouse.x * scaleX),
                        Math.round(mouse.y * scaleY),
                        mouse.buttons
                    )
                }

                onPressed: function(mouse) {
                    if (!vncClient || vncClient.state !== "connected") return
                    var scaleX = vncClient.frameWidth / vncCanvas.width
                    var scaleY = vncClient.frameHeight / vncCanvas.height
                    vncClient.sendPointerEvent(
                        Math.round(mouse.x * scaleX),
                        Math.round(mouse.y * scaleY),
                        mouse.buttons
                    )
                }

                onReleased: function(mouse) {
                    if (!vncClient || vncClient.state !== "connected") return
                    var scaleX = vncClient.frameWidth / vncCanvas.width
                    var scaleY = vncClient.frameHeight / vncCanvas.height
                    vncClient.sendPointerEvent(
                        Math.round(mouse.x * scaleX),
                        Math.round(mouse.y * scaleY),
                        0
                    )
                }
            }

            Keys.onPressed: function(event) {
                if (vncClient && vncClient.state === "connected") {
                    vncClient.sendKeyEvent(event.key, true)
                    event.accepted = true
                }
            }

            Keys.onReleased: function(event) {
                if (vncClient && vncClient.state === "connected") {
                    vncClient.sendKeyEvent(event.key, false)
                    event.accepted = true
                }
            }

            focus: true
        }

        PlasmaComponents.Label {
            id: statusLabel
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: 14
            visible: text !== ""
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 36
            color: Qt.rgba(0, 0, 0, 0.6)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8

                PlasmaComponents.Label {
                    text: vmName + " @ " + nodeName
                    color: "white"
                    font.pixelSize: 12
                    opacity: 0.8
                }

                Item { Layout.fillWidth: true }

                PlasmaComponents.Button {
                    text: "Disconnect"
                    onClicked: {
                        vncClient.disconnect()
                        consoleWindow.close()
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        vncClient.connectToVnc(host, vncPort, vncTicket)
    }

    onClosing: {
        vncClient.disconnect()
    }
}
