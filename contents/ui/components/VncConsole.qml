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
    // WebSocket proxy params — needed to connect through Proxmox's vncwebsocket endpoint
    property int    apiPort:   8006
    property bool   ignoreSsl: false
    // Controller reference — used to deliver the auth header directly in C++
    // without passing it through the QML/JS heap.
    property var    controller: null
    signal requestReconnect()

    function connectWithTicket(port) {
        vncPort         = port
        wsProxy.vncPort = port
        // Deliver auth header and ticket from C++ registry — never touches JS heap.
        if (controller) {
            controller.deliverConsoleAuth(consoleWindow.sessionKey, wsProxy)
            controller.deliverConsoleTicket(consoleWindow.sessionKey, wsProxy, vncClient)
        }
        wsProxy.start()
    }

    title: "Console — " + vmName + " (" + nodeName + ")"
    width: 1024
    height: 768
    minimumWidth: 640
    minimumHeight: 480
    visible: true

    // WebSocket-to-TCP shim: libvncclient speaks raw TCP; Proxmox only exposes
    // a WebSocket endpoint (vncwebsocket). VncWsProxy binds a random local TCP
    // port, accepts libvncclient's connection, and bridges bytes over a WS
    // connection to Proxmox — all transparent to libvncclient.
    ProxMon.VncWsProxy {
        id: wsProxy
        host:       consoleWindow.host
        apiPort:    consoleWindow.apiPort
        node:       consoleWindow.nodeName
        kind:       consoleWindow.kind
        vmid:       consoleWindow.vmid
        vncPort:    consoleWindow.vncPort
        ignoreSsl: consoleWindow.ignoreSsl

        onReady: function(localPort) {
            // Proxy is listening — hand the local port to libvncclient.
            // Ticket was already delivered via deliverConsoleTicket before start().
            vncClient.connectToVnc("127.0.0.1", localPort)
        }
        onErrorOccurred: function(message) {
            statusLabel.text = "Proxy error: " + message
        }
    }

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
    readonly property int maxReconnectAttempts: 3
    Timer {
        id: reconnectTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (consoleWindow.reconnectAttempts < maxReconnectAttempts) {
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
                vncClient.resizeRemote(consoleWindow.width, consoleWindow.height)
            }
        }
    }
    onWidthChanged:  resizeDebounce.restart()
    onHeightChanged: resizeDebounce.restart()

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
                    // Each pointer event is a discrete WebSocket frame — no TCP
                    // stream buffering issues, so send every event immediately.
                    vncClient.sendPointerEvent(p.x, p.y, mouse.buttons)
                }

                onPressed: function(mouse) {
                    if (!vncClient || vncClient.state !== "connected") return
                    var p = mapToFrame(mouse.x, mouse.y)
                    if (!p) return
                    vncClient.sendPointerEvent(p.x, p.y, mouse.buttons)
                }

                onReleased: function(mouse) {
                    if (!vncClient || vncClient.state !== "connected") return
                    var p = mapToFrame(mouse.x, mouse.y)
                    if (!p) return
                    vncClient.sendPointerEvent(p.x, p.y, 0)
                }

                onWheel: function(wheel) {
                    if (!vncClient || vncClient.state !== "connected") return
                    var p = mapToFrame(wheel.x, wheel.y)
                    if (!p) return
                    if (wheel.angleDelta.y !== 0) {
                        var stepsY = Math.max(1, Math.abs(Math.round(wheel.angleDelta.y / 120)))
                        vncClient.sendWheelEvent(p.x, p.y, stepsY, wheel.angleDelta.y > 0, false)
                    }
                    if (wheel.angleDelta.x !== 0) {
                        var stepsX = Math.max(1, Math.abs(Math.round(wheel.angleDelta.x / 120)))
                        vncClient.sendWheelEvent(p.x, p.y, stepsX, wheel.angleDelta.x > 0, true)
                    }
                    wheel.accepted = true
                }
            }

            Keys.onPressed: function(event) {
                if (vncClient && vncClient.state === "connected") {
                    // location 3 = numpad so KP_Enter/KP_0..9/KP_+- etc. are
                    // sent as distinct keysyms rather than their standard equivalents.
                    var loc = (event.modifiers & Qt.KeypadModifier) ? 3 : 0
                    vncClient.sendKeyEvent(event.key, event.text, loc, true)
                    event.accepted = true
                }
            }
            Keys.onReleased: function(event) {
                if (vncClient && vncClient.state === "connected") {
                    var loc = (event.modifiers & Qt.KeypadModifier) ? 3 : 0
                    vncClient.sendKeyEvent(event.key, event.text, loc, false)
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
        // Deliver auth header and ticket from C++ registry before starting proxy.
        if (controller) {
            controller.deliverConsoleAuth(consoleWindow.sessionKey, wsProxy)
            controller.deliverConsoleTicket(consoleWindow.sessionKey, wsProxy, vncClient)
        }
        wsProxy.start()
    }

    onClosing: {
        reconnectTimer.stop()
        resizeDebounce.stop()
        // Stop the proxy first — this aborts the loopback TCP socket so
        // rfbInitClient (which is blocked waiting for RFB handshake bytes)
        // sees a connection error and exits promptly. Without this, disconnect()
        // would block in m_thread->wait() indefinitely because the event loop
        // is suspended and the proxy can never deliver bytes to unblock the thread.
        wsProxy.stop()
        vncClient.disconnect()
    }
}
