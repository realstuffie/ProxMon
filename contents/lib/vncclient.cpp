#include "vncclient.h"
#include "vnckeysym.h"

#include <rfb/rfbclient.h>
#include <QDebug>

// Static callback: called by libvncclient when framebuffer is allocated/resized
static rfbBool resizeCallback(rfbClient *client)
{
    VncClient *self = static_cast<VncClient *>(rfbClientGetClientData(client, nullptr));
    if (!self) return FALSE;

    int w = client->width;
    int h = client->height;

    // Allocate framebuffer for libvncclient to write into
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

// Static callback: called by libvncclient when a region of the framebuffer is updated
static void updateCallback(rfbClient *client, int x, int y, int w, int h)
{
    VncClient *self = static_cast<VncClient *>(rfbClientGetClientData(client, nullptr));
    if (!self || !client->frameBuffer) return;

    // Wrap the framebuffer in a QImage (no copy) and emit a deep copy for thread safety
    QImage frame(client->frameBuffer,
                 client->width,
                 client->height,
                 client->width * 4,
                 QImage::Format_RGB32);
    QMetaObject::invokeMethod(self, [self, img = frame.copy()]() {
        emit self->frameUpdated(img);
    }, Qt::QueuedConnection);

    Q_UNUSED(x); Q_UNUSED(y); Q_UNUSED(w); Q_UNUSED(h);
}

VncClient::VncClient(QObject *parent)
    : QObject(parent)
    , m_pollTimer(new QTimer(this))
{
    connect(m_pollTimer, &QTimer::timeout, this, &VncClient::pollLoop);
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

    m_rfb->MallocFrameBuffer   = resizeCallback;
    m_rfb->GotFrameBufferUpdate = updateCallback;

    // Set password (vncticket acts as the VNC password for Proxmox)
    m_rfb->serverHost = strdup(host.toUtf8().constData());
    m_rfb->serverPort = port;

    // libvncclient reads password via callback — store ticket for the lambda
    QString ticket = vncTicket;
    m_rfb->GetPassword = [](rfbClient *client) -> char* {
        // Retrieve ticket stored in client data slot 1
        char *t = static_cast<char *>(rfbClientGetClientData(client, (void*)1));
        return t ? strdup(t) : strdup("");
    };
    rfbClientSetClientData(m_rfb, (void*)1, strdup(ticket.toUtf8().constData()));

    if (!rfbInitClient(m_rfb, nullptr, nullptr)) {
        m_rfb = nullptr; // rfbInitClient frees on failure
        setState(QStringLiteral("error"));
        emit errorOccurred(QStringLiteral("Failed to connect to VNC server"));
        return;
    }

    setState(QStringLiteral("connected"));
    m_pollTimer->start(33); // ~30fps poll
    // Reset all modifier keys on connect
    SendKeyEvent(m_rfb, 0xFFE1, FALSE); // Shift
    SendKeyEvent(m_rfb, 0xFFE3, FALSE); // Ctrl
    SendKeyEvent(m_rfb, 0xFFE9, FALSE); // Alt
    SendKeyEvent(m_rfb, 0xFFE5, FALSE); // CapsLock
}

void VncClient::disconnect()
{
    m_pollTimer->stop();

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

void VncClient::sendPointerEvent(int x, int y, int buttonMask)
{
    if (m_rfb) {
        SendPointerEvent(m_rfb, x, y, buttonMask);
    }
}

void VncClient::setState(const QString &state)
{
    if (m_state == state) return;
    m_state = state;
    emit stateChanged();
}

void VncClient::pollLoop()
{
    if (!m_rfb) return;

    int result = WaitForMessage(m_rfb, 0); // non-blocking
    if (result > 0) {
        if (!HandleRFBServerMessage(m_rfb)) {
            setState(QStringLiteral("error"));
            emit errorOccurred(QStringLiteral("Lost connection to VNC server"));
            m_pollTimer->stop();
        }
    } else if (result < 0) {
        setState(QStringLiteral("error"));
        emit errorOccurred(QStringLiteral("VNC connection error"));
        m_pollTimer->stop();
    }
}

void VncClient::setFrameSize(int w, int h)
{
    m_frameWidth  = w;
    m_frameHeight = h;
    emit frameSizeChanged();
}