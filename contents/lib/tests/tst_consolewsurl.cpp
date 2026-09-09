#include <QtTest>

#include "proxmoxdatautils.h"

#include <QUrlQuery>

using ProxmoxDataUtils::buildConsoleWebSocketUrl;

namespace {

constexpr int kApiPort   = 8006;
constexpr int kConsolePort = 5900;

const QString kHost = QStringLiteral("proxmox.example");

QUrl guestUrl(const QString &node = QStringLiteral("pve-a"),
              const QString &kind = QStringLiteral("qemu"),
              int vmid = 101,
              const QByteArray &ticket = QByteArrayLiteral("PVEVNC:plain")) {
    return buildConsoleWebSocketUrl(kHost, kApiPort, node, kind, vmid,
                                    kConsolePort, ticket);
}

QString ticketOf(const QUrl &url, QUrl::ComponentFormattingOptions fmt) {
    return QUrlQuery(url.query(QUrl::FullyEncoded))
        .queryItemValue(QStringLiteral("vncticket"), fmt);
}

} // namespace

class ConsoleWsUrlTest : public QObject {
    Q_OBJECT

private slots:
    void schemeIsAlwaysWss();
    void buildsGuestPath();
    void buildsNodeShellPath();
    void carriesConsolePort();
    void percentEncodesBase64Ticket();
    void rejectsUnsafeSegments_data();
    void rejectsUnsafeSegments();
    void rejectsEmptyHost();
};

// The whole point of the helper: no caller and no setting may produce a
// cleartext ws:// console. ignoreSsl governs peer verification elsewhere and
// must never reach the scheme.
void ConsoleWsUrlTest::schemeIsAlwaysWss() {
    QCOMPARE(guestUrl().scheme(), QStringLiteral("wss"));
    QCOMPARE(buildConsoleWebSocketUrl(kHost, kApiPort, QStringLiteral("pve-a"),
                                      QString(), 0, kConsolePort,
                                      QByteArrayLiteral("t")).scheme(),
             QStringLiteral("wss"));
}

void ConsoleWsUrlTest::buildsGuestPath() {
    const QUrl url = guestUrl(QStringLiteral("pve-a"), QStringLiteral("lxc"), 204);
    QVERIFY(url.isValid());
    QCOMPARE(url.host(), kHost);
    QCOMPARE(url.port(), kApiPort);
    QCOMPARE(url.path(), QStringLiteral("/api2/json/nodes/pve-a/lxc/204/vncwebsocket"));
}

// vmid=0 is the node-shell sentinel, signalled by an empty kind. The vmid
// must not leak into the path.
void ConsoleWsUrlTest::buildsNodeShellPath() {
    const QUrl url = buildConsoleWebSocketUrl(kHost, kApiPort,
                                              QStringLiteral("pve-b"), QString(),
                                              0, kConsolePort,
                                              QByteArrayLiteral("t"));
    QVERIFY(url.isValid());
    QCOMPARE(url.path(), QStringLiteral("/api2/json/nodes/pve-b/vncwebsocket"));
}

void ConsoleWsUrlTest::carriesConsolePort() {
    const QUrlQuery query(guestUrl().query(QUrl::FullyEncoded));
    QCOMPARE(query.queryItemValue(QStringLiteral("port")),
             QString::number(kConsolePort));
}

// Proxmox decodes the query with a form-URL decoder, which reads a bare '+'
// as a space and corrupts the base64 ticket. Every reserved character has to
// arrive percent-encoded.
void ConsoleWsUrlTest::percentEncodesBase64Ticket() {
    const QByteArray ticket = QByteArrayLiteral("PVEVNC:a+b/c=d==");
    const QUrl url = guestUrl(QStringLiteral("pve-a"), QStringLiteral("qemu"),
                              101, ticket);
    QVERIFY(url.isValid());

    const QString encoded = ticketOf(url, QUrl::FullyEncoded);
    QVERIFY2(!encoded.contains(QLatin1Char('+')),
             "a raw '+' reaches Proxmox as a space and breaks the ticket");
    QVERIFY(encoded.contains(QStringLiteral("%2B")));
    QVERIFY(encoded.contains(QStringLiteral("%2F")));
    QVERIFY(encoded.contains(QStringLiteral("%3D")));

    QCOMPARE(ticketOf(url, QUrl::FullyDecoded).toUtf8(), ticket);
}

void ConsoleWsUrlTest::rejectsUnsafeSegments_data() {
    QTest::addColumn<QString>("node");
    QTest::addColumn<QString>("kind");

    const QString ok = QStringLiteral("qemu");
    QTest::newRow("node-slash")      << QStringLiteral("pve-a/lxc/1") << ok;
    QTest::newRow("node-parent")     << QStringLiteral("..")          << ok;
    QTest::newRow("node-self")       << QStringLiteral(".")           << ok;
    QTest::newRow("node-query")      << QStringLiteral("pve-a?x=1")   << ok;
    QTest::newRow("node-fragment")   << QStringLiteral("pve-a#frag")  << ok;
    QTest::newRow("node-percent")    << QStringLiteral("pve-a%2f")    << ok;
    QTest::newRow("node-space")      << QStringLiteral("pve a")       << ok;
    QTest::newRow("node-empty")      << QString()                     << ok;
    QTest::newRow("kind-slash")      << QStringLiteral("pve-a")
                                     << QStringLiteral("qemu/../lxc");
    QTest::newRow("kind-parent")     << QStringLiteral("pve-a")
                                     << QStringLiteral("..");
}

// A node or kind that reshapes the path is the only injection surface in
// either console transport. Reject rather than encode: a name needing
// encoding is a name we did not expect.
void ConsoleWsUrlTest::rejectsUnsafeSegments() {
    QFETCH(QString, node);
    QFETCH(QString, kind);
    QVERIFY(!buildConsoleWebSocketUrl(kHost, kApiPort, node, kind, 101,
                                      kConsolePort, QByteArrayLiteral("t"))
                 .isValid());
}

void ConsoleWsUrlTest::rejectsEmptyHost() {
    QVERIFY(!buildConsoleWebSocketUrl(QString(), kApiPort,
                                      QStringLiteral("pve-a"),
                                      QStringLiteral("qemu"), 101, kConsolePort,
                                      QByteArrayLiteral("t"))
                 .isValid());
}

QTEST_APPLESS_MAIN(ConsoleWsUrlTest)
#include "tst_consolewsurl.moc"
