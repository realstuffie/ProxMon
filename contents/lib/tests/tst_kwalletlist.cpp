// KWallet key listing in SecretStore.
//
// A private dbus-daemon hosts a fake org.kde.kwalletd6 so the test never touches
// the user's wallet. The fake answers the three calls SecretStore makes:
// networkWallet, open and entryList.
//
// PATH is emptied once the bus is up. If listing ever started an external
// program again, such as qdbus, it could not start and the test would see the
// wrong error text.
//
// DBUS_SESSION_BUS_ADDRESS is set before anything in the process touches
// QDBusConnection::sessionBus(), because QtDBus reads it once.

#include <QtTest>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVirtualObject>
#include <QProcess>
#include <QSignalSpy>

#include "secretstore.h"

namespace {
const QString KeyA = QStringLiteral("apiTokenSecret:root@pam!a@pve1:8006");
const QString PbsKey = QStringLiteral("pbsTokenSecret:backup@pbs!c@pbs1:8007");
}

class FakeKWallet : public QDBusVirtualObject {
    Q_OBJECT

public:
    // What entryList returns, and whether it answers with an error instead.
    QStringList entries;
    bool failEntryList = false;
    int entryListCalls = 0;

    QString introspect(const QString &) const override { return QString(); }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override {
        if (message.interface() != QLatin1String("org.kde.KWallet")) return false;

        if (message.member() == QLatin1String("networkWallet")) {
            QDBusMessage reply = message.createReply();
            reply << QStringLiteral("kdewallet");
            return connection.send(reply);
        }
        if (message.member() == QLatin1String("open")) {
            QDBusMessage reply = message.createReply();
            reply << 7;
            return connection.send(reply);
        }
        if (message.member() == QLatin1String("entryList")) {
            ++entryListCalls;
            if (failEntryList) {
                return connection.send(message.createErrorReply(QDBusError::Failed, QStringLiteral("wallet closed")));
            }
            QDBusMessage reply = message.createReply();
            reply << entries;
            return connection.send(reply);
        }
        return false;
    }
};

class KWalletListTest : public QObject {
    Q_OBJECT

private slots:
    void initTestCase();
    void cleanupTestCase();
    void init();
    void listsOnlyApiTokenKeys();
    void anEmptyWalletIsAnEmptyListAndStartsNoProcess();
    void aFailedCallReportsAnErrorAfterBothFolders();

private:
    QProcess m_bus;
    FakeKWallet m_wallet;
};

void KWalletListTest::initTestCase() {
    m_bus.start(QStringLiteral("dbus-daemon"),
                {QStringLiteral("--session"), QStringLiteral("--nofork"), QStringLiteral("--print-address")});
    // Some build images have no dbus-daemon. Skip there instead of failing, since
    // the build itself is fine; the test only needs a private bus to host a fake.
    if (!m_bus.waitForStarted(5000)) {
        QSKIP("dbus-daemon is not installed, so the fake KWallet cannot start");
    }
    QVERIFY(m_bus.waitForReadyRead(5000));
    const QByteArray address = m_bus.readLine().trimmed();
    QVERIFY(!address.isEmpty());
    qputenv("DBUS_SESSION_BUS_ADDRESS", address);

    QDBusConnection bus = QDBusConnection::sessionBus();
    QVERIFY2(bus.isConnected(), "could not reach the private bus");
    QVERIFY(bus.registerVirtualObject(QStringLiteral("/modules/kwalletd6"), &m_wallet,
                                      QDBusConnection::SubPath));
    QVERIFY(bus.registerService(QStringLiteral("org.kde.kwalletd6")));

    // The bus is running, so nothing needs PATH any more.
    qputenv("PATH", "/nonexistent");
}

void KWalletListTest::cleanupTestCase() {
    m_bus.terminate();
    m_bus.waitForFinished(3000);
}

void KWalletListTest::init() {
    m_wallet.entries.clear();
    m_wallet.failEntryList = false;
    m_wallet.entryListCalls = 0;
}

void KWalletListTest::listsOnlyApiTokenKeys() {
    m_wallet.entries = {KeyA, PbsKey, QStringLiteral("unrelated")};

    SecretStore store;
    QSignalSpy keys(&store, &SecretStore::keysReady);
    QSignalSpy errors(&store, &SecretStore::keyListError);

    store.listKWalletKeys();
    QVERIFY2(keys.wait(5000), "no key list arrived from KWallet");

    QCOMPARE(keys.first().first().toStringList(), QStringList{KeyA});
    QVERIFY(errors.isEmpty());
    QCOMPARE(m_wallet.entryListCalls, 1);
}

// A wallet with no ProxMon entries answers with a valid, empty list. That is an
// answer, so the listing ends there: one call, and the same "nothing found"
// report as for an empty Secret Service, not a failed read.
void KWalletListTest::anEmptyWalletIsAnEmptyListAndStartsNoProcess() {
    SecretStore store;
    QSignalSpy keys(&store, &SecretStore::keysReady);
    QSignalSpy errors(&store, &SecretStore::keyListError);

    store.listKWalletKeys();
    QVERIFY2(keys.wait(5000), "no key list arrived from KWallet");

    QVERIFY(keys.first().first().toStringList().isEmpty());
    QCOMPARE(m_wallet.entryListCalls, 1);
    QCOMPARE(errors.count(), 1);
    QCOMPARE(errors.first().first().toString(), QStringLiteral("Failed to read the keyring entry list"));
}

void KWalletListTest::aFailedCallReportsAnErrorAfterBothFolders() {
    m_wallet.failEntryList = true;

    SecretStore store;
    QSignalSpy keys(&store, &SecretStore::keysReady);
    QSignalSpy errors(&store, &SecretStore::keyListError);

    store.listKWalletKeys();
    QVERIFY2(keys.wait(5000), "no key list arrived from KWallet");

    QVERIFY(keys.first().first().toStringList().isEmpty());
    // The ProxMon folder and then the service name were both tried.
    QCOMPARE(m_wallet.entryListCalls, 2);
    QCOMPARE(errors.count(), 1);
    QCOMPARE(errors.first().first().toString(), QStringLiteral("Failed to read KWallet entry list"));
}

QTEST_MAIN(KWalletListTest)
#include "tst_kwalletlist.moc"
