// Timeout classification in ProxmoxClient::requestFor.
//
// A request the transfer timeout aborts must surface as a "Host unreachable"
// error. Which QNetworkReply code Qt reports for that differs by version
// (OperationCanceledError in older Qt 6, TimeoutError in newer), and the
// first one used to be dropped as if the caller had cancelled it, leaving the
// panel with no error and no auto-retry.
//
// The other half: a cancel the caller makes itself must stay silent.
//
// The server completes the TLS handshake and then never answers, so the
// client's 5s low-latency transfer timeout is what ends the request.

#include <QtTest>
#include <QProcess>
#include <QSignalSpy>
#include <QSslConfiguration>
#include <QSslKey>
#include <QSslServer>
#include <QSslSocket>
#include <QTemporaryDir>

#include "proxmoxclient.h"
#include "proxmoxconsts.h"

class SilentServer : public QSslServer {
    Q_OBJECT

public:
    explicit SilentServer(QObject *parent = nullptr) : QSslServer(parent) {
        // Accept and hold the socket open without ever writing a response.
        connect(this, &QTcpServer::pendingConnectionAvailable, this, [this]() {
            nextPendingConnection();
        });
    }
};

class HostUnreachableTest : public QObject {
    Q_OBJECT

private slots:
    void initTestCase();
    void transferTimeoutIsReportedAsHostUnreachable();
    void callerCancelStaysSilent();

private:
    void requestNodes(ProxmoxClient &client, quint16 port);

    QTemporaryDir m_certDir;
    QSslConfiguration m_serverSsl;
};

void HostUnreachableTest::initTestCase() {
    QVERIFY2(QSslSocket::supportsSsl(), "Qt was built without TLS support");
    QVERIFY(m_certDir.isValid());

    const QString keyPath = m_certDir.filePath(QStringLiteral("key.pem"));
    const QString certPath = m_certDir.filePath(QStringLiteral("cert.pem"));

    // Generated per run rather than checked in, so the fixture cannot expire.
    QProcess openssl;
    openssl.start(QStringLiteral("openssl"),
                  {QStringLiteral("req"), QStringLiteral("-x509"), QStringLiteral("-newkey"),
                   QStringLiteral("rsa:2048"), QStringLiteral("-nodes"),
                   QStringLiteral("-keyout"), keyPath,
                   QStringLiteral("-out"), certPath,
                   QStringLiteral("-days"), QStringLiteral("1"),
                   QStringLiteral("-subj"), QStringLiteral("/CN=127.0.0.1")});
    QVERIFY2(openssl.waitForStarted(5000), "openssl is required to generate the test certificate");
    QVERIFY2(openssl.waitForFinished(20000) && openssl.exitCode() == 0,
             "openssl failed to generate the test certificate");

    QFile keyFile(keyPath);
    QVERIFY(keyFile.open(QIODevice::ReadOnly));
    const QSslKey key(&keyFile, QSsl::Rsa);
    QVERIFY(!key.isNull());

    const QList<QSslCertificate> certs = QSslCertificate::fromPath(certPath);
    QVERIFY(!certs.isEmpty());

    m_serverSsl = QSslConfiguration::defaultConfiguration();
    m_serverSsl.setPrivateKey(key);
    m_serverSsl.setLocalCertificate(certs.first());
}

void HostUnreachableTest::requestNodes(ProxmoxClient &client, quint16 port) {
    // Picks the 5s transfer timeout instead of the 10s default.
    client.setLowLatency(true);
    client.requestNodesFor(QString(), QStringLiteral("127.0.0.1"), port,
                           QStringLiteral("root@pam!test"), QStringLiteral("secret"),
                           /*ignoreSslErrors=*/true, QByteArray(), QString(), /*seq=*/1);
}

void HostUnreachableTest::transferTimeoutIsReportedAsHostUnreachable() {
    SilentServer server;
    server.setSslConfiguration(m_serverSsl);
    QVERIFY2(server.listen(QHostAddress::LocalHost), qPrintable(server.errorString()));

    ProxmoxClient client;
    QSignalSpy errors(&client, &ProxmoxClient::error);
    requestNodes(client, server.serverPort());

    QVERIFY2(errors.wait(9000), "the timed-out request was dropped without an error");
    const QList<QVariant> args = errors.takeFirst();
    QCOMPARE(args.at(0).toInt(), 1);
    QCOMPARE(args.at(1).toString(), ProxmoxConst::Kind::Nodes);
    const QString message = args.at(3).toString();
    QVERIFY2(message.startsWith(ProxmoxConst::ErrorText::HostUnreachable), qPrintable(message));
    QVERIFY2(message.contains(QStringLiteral("timed out")), qPrintable(message));
}

void HostUnreachableTest::callerCancelStaysSilent() {
    SilentServer server;
    server.setSslConfiguration(m_serverSsl);
    QVERIFY2(server.listen(QHostAddress::LocalHost), qPrintable(server.errorString()));

    ProxmoxClient client;
    QSignalSpy errors(&client, &ProxmoxClient::error);
    requestNodes(client, server.serverPort());

    QTest::qWait(300);
    client.cancelRefreshRequests();
    QTest::qWait(500);
    QVERIFY2(errors.isEmpty(), "a cancel the caller made was reported as an error");
}

QTEST_MAIN(HostUnreachableTest)
#include "tst_hostunreachable.moc"
