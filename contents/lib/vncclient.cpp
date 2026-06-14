#include "vncclient.h"
#include "vnckeysym.h"

#include <rfb/rfbclient.h>
#include <string.h> // explicit_bzero
#include <QCoreApplication>
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

    // Request a full frame at the new dimensions immediately — without this
    // the server waits for the client to ask before sending any pixels.
    SendFramebufferUpdateRequest(client, 0, 0, w, h, FALSE);

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

void VncClient::setTicketSecure(const QByteArray &ticket)
{
    m_ticket = ticket;
}

VncClient::~VncClient()
{
    disconnect();
}

void VncClient::connectToVnc(const QString &host, int port)
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

    // Ticket stored in client-data slot 1; burned here after strdup.
    // C-side copy is zeroed by the worker thread after handshake.
    m_rfb->GetPassword = [](rfbClient *client) -> char* {
        char *t = static_cast<char *>(rfbClientGetClientData(client, (void*)1));
        return t ? strdup(t) : strdup("");
    };
    rfbClientSetClientData(m_rfb, (void*)1, strdup(m_ticket.constData()));
    m_ticket.fill(0);
    m_ticket.clear();

    m_rfb->appData.encodingsString = "tight zrle hextile raw";

    // RFB session runs on a worker thread — rfbInitClient blocks on I/O.
    // Qt-facing work is marshalled back via QueuedConnection. See docs/ARCHITECTURE.md.
    m_running.store(true);
    m_thread = QThread::create([this]() {
        rfbClient *rfb = m_rfb;

        // Grab the ticket before rfbInitClient — it frees rfb on failure so
        // we can't read client data afterward.
        char *ticketSlot = static_cast<char *>(rfbClientGetClientData(rfb, (void*)1));

        bool ok = rfbInitClient(rfb, nullptr, nullptr);
        if (!ok) {
            // rfbInitClient freed rfb on failure — do not touch it.
            // ticketSlot was saved before the call so it's still valid.
            if (ticketSlot) {
                explicit_bzero(ticketSlot, strlen(ticketSlot) + 1);
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

        // Handshake complete — null out the client-data slot first so
        // GetPassword cannot race the free, then zero and release.
        if (ticketSlot) {
            rfbClientSetClientData(rfb, (void*)1, nullptr);
            explicit_bzero(ticketSlot, strlen(ticketSlot) + 1);
            free(ticketSlot);
        }

        QMetaObject::invokeMethod(this, [this]() {
            if (m_state == QStringLiteral("disconnected")) return;
            setState(QStringLiteral("connected"));
        }, Qt::QueuedConnection);

        // Release any modifier keys the server may think are held.
        // Posted via the command queue so the writes stay on this thread
        // alongside the poll loop — not on the main thread.
        postCmd([](rfbClient *rfb) {
            SendKeyEvent(rfb, 0xFFE1, FALSE); // Shift
            SendKeyEvent(rfb, 0xFFE3, FALSE); // Ctrl
            SendKeyEvent(rfb, 0xFFE9, FALSE); // Alt
            SendKeyEvent(rfb, 0xFFE5, FALSE); // CapsLock
        });

        // Poll loop. WaitForMessage timeout is 16 ms so disconnect() is
        // noticed within one interval.
        while (m_running.load()) {
            // Drain pending commands (key/pointer/resize) before waiting for
            // server data. All rfbClient writes stay on this thread.
            {
                QQueue<std::function<void(rfbClient*)>> pending;
                {
                    QMutexLocker lk(&m_cmdMutex);
                    pending.swap(m_cmdQueue);
                }
                for (auto &cmd : pending)
                    cmd(rfb);
            }

            int result = WaitForMessage(rfb, 5'000); // µs — 5 ms keeps disconnect detection fast while reducing post-resize lag
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
                // One coalesced frame signal per server message.
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

    /* Purge any QueuedConnection invokeMethod calls the worker thread posted
       before it exited. If left in the queue they would fire after this object
       is destroyed (use-after-free → crash when closing the window during
       connection). Must run after wait() so no new events can be posted.
    */
    QCoreApplication::removePostedEvents(this);

    if (m_rfb) {
        rfbClientCleanup(m_rfb);
        m_rfb = nullptr;
    }

    {
        QMutexLocker lk(&m_cmdMutex);
        m_cmdQueue.clear();
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
    postCmd([keysym, pressed](rfbClient *rfb) {
        SendKeyEvent(rfb, keysym, pressed ? TRUE : FALSE);
    });
}

void VncClient::allKeysUp()
{
    if (!m_rfb) return;
    const QList<quint32> keysyms = m_keyDownList.values();
    m_keyDownList.clear();
    postCmd([keysyms](rfbClient *rfb) {
        for (auto keysym : keysyms)
            SendKeyEvent(rfb, keysym, FALSE);
    });
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
    postCmd([x, y, vncMask](rfbClient *rfb) {
        SendPointerEvent(rfb, x, y, vncMask);
    });
}

void VncClient::sendWheelEvent(int x, int y, int steps, bool up, bool horizontal)
{
    if (!m_rfb) return;
    // VNC scroll: up=bit3, down=bit4, left=bit5, right=bit6
    int btn = horizontal ? (up ? (1 << 5) : (1 << 6))
                         : (up ? (1 << 3) : (1 << 4));
    postCmd([x, y, steps, btn](rfbClient *rfb) {
        for (int i = 0; i < steps; i++) {
            SendPointerEvent(rfb, x, y, btn);
            SendPointerEvent(rfb, x, y, 0);
        }
    });
}

void VncClient::setState(const QString &state)
{
    if (m_state == state) return;
    m_state = state;
    emit stateChanged();
}

void VncClient::postCmd(std::function<void(rfbClient*)> fn)
{
    QMutexLocker lk(&m_cmdMutex);
    m_cmdQueue.enqueue(std::move(fn));
}

void VncClient::setFrameSize(int w, int h)
{
    m_frameWidth  = w;
    m_frameHeight = h;
    emit frameSizeChanged();
}
