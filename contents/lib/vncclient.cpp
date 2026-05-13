#include "vncclient.h"
#include "vnckeysym.h"

#include <rfb/rfbclient.h>
#include <QDebug>

// Called by libvncclient when the server advertises a new framebuffer size.
static rfbBool resizeCallback(rfbClient *client)
{
    VncClient *self = static_cast<VncClient *>(rfbClientGetClientData(client, nullptr));
    if (!self) return FALSE;

    int w = client->width;
    int h = client->height;

    delete[] client->frameBuffer;
    client->frameBuffer = new uint8_t[w * h * 4];
    client->format.bitsPerPixel = 32;
    client->format.redShift     = 16;
    client->format.greenShift   = 8;
    client->format.blueShift    = 0;
    client->format.redMax       = 0xff;
    client->format.greenMax     = 0xff;
    client->format.blueMax      = 0xff;

    QMetaObject::invokeMethod(self, [self, w, h]() {
        self->setFrameSize(w, h);
    }, Qt::QueuedConnection);

    return TRUE;
}

// Called when a dirty rect is received. A single HandleRFBServerMessage call
// may fire this many times (once per tile). We just mark the frame dirty here;
// the poll loop emits one coalesced signal after the full message is processed.
static void updateCallback(rfbClient *client, int x, int y, int w, int h)
{
    Q_UNUSED(x) Q_UNUSED(y) Q_UNUSED(w) Q_UNUSED(h)
    VncClient *self = static_cast<VncClient *>(rfbClientGetClientData(client, nullptr));
    if (!self || !client->frameBuffer) return;
    self->markFrameDirty();
}

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
    if (m_rfb || m_thread)
        disconnect();

    setState(QStringLiteral("connecting"));

    m_rfb = rfbGetClient(8, 3, 4); // 8 bits/sample, 3 samples/pixel, 4 bytes/pixel
    rfbClientSetClientData(m_rfb, nullptr, this);

    m_rfb->MallocFrameBuffer    = resizeCallback;
    m_rfb->GotFrameBufferUpdate = updateCallback;
    m_rfb->serverHost           = strdup(host.toUtf8().constData());
    m_rfb->serverPort           = port;

    // Password callback — ticket stored in client-data slot 1.
    m_rfb->GetPassword = [](rfbClient *client) -> char* {
        char *t = static_cast<char *>(rfbClientGetClientData(client, (void*)1));
        return t ? strdup(t) : strdup("");
    };
    rfbClientSetClientData(m_rfb, (void*)1, strdup(vncTicket.toUtf8().constData()));

    m_rfb->appData.encodingsString = "tight zrle hextile raw";

    // The entire RFB session runs on a worker thread:
    // rfbInitClient() and HandleRFBServerMessage() both block on socket I/O,
    // which would deadlock Qt's event loop (VncWsProxy needs it for WebSocket
    // delivery). All Qt-facing work is marshalled back via QueuedConnection.
    // Concurrent socket writes from the main thread (key/pointer/resize events)
    // are safe at the kernel level alongside the worker thread's reads.
    m_running.store(true);
    m_thread = QThread::create([this]() {
        rfbClient *rfb = m_rfb;

        // Grab the ticket before rfbInitClient — it frees rfb on failure so
        // we can't read client data afterward.
        char *ticketSlot = static_cast<char *>(rfbClientGetClientData(rfb, (void*)1));

        bool ok = rfbInitClient(rfb, nullptr, nullptr);
        if (!ok) {
            if (ticketSlot) {
                volatile char *p = ticketSlot;
                while (*p) *p++ = '\0';
                free(ticketSlot);
            }
            m_rfb = nullptr;
            QMetaObject::invokeMethod(this, [this]() {
                if (m_state != QStringLiteral("disconnected")) {
                    setState(QStringLiteral("error"));
                    emit errorOccurred(QStringLiteral("Failed to connect to VNC server"));
                }
            }, Qt::QueuedConnection);
            return;
        }

        // Handshake complete — zero and free the ticket immediately.
        if (ticketSlot) {
            volatile char *p = ticketSlot;
            while (*p) *p++ = '\0';
            free(ticketSlot);
            rfbClientSetClientData(rfb, (void*)1, nullptr);
        }

        QMetaObject::invokeMethod(this, [this]() {
            if (m_state == QStringLiteral("disconnected")) return;
            setState(QStringLiteral("connected"));
            // Release any modifier keys the server may think are held.
            SendKeyEvent(m_rfb, 0xFFE1, FALSE); // Shift
            SendKeyEvent(m_rfb, 0xFFE3, FALSE); // Ctrl
            SendKeyEvent(m_rfb, 0xFFE9, FALSE); // Alt
            SendKeyEvent(m_rfb, 0xFFE5, FALSE); // CapsLock
        }, Qt::QueuedConnection);

        // Poll loop. WaitForMessage timeout is 16 ms so disconnect() is
        // noticed within one interval.
        while (m_running.load()) {
            int result = WaitForMessage(rfb, 16'000); // µs
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
                // Emit one frame per server message, coalescing all dirty-rect
                // tiles. libvncclient leaves the alpha byte as 0x00; converting
                // to ARGB32_Premultiplied ORs in 0xFF000000 so the GPU texture
                // is fully opaque.
                if (m_frameDirty.exchange(false, std::memory_order_relaxed)
                        && rfb->frameBuffer) {
                    QImage frame(rfb->frameBuffer,
                                 rfb->width, rfb->height,
                                 rfb->width * 4,
                                 QImage::Format_RGB32);
                    QMetaObject::invokeMethod(this,
                        [this, img = frame.convertToFormat(QImage::Format_ARGB32_Premultiplied)]() {
                            emit frameUpdated(img, 0, 0, img.width(), img.height());
                        }, Qt::QueuedConnection);
                }
            }
        }

        rfbClientCleanup(rfb);
        m_rfb = nullptr;
    });
    m_thread->start();
}

void VncClient::disconnect()
{
    // Signal the poll loop to stop; wait for the thread to exit before
    // touching rfb — the thread owns it and frees it at the end of the lambda.
    m_running.store(false);

    if (m_thread) {
        m_thread->wait();
        m_thread->deleteLater();
        m_thread = nullptr;
    }

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
    for (auto keysym : m_keyDownList)
        SendKeyEvent(m_rfb, keysym, FALSE);
    m_keyDownList.clear();
}

void VncClient::sendPointerEvent(int x, int y, int qtButtons)
{
    if (!m_rfb) return;
    // Qt:  Left=0x01, Right=0x02, Middle=0x04, Back=0x08, Forward=0x10
    // VNC: Left=bit0, Middle=bit1, Right=bit2, Back=bit7, Forward=bit8
    int vncMask = 0;
    if (qtButtons & 0x01) vncMask |= (1 << 0);
    if (qtButtons & 0x02) vncMask |= (1 << 2);
    if (qtButtons & 0x04) vncMask |= (1 << 1);
    if (qtButtons & 0x08) vncMask |= (1 << 7);
    if (qtButtons & 0x10) vncMask |= (1 << 8);
    SendPointerEvent(m_rfb, x, y, vncMask);
}

void VncClient::sendWheelEvent(int x, int y, int steps, bool up, bool horizontal)
{
    if (!m_rfb) return;
    // VNC scroll: up=bit3, down=bit4, left=bit5, right=bit6
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

    // Hand-craft SetDesktopSize (251) — libvncclient ≤ 0.9.15 truncates the
    // SCREEN array (LibVNC #640), causing QEMU to silently reject it.
    // Wire format: 8-byte header + 1 × 16-byte SCREEN = 24 bytes total.
    const quint16 w = static_cast<quint16>(width);
    const quint16 h = static_cast<quint16>(height);
    char buf[24] = {0};
    buf[0]  = 251;
    buf[2]  = static_cast<char>((w >> 8) & 0xFF);
    buf[3]  = static_cast<char>( w        & 0xFF);
    buf[4]  = static_cast<char>((h >> 8) & 0xFF);
    buf[5]  = static_cast<char>( h        & 0xFF);
    buf[6]  = 1;
    buf[16] = static_cast<char>((w >> 8) & 0xFF);
    buf[17] = static_cast<char>( w        & 0xFF);
    buf[18] = static_cast<char>((h >> 8) & 0xFF);
    buf[19] = static_cast<char>( h        & 0xFF);

    if (!WriteToRFBServer(m_rfb, buf, sizeof(buf)))
        qWarning() << "VncClient: SetDesktopSize write failed" << width << "x" << height;
}
