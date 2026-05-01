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

        onFrameUpdated: function(image) {
            vncCanvas.updateFrame(image)
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

    function qtKeyToKeysym(key) {
    switch(key) {
        case Qt.Key_Backspace:  return 0xFF08
        case Qt.Key_Tab:        return 0xFF09
        case Qt.Key_Return:     return 0xFF0D
        case Qt.Key_Escape:     return 0xFF1B
        case Qt.Key_Delete:     return 0xFFFF
        case Qt.Key_Home:       return 0xFF50
        case Qt.Key_Left:       return 0xFF51
        case Qt.Key_Up:         return 0xFF52
        case Qt.Key_Right:      return 0xFF53
        case Qt.Key_Down:       return 0xFF54
        case Qt.Key_End:        return 0xFF57
        case Qt.Key_PageUp:     return 0xFF55
        case Qt.Key_PageDown:   return 0xFF56
        case Qt.Key_F1:         return 0xFFBE
        case Qt.Key_F2:         return 0xFFBF
        case Qt.Key_F3:         return 0xFFC0
        case Qt.Key_F4:         return 0xFFC1
        case Qt.Key_F5:         return 0xFFC2
        case Qt.Key_F6:         return 0xFFC3
        case Qt.Key_F7:         return 0xFFC4
        case Qt.Key_F8:         return 0xFFC5
        case Qt.Key_F9:         return 0xFFC6
        case Qt.Key_F10:        return 0xFFC7
        case Qt.Key_F11:        return 0xFFC8
        case Qt.Key_F12:        return 0xFFC9
        case Qt.Key_Control:    return 0xFFE3
        case Qt.Key_Shift:      return 0xFFE1
        case Qt.Key_Alt:        return 0xFFE9
        case Qt.Key_Super_L:    return 0xFFEB
        case Qt.Key_CapsLock:   return 0xFFE5
        case Qt.Key_NumLock:    return 0xFF7F
        case Qt.Key_ScrollLock: return 0xFF14
        case Qt.Key_Insert:     return 0xFF63
        case Qt.Key_Pause:      return 0xFF13
        case Qt.Key_Print:      return 0xFF61
        case Qt.key_exclamation: return 0x0021
        case Qt.key_at:          return 0x0040
        case Qt.key_number_sign: return 0x0023
        case Qt.key_dollar:      return 0x0024
        case Qt.key_percent:     return 0x0025
        case Qt.key_ampersand:   return 0x0026
        case Qt.key_apostrophe:  return 0x0027
        case Qt.key_parenleft:   return 0x0028
        case Qt.key_parenright:  return 0x0029
        case Qt.key_asterisk:    return 0x002A
        case Qt.key_plus:        return 0x002B
        case Qt.key_comma:       return 0x002C
        case Qt.key_minus:       return 0x002D
        case Qt.key_period:      return 0x002E
        case Qt.key_slash:       return 0x002F
        case Qt.key_0:           return 0x0030
        case Qt.key_1:           return 0x0031
        case Qt.key_2:           return 0x0032
        case Qt.key_3:           return 0x0033
        case Qt.key_4:           return 0x0034
        case Qt.key_5:           return 0x0035
        case Qt.key_6:           return 0x0036
        case Qt.key_7:           return 0x0037
        case Qt.key_8:           return 0x0038
        case Qt.key_9:           return 0x0039
        case Qt.key_colon:       return 0x003A
        case Qt.key_semicolon:   return 0x003B
        case Qt.key_less:        return 0x003C
        case Qt.key_equal:       return 0x003D
        case Qt.key_greater:     return 0x003E
        case Qt.key_question:    return 0x003F
        case Qt.key_at_sign:     return 0x0040
        default:                return key
    }
}
    Rectangle {
        anchors.fill: parent
        color: "#1a1a1a"

        ProxMon.VncFrameView {
            id: vncCanvas
            anchors.fill: parent

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
                    var key = event.key
                    vncClient.sendKeyEvent(key, true)
                    event.accepted = true
                }
            }
            Keys.onReleased: function(event) {
                if (vncClient && vncClient.state === "connected") {
                    var key = event.key
                    vncClient.sendKeyEvent(key, false)
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
