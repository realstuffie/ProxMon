// Regression test for the shared QNetworkAccessManager in ProxmoxClient.
//
// cancelPBS() once called m_nam.clearConnectionCache(). That manager is shared
// by the PVE and PBS paths, so the clear dropped the pooled sockets of both and
// closed whichever node request was in flight. That request then hung until its
// transfer timeout and failed as an HTTP 0.
//
// Only the first refresh after a plasmashell start could hit it, because the
// PBS cycle and the node refresh run on intervals of 1800s and 30s that
// coincide once. Later refreshes were unaffected, so the panel showed a
// fraction of the real guests until the next one and then corrected itself.
//
// The test reproduces the collision: hold a node reply open, run a PBS cycle
// against the same client, cancel that cycle while the node reply is still
// open, and require the node reply to arrive anyway.

#include <QtTest>
#include <QCoreApplication>
#include <QProcess>
#include <QSignalSpy>
#include <QSslConfiguration>
#include <QSslKey>
#include <QSslServer>
#include <QSslSocket>
#include <QSharedPointer>
#include <QTemporaryDir>
#include <QTimer>

#include "proxmoxclient.h"
#include "proxmoxconsts.h"

// Serves the handful of endpoints this test touches over TLS, and lets the
// container listing be held open so a cancel can land while it is in flight.
class FakePveServer : public QSslServer {
    Q_OBJECT

public:
    explicit FakePveServer(QObject *parent = nullptr) : QSslServer(parent) {
        connect(this, &QTcpServer::pendingConnectionAvailable, this, &FakePveServer::onConnection);
    }

    // How long the container listing is held before it answers. Long enough
    // that the PBS cancel below lands while the request is still open.
    int lxcDelayMs = 1200;

private slots:
    void onConnection() {
        auto *socket = qobject_cast<QSslSocket *>(nextPendingConnection());
        if (!socket) return;
        auto buffer = QSharedPointer<QByteArray>::create();
        connect(socket, &QIODevice::readyRead, this, [this, socket, buffer]() {
            // readyRead can split a request, so wait for the end of the headers
            // rather than assuming the first chunk holds the whole request line.
            buffer->append(socket->readAll());
            if (!buffer->contains("\r\n\r\n")) return;
            const QByteArray path =
                buffer->left(buffer->indexOf("\r\n")).split(' ').value(1);

            if (path.contains("/lxc")) {
                // The long pole of a refresh, and the request the old bug took.
                QTimer::singleShot(lxcDelayMs, socket, [socket]() {
                    if (socket->state() != QAbstractSocket::ConnectedState) return;
                    respond(socket, R"({"data":[{"vmid":101,"name":"ct-one","status":"running"}]})");
                });
                return;
            }
            if (path.contains("/admin/datastore")) {
                respond(socket, R"({"data":[{"store":"pbs"}]})");
                return;
            }
            respond(socket, R"({"data":[]})");
        });
    }

private:
    static void respond(QSslSocket *socket, const QByteArray &body) {
        socket->write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: "
                      + QByteArray::number(body.size()) + "\r\nConnection: close\r\n\r\n" + body);
        socket->flush();
        socket->disconnectFromHost();
    }
};

class TestCancelIsolation : public QObject {
    Q_OBJECT

private slots:
    void initTestCase();
    void pbsCancelLeavesNodeRequestAlive();
    void cleanupTestCase();

private:
    QTemporaryDir m_certDir;
    QSslConfiguration m_serverSsl;
};

void TestCancelIsolation::initTestCase() {
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

void TestCancelIsolation::pbsCancelLeavesNodeRequestAlive() {
    FakePveServer server;
    server.setSslConfiguration(m_serverSsl);
    QVERIFY2(server.listen(QHostAddress::LocalHost), qPrintable(server.errorString()));
    const quint16 port = server.serverPort();

    ProxmoxClient client;
    // Picks the 5s transfer timeout, so a socket the cancel closed would leave
    // the reply hanging well past the wait below instead of failing fast.
    client.setLowLatency(true);

    QSignalSpy replies(&client, &ProxmoxClient::reply);
    QSignalSpy errors(&client, &ProxmoxClient::error);

    const int seq = 1;
    client.requestLxcFor(QString(), QStringLiteral("127.0.0.1"), port,
                         QStringLiteral("root@pam!test"), QStringLiteral("secret"),
                         /*ignoreSslErrors=*/true, QByteArray(), QString(),
                         QStringLiteral("pve"), seq);

    // The PBS cycle the startup refresh used to collide with.
    client.fetchPBSDatastores(QStringLiteral("pbs"), QStringLiteral("127.0.0.1"), port,
                              QStringLiteral("root@pam!pbs"), QStringLiteral("secret"),
                              /*ignoreSslErrors=*/true, QByteArray(), QString());

    // Land the cancel while the container listing is still open. Before the
    // fix this cleared the whole manager's pool and took that request with it.
    QTest::qWait(300);
    QVERIFY2(replies.isEmpty(), "the container listing answered before the cancel could land");
    client.cancelPBS();

    QVERIFY2(replies.wait(4000),
             "the container listing never completed: cancelPBS() disturbed a request that was not its own");

    const QList<QVariant> args = replies.takeFirst();
    QCOMPARE(args.at(0).toInt(), seq);
    QCOMPARE(args.at(1).toString(), ProxmoxConst::Kind::Lxc);
    QCOMPARE(args.at(2).toString(), QStringLiteral("pve"));

    const QVariantList rows = args.at(3).toMap().value(QStringLiteral("data")).toList();
    QCOMPARE(rows.size(), 1);
    QCOMPARE(rows.first().toMap().value(QStringLiteral("vmid")).toInt(), 101);

    QVERIFY2(errors.isEmpty(), "the node request reported an error");
}

void TestCancelIsolation::cleanupTestCase() {}

QTEST_MAIN(TestCancelIsolation)
#include "tst_cancelisolation.moc"
