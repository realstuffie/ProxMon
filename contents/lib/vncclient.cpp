#include "vncclient.h"

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

static quint32 qtKeyToKeysym(quint32 key)
{
    switch (key) {
    case Qt::Key_Backspace:  return 0xFF08;
    case Qt::Key_Tab:        return 0xFF09;
    case Qt::Key_Return:     return 0xFF0D;
    case Qt::Key_Enter:      return 0xFF8D;
    case Qt::Key_Escape:     return 0xFF1B;
    case Qt::Key_Delete:     return 0xFFFF;
    case Qt::Key_Home:       return 0xFF50;
    case Qt::Key_Left:       return 0xFF51;
    case Qt::Key_Up:         return 0xFF52;
    case Qt::Key_Right:      return 0xFF53;
    case Qt::Key_Down:       return 0xFF54;
    case Qt::Key_PageUp:     return 0xFF55;
    case Qt::Key_PageDown:   return 0xFF56;
    case Qt::Key_End:        return 0xFF57;
    case Qt::Key_Insert:     return 0xFF63;
    case Qt::Key_CapsLock:   return 0xFFE5;
    case Qt::Key_NumLock:    return 0xFF7F;
    case Qt::Key_ScrollLock: return 0xFF14;
    case Qt::Key_Shift:      return 0xFFE1;
    case Qt::Key_Control:    return 0xFFE3;
    case Qt::Key_Alt:        return 0xFFE9;
    case Qt::Key_AltGr:      return 0xFFEA;
    case Qt::Key_Meta:
    case Qt::Key_Super_L:    return 0xFFEB;
    case Qt::Key_Super_R:    return 0xFFEC;
    case Qt::Key_F1:         return 0xFFBE;
    case Qt::Key_F2:         return 0xFFBF;
    case Qt::Key_F3:         return 0xFFC0;
    case Qt::Key_F4:         return 0xFFC1;
    case Qt::Key_F5:         return 0xFFC2;
    case Qt::Key_F6:         return 0xFFC3;
    case Qt::Key_F7:         return 0xFFC4;
    case Qt::Key_F8:         return 0xFFC5;
    case Qt::Key_F9:         return 0xFFC6;
    case Qt::Key_F10:        return 0xFFC7;
    case Qt::Key_F11:        return 0xFFC8;
    case Qt::Key_F12:        return 0xFFC9;
    default:
        if (key >= 0x20 && key <= 0xFF) return key;
        return key;
    }
}
void VncClient::sendKeyEvent(quint32 key, bool pressed)
{
    if (m_rfb) {
        qDebug() << "[VNC key]" << Qt::hex << key << "->" << qtKeyToKeysym(key) << pressed;
        SendKeyEvent(m_rfb, qtKeyToKeysym(key), pressed ? TRUE : FALSE);
    }
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