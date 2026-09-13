#include <QtTest>
#include <QTcpServer>
#include <QTcpSocket>
#include <QtEndian>
#include <rfb/rfbclient.h>

#include "vncclient.h"

namespace {
void append16(QByteArray &bytes, quint16 value)
{
    char encoded[2];
    qToBigEndian(value, encoded);
    bytes.append(encoded, 2);
}

void append32(QByteArray &bytes, quint32 value)
{
    char encoded[4];
    qToBigEndian(value, encoded);
    bytes.append(encoded, 4);
}

QByteArray rectangle(const QSize &size, quint32 encoding)
{
    QByteArray bytes = QByteArray::fromHex("00000001"); // framebuffer update, one rectangle
    append16(bytes, 0);
    append16(bytes, 0);
    append16(bytes, size.width());
    append16(bytes, size.height());
    append32(bytes, encoding);
    return bytes;
}

// Minimal RFB 3.8 peer. Like QEMU, it prefers ExtendedDesktopSize when
// advertised and uses screen ID 0. A legacy-only peer requires DesktopSize.
class VncPeer : public QObject {
public:
    VncPeer()
    {
        connect(&server, &QTcpServer::newConnection, this, [this]() {
            socket = server.nextPendingConnection();
            connect(socket, &QTcpSocket::readyRead, this, [this]() { receive(); });
            socket->write("RFB 003.008\n");
        });
    }

    ~VncPeer() override
    {
        // Unblock the client's worker even when an assertion ends a test.
        if (socket) socket->abort();
    }

    void resize(const QSize &size)
    {
        const bool extended = preferExtended && encodings.contains(rfbEncodingExtDesktopSize);
        if (!extended && !encodings.contains(rfbEncodingNewFBSize)) return;
        QByteArray bytes = rectangle(size, extended ? rfbEncodingExtDesktopSize : rfbEncodingNewFBSize);
        if (extended) {
            bytes.append(QByteArray::fromHex("01000000")); // one screen
            append32(bytes, 0); // QEMU's valid screen ID
            append16(bytes, 0);
            append16(bytes, 0);
            append16(bytes, size.width());
            append16(bytes, size.height());
            append32(bytes, 0);
        }
        socket->write(bytes);
        sendFrame(size);
    }

    void sendFrame(const QSize &size)
    {
        QByteArray bytes = rectangle(size, rfbEncodingRaw);
        const quint32 pixel = (0x11u << quint8(pixelFormat.at(10)))
            | (0x22u << quint8(pixelFormat.at(11))) | (0x33u << quint8(pixelFormat.at(12)));
        char encoded[4];
        if (pixelFormat.at(2)) qToBigEndian(pixel, encoded);
        else qToLittleEndian(pixel, encoded);
        bytes.append(QByteArray(encoded, 4).repeated(size.width() * size.height()));
        socket->write(bytes);
    }

    QTcpServer server;
    QTcpSocket *socket = nullptr;
    QList<quint32> encodings;
    QList<int> messageTypes;
    bool preferExtended = true;
    bool rejectHandshake = false;
    int resizeRequests = 0;

private:
    void receive()
    {
        input += socket->readAll();
        for (;;) {
            if (phase == 0) {
                if (input.size() < 12) return;
                input.remove(0, 12);
                if (rejectHandshake) {
                    socket->abort();
                    return;
                }
                socket->write(QByteArray::fromHex("0101")); // one security type: None
                phase = 1;
            } else if (phase == 1) {
                if (input.isEmpty()) return;
                input.remove(0, 1);
                socket->write(QByteArray(4, '\0')); // security result
                phase = 2;
            } else if (phase == 2) {
                if (input.isEmpty()) return;
                input.remove(0, 1); // ClientInit
                QByteArray init;
                append16(init, 64);
                append16(init, 48);
                init += QByteArray::fromHex("2018000100ff00ff00ff100800000000");
                append32(init, 4);
                init += "test";
                socket->write(init);
                phase = 3;
            } else {
                if (input.isEmpty()) return;
                const auto type = quint8(input.at(0));
                int length = 0;
                switch (type) {
                case rfbSetPixelFormat: length = 20; break;
                case rfbSetEncodings:
                    if (input.size() < 4) return;
                    length = 4 + 4 * qFromBigEndian<quint16>(input.constData() + 2);
                    break;
                case rfbFramebufferUpdateRequest: length = 10; break;
                case rfbKeyEvent: length = 8; break;
                case rfbPointerEvent: length = 6; break;
                case rfbSetDesktopSize: ++resizeRequests; socket->abort(); return;
                default: socket->abort(); return;
                }
                if (input.size() < length) return;
                const QByteArray message = input.first(length);
                input.remove(0, length);
                messageTypes.append(type);
                if (type == rfbSetPixelFormat) {
                    pixelFormat = message.mid(4, 16);
                } else if (type == rfbSetEncodings) {
                    encodings.clear();
                    for (int offset = 4; offset < length; offset += 4)
                        encodings.append(qFromBigEndian<quint32>(message.constData() + offset));
                } else if (type == rfbFramebufferUpdateRequest && !sentFrame
                           && !encodings.isEmpty() && !pixelFormat.isEmpty()) {
                    sentFrame = true;
                    sendFrame(QSize(64, 48));
                }
            }
        }
    }

    QByteArray input;
    QByteArray pixelFormat;
    int phase = 0;
    bool sentFrame = false;
};
}

class VncClientTest : public QObject {
    Q_OBJECT
private slots:
    void serverResizeKeepsConnection_data();
    void serverResizeKeepsConnection();
    void negotiatesBeforeRequestingPixels();
    void handshakeFailureCanReconnect();
};

void VncClientTest::serverResizeKeepsConnection_data()
{
    QTest::addColumn<bool>("preferExtended");
    QTest::newRow("qemu-screen-zero") << true;
    QTest::newRow("legacy-desktop-size") << false;
}

void VncClientTest::serverResizeKeepsConnection()
{
    QFETCH(bool, preferExtended);
    VncClient client;
    VncPeer peer; // destroyed first to unblock any pending client read
    peer.preferExtended = preferExtended;
    QSignalSpy frames(&client, &VncClient::frameUpdated);
    QSignalSpy errors(&client, &VncClient::errorOccurred);
    QVERIFY(peer.server.listen(QHostAddress::LocalHost, 0));
    client.connectToVnc(QStringLiteral("127.0.0.1"), peer.server.serverPort());
    QTRY_COMPARE(client.state(), QStringLiteral("connected"));
    QTRY_VERIFY(!frames.isEmpty());

    for (const QSize &size : {QSize(1680, 732), QSize(32, 24), QSize(96, 72)}) {
        frames.clear();
        peer.resize(size);
        QTRY_VERIFY_WITH_TIMEOUT(client.frameWidth() == size.width() || !errors.isEmpty(), 3000);
        QCOMPARE(errors.size(), 0);
        QCOMPARE(QSize(client.frameWidth(), client.frameHeight()), size);
        QTRY_VERIFY(!frames.isEmpty());
        const auto frame = qvariant_cast<QImage>(frames.last().at(0));
        QCOMPARE(frame.size(), size);
        QCOMPARE(frame.pixel(0, 0), qRgb(0x11, 0x22, 0x33));
        QCOMPARE(frame.pixel(size.width() - 1, size.height() - 1), qRgb(0x11, 0x22, 0x33));
        QCOMPARE(client.state(), QStringLiteral("connected"));
    }
    QCOMPARE(peer.resizeRequests, 0);
}

void VncClientTest::negotiatesBeforeRequestingPixels()
{
    VncClient client;
    VncPeer peer;
    QVERIFY(peer.server.listen(QHostAddress::LocalHost, 0));
    client.connectToVnc(QStringLiteral("127.0.0.1"), peer.server.serverPort());
    QTRY_VERIFY(peer.messageTypes.contains(rfbFramebufferUpdateRequest));
    QCOMPARE(peer.messageTypes.first(), int(rfbSetPixelFormat));
    QVERIFY(peer.messageTypes.indexOf(rfbSetEncodings)
            < peer.messageTypes.indexOf(rfbFramebufferUpdateRequest));
}

void VncClientTest::handshakeFailureCanReconnect()
{
    VncClient client;
    VncPeer badPeer;
    badPeer.rejectHandshake = true;
    QVERIFY(badPeer.server.listen(QHostAddress::LocalHost, 0));
    client.connectToVnc(QStringLiteral("127.0.0.1"), badPeer.server.serverPort());
    QTRY_COMPARE(client.state(), QStringLiteral("error"));

    VncPeer goodPeer;
    QSignalSpy frames(&client, &VncClient::frameUpdated);
    QVERIFY(goodPeer.server.listen(QHostAddress::LocalHost, 0));
    client.connectToVnc(QStringLiteral("127.0.0.1"), goodPeer.server.serverPort());
    QTRY_COMPARE(client.state(), QStringLiteral("connected"));
    QTRY_VERIFY(!frames.isEmpty());
    QCOMPARE(QSize(client.frameWidth(), client.frameHeight()), QSize(64, 48));
}

QTEST_GUILESS_MAIN(VncClientTest)
#include "tst_vncclient.moc"
