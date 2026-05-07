import QtQuick
import QtQuick.Window
import org.kde.plasma.components as PlasmaComponents
import "../../lib/proxmox" as ProxMon

Window {
    id: consoleWindow

    property string vmName: ""
    property string nodeName: ""
    property int vmid: 0
    property string sessionKey: ""
    property string kind: ""
    property string host: ""
    property int vncPort: 0
    property string vncTicket: ""
    signal requestReconnect()
    
    function connectWithTicket(port, ticket) {
        vncPort = port
        vncTicket = ticket
        vncClient.connectToVnc(host, port, ticket)
    }

    title: "Console — " + vmName + " (" + nodeName + ")"
    width: 1024
    height: 768
    minimumWidth: 640
    minimumHeight: 480
    visible: true

    ProxMon.VncClient {
        id: vncClient

        onFrameUpdated: function(image, x, y, w, h) {
            vncCanvas.updateFrame(image, x, y, w, h)
        }

        onStateChanged: {
            if (state === "error") {
                statusLabel.text = "Connection lost - reconnecting..."
                reconnectTimer.start()
            } else if (state === "connected") {
                statusLabel.text = ""
                reconnectTimer.stop()
                consoleWindow.reconnectAttempts = 0
            } else if (state === "connecting") {
                statusLabel.text = "Connecting..."
            }
        }

        onErrorOccurred: function(message) {
            statusLabel.text = message
        }
    }
    property int reconnectAttempts: 0
    Timer {
        id: reconnectTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (consoleWindow.reconnectAttempts < 3) {
                consoleWindow.reconnectAttempts += 1
                requestReconnect()
            } else {
                statusLabel.text = "Connection lost - please reopen"
            }
        }
    }

    // Debounce window-resize → SetDesktopSize so we don't spam QEMU during
    // a drag. Fires 300ms after the last width/height change with the final
    // dimensions. Connected via Window.onWidthChanged/onHeightChanged below.
    Timer {
        id: resizeDebounce
        interval: 100
        repeat: false
        onTriggered: {
            if (vncClient.state === "connected"
                && consoleWindow.width > 0 && consoleWindow.height > 0) {
                console.log("[VNC resize] firing", consoleWindow.width, "x", consoleWindow.height)
                vncClient.resizeRemote(consoleWindow.width, consoleWindow.height)
            } else {
                console.log("[VNC resize] skipped state=", vncClient.state)
            }
        }
    }
    onWidthChanged:  { console.log("[VNC resize] widthChanged", width); resizeDebounce.restart() }
    onHeightChanged: { console.log("[VNC resize] heightChanged", height); resizeDebounce.restart() }
    

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
                id: mouseArea
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                hoverEnabled: true

                // Throttle move-events to ~60Hz. High-polling mice fire
                // onPositionChanged thousands of times per second; sending a
                // VNC pointer event for each clogs the server-side queue and
                // acts on stale positions. Strategy: send immediately if
                // enough time has elapsed since the last send, otherwise
                // stash the latest position and let a flush timer send it
                // when the throttle interval expires. Press/release bypass
                // the throttle entirely — button transitions must not be
                // dropped or delayed.
                property int  lastMoveSentMs: 0
                property var  pendingMove: null
                readonly property int moveIntervalMs: 16  // ~60Hz

                Timer {
                    id: moveFlush
                    interval: 1
                    repeat: false
                    onTriggered: {
                        if (!mouseArea.pendingMove) return
                        if (vncClient && vncClient.state === "connected") {
                            var m = mouseArea.pendingMove
                            vncClient.sendPointerEvent(m.x, m.y, m.buttons)
                            mouseArea.lastMoveSentMs = Date.now()
                        }
                        mouseArea.pendingMove = null
                    }
                }

                // Map canvas (window) coords to framebuffer coords using
                // the same aspect-preserving fit math as VncFrameView::paint.
                // Returns null if the cursor is in the letterbox/pillarbox
                // area outside the rendered framebuffer.
                function mapToFrame(mx, my) {
                    var fbW = vncClient.frameWidth
                    var fbH = vncClient.frameHeight
                    var cw  = vncCanvas.width
                    var ch  = vncCanvas.height
                    if (fbW <= 0 || fbH <= 0 || cw <= 0 || ch <= 0) return null
                    var s = Math.min(cw / fbW, ch / fbH)
                    var fitW = fbW * s
                    var fitH = fbH * s
                    var ox = (cw - fitW) / 2
                    var oy = (ch - fitH) / 2
                    var fx = (mx - ox) / s
                    var fy = (my - oy) / s
                    if (fx < 0 || fy < 0 || fx >= fbW || fy >= fbH) return null
                    return { x: Math.round(fx), y: Math.round(fy) }
                }

                onClicked: function(mouse) {
                    vncCanvas.forceActiveFocus()
                }

                onPositionChanged: function(mouse) {
                    if (!vncClient || vncClient.state !== "connected") return
                    var p = mapToFrame(mouse.x, mouse.y)
                    if (!p) return
                    var now = Date.now()
                    var elapsed = now - lastMoveSentMs
                    if (elapsed >= moveIntervalMs) {
                        // Past throttle window — send straight away.
                        vncClient.sendPointerEvent(p.x, p.y, mouse.buttons)
                        lastMoveSentMs = now
                        pendingMove = null
                        moveFlush.stop()
                    } else {
                        // Inside throttle window — coalesce. Keep the latest
                        // position and arm the flush timer for the remainder
                        // of the interval. Repeated movement keeps overwriting
                        // pendingMove until the timer fires.
                        pendingMove = { x: p.x, y: p.y, buttons: mouse.buttons }
                        if (!moveFlush.running) {
                            moveFlush.interval = moveIntervalMs - elapsed
                            moveFlush.start()
                        }
                    }
                }

                onPressed: function(mouse) {
                    if (!vncClient || vncClient.state !== "connected") return
                    var p = mapToFrame(mouse.x, mouse.y)
                    if (!p) return
                    // Bypass throttle: button transitions must not be deferred.
                    pendingMove = null
                    moveFlush.stop()
                    vncClient.sendPointerEvent(p.x, p.y, mouse.buttons)
                    lastMoveSentMs = Date.now()
                }

                onReleased: function(mouse) {
                    if (!vncClient || vncClient.state !== "connected") return
                    var p = mapToFrame(mouse.x, mouse.y)
                    if (!p) return
                    pendingMove = null
                    moveFlush.stop()
                    vncClient.sendPointerEvent(p.x, p.y, 0)
                    lastMoveSentMs = Date.now()
                }
            }

            Keys.onPressed: function(event) {
                if (vncClient && vncClient.state === "connected") {
                    vncClient.sendKeyEvent(event.key, event.text, 0, true)
                    event.accepted = true
                }
            }
            Keys.onReleased: function(event) {
                if (vncClient && vncClient.state === "connected") {
                    vncClient.sendKeyEvent(event.key, event.text, 0, false)
                    event.accepted = true
                }
            }

            focus: true
            onActiveFocusChanged: if (!activeFocus) vncClient.allKeysUp()
        }

        PlasmaComponents.Label {
            id: statusLabel
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: 14
            visible: text !== ""
        }

    }

    Component.onCompleted: {
        console.log("[VNC resize] VncConsole loaded, initial size", width, "x", height)
        vncClient.connectToVnc(host, vncPort, vncTicket)
    }

    onClosing: {
        vncClient.disconnect()
        reconnectTimer.stop()
    }
}
