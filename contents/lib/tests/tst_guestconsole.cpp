#include <QtTest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSharedPointer>
#include <QSslKey>
#include <QSslServer>
#include <QSslSocket>
#include <QTemporaryDir>
#include <QUrlQuery>
#include <QWebSocket>
#include <QWebSocketServer>

#include "lxcterminal.h"
#include "proxmoxclient.h"

// Exercise actual HTTPS requests so console selection, TLS trust, request
// identity and termproxy parameters are checked together.
class ConsoleApiServer : public QSslServer {
public:
    QByteArray config = R"({"data":{"vga":"serial0","serial0":"socket"}})";
    QByteArray proxy = R"({"data":{"port":5900,"ticket":"test-ticket","user":"test@pam"}})";
    int configStatus = 200;
    QList<QByteArray> requests;

    ConsoleApiServer() {
        connect(this, &QTcpServer::pendingConnectionAvailable, this, [this]() {
            auto *socket = qobject_cast<QSslSocket *>(nextPendingConnection());
            if (!socket) return;
            auto buffer = QSharedPointer<QByteArray>::create();
            connect(socket, &QIODevice::readyRead, socket, [this, socket, buffer]() {
                buffer->append(socket->readAll());
                const int end = buffer->indexOf("\r\n\r\n");
                if (end < 0) return;
                int length = 0;
                for (const QByteArray &line : buffer->left(end).split('\n')) {
                    if (line.toLower().startsWith("content-length:")) {
                        length = line.mid(line.indexOf(':') + 1).trimmed().toInt();
                    }
                }
                if (buffer->size() < end + 4 + length) return;
                requests.append(*buffer);
                const bool isConfig = buffer->startsWith("GET ");
                const QByteArray body = isConfig ? config : proxy;
                const int status = isConfig ? configStatus : 200;
                socket->write("HTTP/1.1 " + QByteArray::number(status) + " Test\r\n"
                              "Content-Type: application/json\r\nConnection: close\r\nContent-Length: "
                              + QByteArray::number(body.size()) + "\r\n\r\n" + body);
                socket->disconnectFromHost();
            });
        });
    }
};

class GuestConsoleTest : public QObject {
    Q_OBJECT

private slots:
    void initTestCase();
    void selectsConsole_data();
    void selectsConsole();
    void rejectsInvalidResponse_data();
    void rejectsInvalidResponse();
    void serialTerminalConnectsToVm();

private:
    QTemporaryDir m_certDir;
    QSslConfiguration m_tls;
    QByteArray m_ca;
};

void GuestConsoleTest::initTestCase() {
    QVERIFY(QSslSocket::supportsSsl());
    QVERIFY(m_certDir.isValid());
    const QString keyPath = m_certDir.filePath(QStringLiteral("key.pem"));
    const QString certPath = m_certDir.filePath(QStringLiteral("cert.pem"));
    QProcess openssl;
    openssl.start(QStringLiteral("openssl"), {
        QStringLiteral("req"), QStringLiteral("-x509"), QStringLiteral("-newkey"),
        QStringLiteral("rsa:2048"), QStringLiteral("-nodes"),
        QStringLiteral("-keyout"), keyPath, QStringLiteral("-out"), certPath,
        QStringLiteral("-days"), QStringLiteral("1"),
        QStringLiteral("-subj"), QStringLiteral("/CN=127.0.0.1"),
        QStringLiteral("-addext"), QStringLiteral("subjectAltName=IP:127.0.0.1")});
    QVERIFY(openssl.waitForFinished(20000));
    QCOMPARE(openssl.exitCode(), 0);
    QFile keyFile(keyPath);
    QVERIFY(keyFile.open(QIODevice::ReadOnly));
    const QSslKey key(&keyFile, QSsl::Rsa);
    QVERIFY(!key.isNull());
    QFile certFile(certPath);
    QVERIFY(certFile.open(QIODevice::ReadOnly));
    m_ca = certFile.readAll();
    const auto certificates = QSslCertificate::fromData(m_ca);
    QVERIFY(!certificates.isEmpty());
    m_tls = QSslConfiguration::defaultConfiguration();
    m_tls.setPrivateKey(key);
    m_tls.setLocalCertificate(certificates.first());
    m_tls.setPeerVerifyMode(QSslSocket::VerifyNone);
}

void GuestConsoleTest::selectsConsole_data() {
    QTest::addColumn<QByteArray>("config");
    QTest::addColumn<QString>("serial");
    QTest::newRow("cloud-init-serial0")
        << QByteArray(R"({"data":{"vga":"serial0","serial0":"socket"}})") << QStringLiteral("serial0");
    QTest::newRow("serial2-property-format")
        << QByteArray(R"({"data":{"vga":"type=serial2,memory=16","serial2":"socket"}})") << QStringLiteral("serial2");
    QTest::newRow("serial3-reordered-options")
        << QByteArray(R"({"data":{"vga":"memory=16,type=serial3","serial3":"socket"}})") << QStringLiteral("serial3");
    QTest::newRow("graphical-with-debug-serial")
        << QByteArray(R"({"data":{"vga":"virtio","serial0":"socket"}})") << QString();
    QTest::newRow("default-display") << QByteArray(R"({"data":{}})") << QString();
}

void GuestConsoleTest::selectsConsole() {
    QFETCH(QByteArray, config);
    QFETCH(QString, serial);
    ConsoleApiServer server;
    server.config = config;
    server.setSslConfiguration(m_tls);
    QVERIFY(server.listen(QHostAddress::LocalHost));
    ProxmoxClient client;
    QSignalSpy terminal(&client, &ProxmoxClient::ttyProxyReady);
    QSignalSpy graphical(&client, &ProxmoxClient::vncProxyReady);
    QSignalSpy terminalErrors(&client, &ProxmoxClient::ttyProxyError);
    QSignalSpy graphicalErrors(&client, &ProxmoxClient::vncProxyError);
    client.requestGuestConsole(QStringLiteral("endpoint-b"), QStringLiteral("request-42"),
        QStringLiteral("127.0.0.1"), server.serverPort(), QStringLiteral("test@pam!monitor"),
        QStringLiteral("test-secret"), false, m_ca, QString(), QStringLiteral("pve-b"),
        QStringLiteral("qemu"), 100);
    QTRY_COMPARE(terminal.size() + graphical.size(), 1);
    QVERIFY(terminalErrors.isEmpty());
    QVERIFY(graphicalErrors.isEmpty());
    QCOMPARE(server.requests.size(), 2);
    QVERIFY(server.requests[0].startsWith("GET /api2/json/nodes/pve-b/qemu/100/config?current=1 "));
    const QByteArray operation = serial.isEmpty() ? "vncproxy" : "termproxy";
    QVERIFY(server.requests[1].startsWith("POST /api2/json/nodes/pve-b/qemu/100/" + operation + " "));
    for (const auto &request : server.requests) {
        QVERIFY(request.contains("Authorization: PVEAPIToken=test@pam!monitor=test-secret\r\n"));
    }
    const auto args = serial.isEmpty() ? graphical.first() : terminal.first();
    QCOMPARE(args[0].toString(), QStringLiteral("endpoint-b"));
    QCOMPARE(args[1].toString(), QStringLiteral("request-42"));
    if (!serial.isEmpty()) {
        QCOMPARE(graphical.size(), 0);
        QCOMPARE(args[3].toString(), QStringLiteral("pve-b"));
        QCOMPARE(args[4].toInt(), 100);
        QCOMPARE(args[9].toString(), QStringLiteral("qemu"));
        QVERIFY(server.requests[1].endsWith("serial=" + serial.toUtf8()));
    } else {
        QCOMPARE(terminal.size(), 0);
        QCOMPARE(args[4].toString(), QStringLiteral("qemu"));
        QCOMPARE(args[5].toInt(), 100);
    }
}

void GuestConsoleTest::rejectsInvalidResponse_data() {
    QTest::addColumn<QByteArray>("config");
    QTest::addColumn<int>("status");
    QTest::addColumn<QByteArray>("proxy");
    QTest::addColumn<int>("requestCount");
    const QByteArray valid = R"({"data":{"vga":"serial0","serial0":"socket"}})";
    QTest::newRow("config-permission-denied") << valid << 403 << QByteArray() << 1;
    QTest::newRow("invalid-config-json") << QByteArray("invalid") << 200 << QByteArray() << 1;
    QTest::newRow("missing-config-object") << QByteArray(R"({"data":[]})") << 200 << QByteArray() << 1;
    QTest::newRow("missing-serial-port")
        << QByteArray(R"({"data":{"vga":"serial0"}})") << 200 << QByteArray() << 1;
    QTest::newRow("host-device-serial")
        << QByteArray(R"({"data":{"vga":"serial0","serial0":"/dev/ttyS0"}})") << 200 << QByteArray() << 1;
    QTest::newRow("missing-proxy-user")
        << valid << 200 << QByteArray(R"({"data":{"port":5900,"ticket":"ticket"}})") << 2;
}

void GuestConsoleTest::rejectsInvalidResponse() {
    QFETCH(QByteArray, config);
    QFETCH(int, status);
    QFETCH(QByteArray, proxy);
    QFETCH(int, requestCount);
    ConsoleApiServer server;
    server.config = config;
    server.configStatus = status;
    server.proxy = proxy;
    server.setSslConfiguration(m_tls);
    QVERIFY(server.listen(QHostAddress::LocalHost));
    ProxmoxClient client;
    QSignalSpy terminal(&client, &ProxmoxClient::ttyProxyReady);
    QSignalSpy graphical(&client, &ProxmoxClient::vncProxyReady);
    QSignalSpy terminalErrors(&client, &ProxmoxClient::ttyProxyError);
    QSignalSpy graphicalErrors(&client, &ProxmoxClient::vncProxyError);
    client.requestGuestConsole(QStringLiteral("endpoint-b"), QStringLiteral("request-42"),
        QStringLiteral("127.0.0.1"), server.serverPort(), QStringLiteral("test@pam!monitor"),
        QStringLiteral("test-secret"), false, m_ca, QString(), QStringLiteral("pve-b"),
        QStringLiteral("qemu"), 100);
    QTRY_COMPARE(terminalErrors.size() + graphicalErrors.size(), 1);
    QVERIFY(terminal.isEmpty());
    QVERIFY(graphical.isEmpty());
    QCOMPARE(server.requests.size(), requestCount);
    const auto args = requestCount == 1 ? graphicalErrors.first() : terminalErrors.first();
    QCOMPARE(args[0].toString(), QStringLiteral("endpoint-b"));
    QCOMPARE(args[1].toString(), QStringLiteral("request-42"));
    const QString message = args[requestCount == 1 ? 5 : 4].toString();
    QVERIFY(!message.contains(QStringLiteral("test-secret")));
}

void GuestConsoleTest::serialTerminalConnectsToVm() {
    QWebSocketServer server(QStringLiteral("VM console"), QWebSocketServer::SecureMode);
    server.setSslConfiguration(m_tls);
    QVERIFY(server.listen(QHostAddress::LocalHost));
    QUrl receivedUrl;
    QByteArray receivedAuth;
    QString login;
    connect(&server, &QWebSocketServer::newConnection, this, [&]() {
        auto *socket = server.nextPendingConnection();
        receivedUrl = socket->requestUrl();
        receivedAuth = socket->request().rawHeader("Authorization");
        connect(socket, &QWebSocket::textMessageReceived, socket, [&, socket](const QString &message) {
            if (!login.isEmpty()) return;
            login = message;
            socket->sendBinaryMessage(QByteArrayLiteral("OK\nVM login: "));
        });
        connect(socket, &QWebSocket::disconnected, socket, &QObject::deleteLater);
    });
    LxcTerminal terminal;
    QSignalSpy errors(&terminal, &LxcTerminal::errorOccurred);
    QSignalSpy closed(&terminal, &LxcTerminal::closed);
    terminal.setAuthHeaderSecure(QByteArrayLiteral("PVEAPIToken=test@pam!monitor=test-secret"));
    terminal.setTicketSecure(QByteArrayLiteral("ticket+/="));
    terminal.open(QStringLiteral("127.0.0.1"), server.serverPort(), QStringLiteral("pve-b"),
        100, QStringLiteral("cloud-vm"), 5900, QStringLiteral("test@pam"), false,
        QString::fromUtf8(m_ca), QString(), QStringLiteral("qemu"));
    QTRY_COMPARE(terminal.state(), QStringLiteral("connected"));
    QVERIFY(errors.isEmpty());
    QCOMPARE(receivedUrl.path(), QStringLiteral("/api2/json/nodes/pve-b/qemu/100/vncwebsocket"));
    QCOMPARE(receivedAuth, QByteArrayLiteral("PVEAPIToken=test@pam!monitor=test-secret"));
    QCOMPARE(login, QStringLiteral("test@pam:ticket+/=\n"));
    terminal.closeWindow();
    QCOMPARE(closed.size(), 1);
    terminal.closeWindow();
    QCOMPARE(closed.size(), 1);
}

QTEST_MAIN(GuestConsoleTest)
#include "tst_guestconsole.moc"
