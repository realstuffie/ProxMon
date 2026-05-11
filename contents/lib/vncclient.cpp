#include "vncclient.h"
#include "vnckeysym.h"

#include <rfb/rfbclient.h>
#include <QDebug>

// ---------------------------------------------------------------------------
// Static callbacks — called by libvncclient from the worker thread
// ---------------------------------------------------------------------------

// Called when the server advertises a new framebuffer size.
static rfbBool resizeCallback(rfbClient *client)
{
    VncClient *self = static_cast<VncClient *>(rfbClientGetClientData(client, nullptr));
    if (!self) return FALSE;

    int w = client->width;
    int h = client->height;

    // Allocate framebuffer for libvncclient to write into (worker-thread side).
    delete[] client->frameBuffer;
    client->frameBuffer = new uint8_t[w * h * 4];
    client->format.bitsPerPixel = 32;
    client->format.redShift     = 16;
    client->format.greenShift   = 8;
    client->format.blueShift    = 0;
    client->format.redMax       = 0xff;
    client->format.greenMax     = 0xff;
    client->format.blueMax      = 0xff;

    // Cross to the main thread for the QML-facing property update.
    QMetaObject::invokeMethod(self, [self, w, h]() {
        self->setFrameSize(w, h);
    }, Qt::QueuedConnection);

    return TRUE;
}

// Called when a rectangular region of the framebuffer has been updated.
// A single HandleRFBServerMessage call can fire this many times (once per
// dirty-rect tile). Rather than copying the full framebuffer and queuing a
// separate invoke for every tile, just mark the frame dirty here. The poll
// loop copies and emits once after HandleRFBServerMessage returns, coalescing
// all tiles into a single frameUpdated signal.
static void updateCallback(rfbClient *client, int x, int y, int w, int h)
{
    Q_UNUSED(x) Q_UNUSED(y) Q_UNUSED(w) Q_UNUSED(h)
    VncClient *self = static_cast<VncClient *>(rfbClientGetClientData(client, nullptr));
    if (!self || !client->frameBuffer) return;
    self->markFrameDirty();
}

// ---------------------------------------------------------------------------
// VncClient
// ---------------------------------------------------------------------------

VncClient::VncClient(QObject *parent)
    : QObject(parent)
{
}

VncClient::~VncClient()
{
    disconnect();
}

void VncClient::connectToVnc(const QString &host, int port, const QString &vncTicket)
{
    if (m_rfb) {
        disconnect();
    }

    setState(QStringLiteral("connecting"));

    m_rfb = rfbGetClient(8, 3, 4); // 8 bits/sample, 3 samples/pixel, 4 bytes/pixel
    rfbClientSetClientData(m_rfb, nullptr, this);

    m_rfb->MallocFrameBuffer    = resizeCallback;
    m_rfb->GotFrameBufferUpdate = updateCallback;

    m_rfb->serverHost = strdup(host.toUtf8().constData());
    m_rfb->serverPort = port;

    // VNC password callback — stores ticket in client-data slot 1.
    m_rfb->GetPassword = [](rfbClient *client) -> char* {
        char *t = static_cast<char *>(rfbClientGetClientData(client, (void*)1));
        return t ? strdup(t) : strdup("");
    };
    rfbClientSetClientData(m_rfb, (void*)1, strdup(vncTicket.toUtf8().constData()));

    m_rfb->appData.encodingsString = "tight zrle hextile raw";

    // Run the entire RFB session on a worker thread:
    //
    //   • rfbInitClient() blocks during the TCP connect + RFB handshake.
    //     Running it on the main thread would freeze Qt's event loop, which
    //     VncWsProxy needs to deliver WebSocket data — instant deadlock.
    //
    //   • HandleRFBServerMessage() also blocks when a message arrives in
    //     fragments (it keeps calling recv() until the full message is present).
    //     Putting it on the main thread with WaitForMessage(timeout=0) causes
    //     exactly the same deadlock for large framebuffer updates.
    //
    // All Qt-facing work (state changes, frame signals) is marshalled back to
    // the main thread via QueuedConnection. Sends (sendKeyEvent, sendPointerEvent,
    // resizeRemote) are called from the main thread and reach libvncclient via
    // WriteToRFBServer; concurrent socket reads/writes are safe at the kernel level.

    m_running.store(true);
    m_thread = QThread::create([this]() {
        rfbClient *rfb = m_rfb; // local alias — avoids racing on m_rfb=nullptr

        bool ok = rfbInitClient(rfb, nullptr, nullptr);
        if (!ok) {
            // rfbInitClient frees rfb on failure. Null m_rfb directly here —
            // it's visible to the main thread after m_thread->wait() returns,
            // so disconnect() won't attempt a second rfbClientCleanup on it.
            m_rfb = nullptr;
            QMetaObject::invokeMethod(this, [this]() {
                if (m_state != QStringLiteral("disconnected")) {
                    setState(QStringLiteral("error"));
                    emit errorOccurred(QStringLiteral("Failed to connect to VNC server"));
                }
            }, Qt::QueuedConnection);
            return;
        }

        // Handshake done — notify main thread and reset modifier keys.
        QMetaObject::invokeMethod(this, [this]() {
            if (m_state == QStringLiteral("disconnected")) return;
            setState(QStringLiteral("connected"));
            SendKeyEvent(m_rfb, 0xFFE1, FALSE); // Shift
            SendKeyEvent(m_rfb, 0xFFE3, FALSE); // Ctrl
            SendKeyEvent(m_rfb, 0xFFE9, FALSE); // Alt
            SendKeyEvent(m_rfb, 0xFFE5, FALSE); // CapsLock
        }, Qt::QueuedConnection);

        // Poll loop — stays in this thread so HandleRFBServerMessage can block
        // freely on partial messages without stalling the Qt event loop.
        // WaitForMessage timeout is 16 ms so disconnect() is noticed quickly.
        while (m_running.load()) {
            int result = WaitForMessage(rfb, 16'000); // 16 ms in µs
            if (!m_running.load()) break;
            if (result < 0) {
                QMetaObject::invokeMethod(this, [this]() {
                    if (m_state != QStringLiteral("disconnected")) {
                        setState(QStringLiteral("error"));
                        emit errorOccurred(QStringLiteral("VNC connection error"));
                    }
                }, Qt::QueuedConnection);
                break;
            }
            if (result > 0) {
                if (!HandleRFBServerMessage(rfb)) {
                    QMetaObject::invokeMethod(this, [this]() {
                        if (m_state != QStringLiteral("disconnected")) {
                            setState(QStringLiteral("error"));
                            emit errorOccurred(QStringLiteral("Lost connection to VNC server"));
                        }
                    }, Qt::QueuedConnection);
                    break;
                }
                // Coalesced frame emit: all dirty-rect tiles from the message
                // above are now merged into one copy+signal, keeping the main
                // thread's event queue short and the renderer at a steady pace.
                if (m_frameDirty.exchange(false, std::memory_order_relaxed)
                        && rfb->frameBuffer) {
                    QImage frame(rfb->frameBuffer,
                                 rfb->width, rfb->height,
                                 rfb->width * 4,
                                 QImage::Format_RGB32);
                    QMetaObject::invokeMethod(this,
                        [this, img = frame.copy()]() {
                            emit frameUpdated(img, 0, 0, img.width(), img.height());
                        }, Qt::QueuedConnection);
                }
            }
        }

        // Thread-side cleanup: free the rfbClient and null the shared pointer
        // on the main thread so disconnect() can see it's already gone.
        rfbClientCleanup(rfb);
        m_rfb = nullptr; // direct write — visible to main thread after m_thread->wait() returns
    });
    m_thread->start();
}

void VncClient::disconnect()
{
    // Signal the poll loop to stop and wait for the thread to exit cleanly.
    // We do NOT call rfbClientCleanup here — the thread owns rfb and frees it
    // itself at the end of the lambda to avoid concurrent-access races.
    m_running.store(false);

    if (m_thread) {
        m_thread->wait(); // at most one WaitForMessage timeout (16 ms) + cleanup
        m_thread->deleteLater();
        m_thread = nullptr;
    }

    // In the rare case rfbInitClient failed and nulled m_rfb from the main thread
    // callback before disconnect() ran, or if connectToVnc was never called, this
    // is already null. Either way safe to touch on the main thread now.
    if (m_rfb) {
        rfbClientCleanup(m_rfb);
        m_rfb = nullptr;
    }

    setState(QStringLiteral("disconnected"));
}

void VncClient::sendKeyEvent(int qtKey, const QString &text, int location, bool pressed)
{
    if (!m_rfb) return;
    quint32 keysym = getKeysym(static_cast<Qt::Key>(qtKey), text, location);
    if (!keysym) return;
    quint32 trackKey = (quint32(qtKey) << 2) | (location & 3);
    if (pressed) {
        m_keyDownList[trackKey] = keysym;
    } else {
        if (!m_keyDownList.contains(trackKey)) return;
        keysym = m_keyDownList.take(trackKey);
    }
    SendKeyEvent(m_rfb, keysym, pressed ? TRUE : FALSE);
}

void VncClient::allKeysUp()
{
    if (!m_rfb) return;
    for (auto keysym : m_keyDownList) {
        SendKeyEvent(m_rfb, keysym, FALSE);
    }
    m_keyDownList.clear();
}

void VncClient::sendPointerEvent(int x, int y, int qtButtons)
{
    if (!m_rfb) return;
    // Map Qt button mask to VNC button mask.
    // Qt: Left=0x01, Right=0x02, Middle=0x04, Back=0x08, Forward=0x10
    // VNC: Left=bit0, Middle=bit1, Right=bit2, Back=bit7, Forward=bit8
    // Scroll (bits 3-6) is sent separately via sendWheelEvent, never via this path.
    int vncMask = 0;
    if (qtButtons & 0x01) vncMask |= (1 << 0); // Left
    if (qtButtons & 0x02) vncMask |= (1 << 2); // Right
    if (qtButtons & 0x04) vncMask |= (1 << 1); // Middle
    if (qtButtons & 0x08) vncMask |= (1 << 7); // Back   (button 8)
    if (qtButtons & 0x10) vncMask |= (1 << 8); // Forward (button 9)
    SendPointerEvent(m_rfb, x, y, vncMask);
}

void VncClient::sendWheelEvent(int x, int y, int steps, bool up, bool horizontal)
{
    if (!m_rfb) return;
    // VNC scroll buttons: up=bit3, down=bit4, left=bit5, right=bit6
    int btn = horizontal ? (up ? (1 << 5) : (1 << 6))
                         : (up ? (1 << 3) : (1 << 4));
    for (int i = 0; i < steps; i++) {
        SendPointerEvent(m_rfb, x, y, btn);
        SendPointerEvent(m_rfb, x, y, 0);
    }
}

void VncClient::setState(const QString &state)
{
    if (m_state == state) return;
    m_state = state;
    emit stateChanged();
}

void VncClient::setFrameSize(int w, int h)
{
    m_frameWidth  = w;
    m_frameHeight = h;
    emit frameSizeChanged();
}

void VncClient::resizeRemote(int width, int height)
{
    if (!m_rfb || width <= 0 || height <= 0) return;

    // Hand-craft the SetDesktopSize (251) message because libvncclient ≤ 0.9.15
    // truncates the SCREEN array (LibVNC issue #640), causing QEMU to silently
    // reject it. Wire format: 8-byte header + 1 × 16-byte SCREEN = 24 bytes.
    const quint16 w = static_cast<quint16>(width);
    const quint16 h = static_cast<quint16>(height);
    char buf[24] = {0};
    buf[0]  = 251;
    buf[2]  = static_cast<char>((w >> 8) & 0xFF);
    buf[3]  = static_cast<char>( w        & 0xFF);
    buf[4]  = static_cast<char>((h >> 8) & 0xFF);
    buf[5]  = static_cast<char>( h        & 0xFF);
    buf[6]  = 1; // number-of-screens
    buf[16] = static_cast<char>((w >> 8) & 0xFF);
    buf[17] = static_cast<char>( w        & 0xFF);
    buf[18] = static_cast<char>((h >> 8) & 0xFF);
    buf[19] = static_cast<char>( h        & 0xFF);

    if (!WriteToRFBServer(m_rfb, buf, sizeof(buf))) {
        qWarning() << "VncClient: WriteToRFBServer failed for SetDesktopSize"
                   << width << "x" << height;
    }
}
