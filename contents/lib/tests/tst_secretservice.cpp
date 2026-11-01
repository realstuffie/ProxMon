// Secret Service key listing and provider detection in SecretStore.
//
// A private dbus-daemon hosts a fake org.freedesktop.secrets so the test never
// touches the user's keyring. The fake answers the two calls SecretStore makes:
// Service.SearchItems and Properties.Get for an item's Attributes, with the
// attribute layout QtKeychain's libsecret backend writes (user, server, type).
//
// DBUS_SESSION_BUS_ADDRESS is set before anything in the process touches
// QDBusConnection::sessionBus(), because QtDBus reads it once.

#include <QtTest>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusVariant>
#include <QDBusVirtualObject>
#include <QMap>
#include <QProcess>
#include <QSignalSpy>
#include <QTcpServer>

#include "proxmoxclient.h"
#include "proxmoxconsts.h"
#include "proxmoxcontroller.h"
#include "secretstore.h"

// The Secret Service wire format, with a plain session for this private bus.
struct TestSecret {
    QDBusObjectPath session;
    QByteArray parameters;
    QByteArray value;
    QString contentType;
};
Q_DECLARE_METATYPE(TestSecret)

QDBusArgument &operator<<(QDBusArgument &arg, const TestSecret &secret) {
    arg.beginStructure();
    arg << secret.session << secret.parameters << secret.value << secret.contentType;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, TestSecret &secret) {
    arg.beginStructure();
    arg >> secret.session >> secret.parameters >> secret.value >> secret.contentType;
    arg.endStructure();
    return arg;
}

namespace {
const QString Collection = QStringLiteral("/org/freedesktop/secrets/collection/default");
const QString Item1 = QStringLiteral("/org/freedesktop/secrets/collection/default/1");
const QString Item2 = QStringLiteral("/org/freedesktop/secrets/collection/default/2");
const QString Locked3 = QStringLiteral("/org/freedesktop/secrets/collection/default/3");

const QString KeyA = QStringLiteral("apiTokenSecret:root@pam!a@pve1:8006");
const QString KeyB = QStringLiteral("apiTokenSecret:root@pam!b@pve2:8006");
const QString PbsKey = QStringLiteral("pbsTokenSecret:backup@pbs!c@pbs1:8007");
}

class FakeSecretService : public QDBusVirtualObject {
    Q_OBJECT

public:
    QStringList searchedServers;
    // Whether the default collection reports itself locked.
    bool locked = false;
    int searchCalls = 0;
    bool serveSecret = false;
    int secretReads = 0;

    QString introspect(const QString &) const override { return QString(); }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override {
        if (message.interface() == QLatin1String("org.freedesktop.Secret.Service")
            && message.member() == QLatin1String("OpenSession")) {
            if (message.arguments().value(0).toString() != QLatin1String("plain")) {
                return connection.send(message.createErrorReply(
                    QDBusError::NotSupported, QStringLiteral("Use a plain test session")));
            }
            return connection.send(message.createReply({
                QVariant::fromValue(QDBusVariant(QString())),
                QVariant::fromValue(QDBusObjectPath(QStringLiteral("/org/freedesktop/secrets/session/test")))}));
        }
        if (message.interface() == QLatin1String("org.freedesktop.DBus.Properties")
            && message.member() == QLatin1String("GetAll")) {
            return connection.send(message.createReply(QVariantList{QVariantMap{}}));
        }
        if (message.interface() == QLatin1String("org.freedesktop.Secret.Service")
            && message.member() == QLatin1String("GetSecrets")) {
            ++secretReads;
            const TestSecret secret{message.arguments().value(1).value<QDBusObjectPath>(),
                                    {}, QByteArray("test-token"), QStringLiteral("text/plain")};
            return connection.send(message.createReply({QVariant::fromValue(
                QMap<QDBusObjectPath, TestSecret>{{QDBusObjectPath(Item1), secret}})}));
        }
        if (message.interface() == QLatin1String("org.freedesktop.Secret.Service")
            && message.member() == QLatin1String("ReadAlias")) {
            QDBusMessage reply = message.createReply();
            reply << QVariant::fromValue(QDBusObjectPath(Collection));
            return connection.send(reply);
        }
        if (message.interface() == QLatin1String("org.freedesktop.DBus.Properties")
            && message.member() == QLatin1String("Get")
            && message.arguments().value(1).toString() == QLatin1String("Locked")) {
            QDBusMessage reply = message.createReply();
            reply << QVariant::fromValue(QDBusVariant(locked));
            return connection.send(reply);
        }
        if (message.interface() == QLatin1String("org.freedesktop.Secret.Service")
            && message.member() == QLatin1String("SearchItems")) {
            ++searchCalls;
            const QDBusArgument arg = message.arguments().value(0).value<QDBusArgument>();
            const QMap<QString, QString> wanted = qdbus_cast<QMap<QString, QString>>(arg);
            searchedServers << wanted.value(QStringLiteral("server"));

            QDBusMessage reply = message.createReply();
            if (serveSecret) {
                reply << QVariant::fromValue(QList<QDBusObjectPath>{QDBusObjectPath(Item1)})
                      << QVariant::fromValue(QList<QDBusObjectPath>{});
                return connection.send(reply);
            }
            reply << QVariant::fromValue(QList<QDBusObjectPath>{QDBusObjectPath(Item1), QDBusObjectPath(Item2)})
                  << QVariant::fromValue(QList<QDBusObjectPath>{QDBusObjectPath(Locked3)});
            return connection.send(reply);
        }
        if (message.interface() == QLatin1String("org.freedesktop.DBus.Properties")
            && message.member() == QLatin1String("Get")) {
            const QString path = message.path();
            QString user;
            if (path == Item1) user = KeyA;
            else if (path == Item2) user = PbsKey;
            else if (path == Locked3) user = KeyB;
            QMap<QString, QString> attrs{
                {QStringLiteral("user"), user},
                {QStringLiteral("server"), QStringLiteral("ProxMon")},
                {QStringLiteral("type"), QStringLiteral("plaintext")},
            };
            QDBusMessage reply = message.createReply();
            reply << QVariant::fromValue(QDBusVariant(QVariant::fromValue(attrs)));
            return connection.send(reply);
        }
        return false;
    }
};

class SecretServiceTest : public QObject {
    Q_OBJECT

private slots:
    void initTestCase();
    void cleanupTestCase();
    void listsOnlyApiTokenKeysIncludingLockedItems();
    void providerIsTheProcessOwningTheName();
    void lockedKeyringFailsAReadWithoutPrompting();
    void unlockWakesAWatcherButLockingDoesNot();
    void collectionChangedWakesAWatcherOnlyOnceUnlocked();
    void refreshReadFailureRecoversAfterUnlock_data();
    void refreshReadFailureRecoversAfterUnlock();

private:
    QProcess m_bus;
    FakeSecretService m_service;
};

void SecretServiceTest::initTestCase() {
    if (!SecretStore::backendSelectionSupported()) {
        QSKIP("QtKeychain older than 0.16.0 cannot be pointed at the fake Secret Service");
    }
    m_bus.start(QStringLiteral("dbus-daemon"),
                {QStringLiteral("--session"), QStringLiteral("--nofork"), QStringLiteral("--print-address")});
    // Some build images have no dbus-daemon. Skip there instead of failing, since
    // the build itself is fine; the test only needs a private bus to host a fake.
    if (!m_bus.waitForStarted(5000)) {
        QSKIP("dbus-daemon is not installed, so the fake Secret Service cannot start");
    }
    QVERIFY(m_bus.waitForReadyRead(5000));
    const QByteArray address = m_bus.readLine().trimmed();
    QVERIFY(!address.isEmpty());
    qputenv("DBUS_SESSION_BUS_ADDRESS", address);

    qDBusRegisterMetaType<QMap<QString, QString>>();
    qDBusRegisterMetaType<TestSecret>();
    qDBusRegisterMetaType<QMap<QDBusObjectPath, TestSecret>>();
    QDBusConnection bus = QDBusConnection::sessionBus();
    QVERIFY2(bus.isConnected(), "could not reach the private bus");
    QVERIFY(bus.registerVirtualObject(QStringLiteral("/org/freedesktop/secrets"), &m_service,
                                      QDBusConnection::SubPath));
    QVERIFY(bus.registerService(QStringLiteral("org.freedesktop.secrets")));

    // Keychain jobs are not started here, so this still takes effect. An older
    // ProxMon leaks QTKEYCHAIN_BACKEND=kwallet6 into terminals; drop it so it
    // does not count as a user override.
    qunsetenv("QTKEYCHAIN_BACKEND");
    SecretStore::selectBackend(true);
    QVERIFY(SecretStore::usesSecretService());
}

void SecretServiceTest::cleanupTestCase() {
    m_bus.terminate();
    m_bus.waitForFinished(3000);
}

void SecretServiceTest::listsOnlyApiTokenKeysIncludingLockedItems() {
    SecretStore store;
    QSignalSpy keys(&store, &SecretStore::keysReady);
    QSignalSpy errors(&store, &SecretStore::keyListError);

    store.listKeys();
    QVERIFY2(keys.wait(5000), "no key list arrived from the Secret Service");

    const QStringList listed = keys.takeFirst().at(0).toStringList();
    // The PBS token entry is not a restorable endpoint, so the list drops it.
    QCOMPARE(listed, (QStringList{KeyA, KeyB}));
    QVERIFY(errors.isEmpty());
    QCOMPARE(m_service.searchedServers, QStringList{QStringLiteral("ProxMon")});
}

void SecretServiceTest::providerIsTheProcessOwningTheName() {
    // The fake runs inside this test, so the owner is this process. The name
    // is the kernel's comm string, which is not one of the known providers.
    const QString provider = SecretStore::secretServiceProvider();
    QVERIFY2(!provider.isEmpty(), "no provider found for org.freedesktop.secrets");
    QVERIFY(QCoreApplication::applicationName().isEmpty() || !provider.contains(QLatin1Char('/')));
}

// A background read must not turn into an unlock dialog. The fake has no
// GetSecret or Unlock, so a read that got past the check would hang or fail
// differently; instead it must end at once with a message naming the provider.
void SecretServiceTest::lockedKeyringFailsAReadWithoutPrompting() {
    m_service.locked = true;
    const int searchesBefore = m_service.searchCalls;

    SecretStore store;
    QStringList errors;
    bool readyCalled = false;
    store.readSecret(KeyA,
                     [&](const QString &) { readyCalled = true; },
                     [&](const QString &message) { errors << message; });

    QTRY_COMPARE_WITH_TIMEOUT(errors.size(), 1, 5000);
    QVERIFY(!readyCalled);
    QVERIFY2(errors.first().contains(QStringLiteral("is locked")), qPrintable(errors.first()));
    QVERIFY2(errors.first().contains(SecretStore::secretServiceProvider()), qPrintable(errors.first()));
    // The lookup that would have prompted never started.
    QCOMPARE(m_service.searchCalls, searchesBefore);
    m_service.locked = false;
}

void SecretServiceTest::unlockWakesAWatcherButLockingDoesNot() {
    SecretStore store;
    QSignalSpy opened(&store, &SecretStore::walletOpened);
    store.watchWalletOpened();

    auto emitLocked = [](bool locked) {
        QDBusMessage signal = QDBusMessage::createSignal(
            Collection, QStringLiteral("org.freedesktop.DBus.Properties"),
            QStringLiteral("PropertiesChanged"));
        signal << QStringLiteral("org.freedesktop.Secret.Collection")
               << QVariantMap{{QStringLiteral("Locked"), locked}}
               << QStringList();
        QDBusConnection::sessionBus().send(signal);
    };

    emitLocked(true);
    QTest::qWait(300);
    QCOMPARE(opened.count(), 0);

    emitLocked(false);
    QVERIFY2(opened.wait(5000), "unlocking did not wake the watcher");
    QCOMPARE(opened.count(), 1);
}

// KeePassXC announces a lock and an unlock the same way, with
// Service.CollectionChanged and no property change. The watcher has to look at
// the Locked flag, so a lock must not wake it and an unlock must.
void SecretServiceTest::collectionChangedWakesAWatcherOnlyOnceUnlocked() {
    SecretStore store;
    QSignalSpy opened(&store, &SecretStore::walletOpened);
    store.watchWalletOpened();

    auto emitChanged = []() {
        QDBusMessage signal = QDBusMessage::createSignal(
            QStringLiteral("/org/freedesktop/secrets"),
            QStringLiteral("org.freedesktop.Secret.Service"),
            QStringLiteral("CollectionChanged"));
        signal << QVariant::fromValue(QDBusObjectPath(Collection));
        QDBusConnection::sessionBus().send(signal);
    };

    m_service.locked = true;
    emitChanged();
    QTest::qWait(400);
    QCOMPARE(opened.count(), 0);

    m_service.locked = false;
    emitChanged();
    QVERIFY2(opened.wait(5000), "an unlock announced by CollectionChanged did not wake the watcher");
    QCOMPARE(opened.count(), 1);
}

void SecretServiceTest::refreshReadFailureRecoversAfterUnlock_data() {
    QTest::addColumn<bool>("multiHost");
    QTest::addColumn<bool>("children");
    QTest::newRow("single-nodes") << false << false;
    QTest::newRow("single-children") << false << true;
    QTest::newRow("multi-nodes") << true << false;
    QTest::newRow("multi-children") << true << true;
}

void SecretServiceTest::refreshReadFailureRecoversAfterUnlock() {
    QFETCH(bool, multiHost);
    QFETCH(bool, children);

    // Accept connections without answering TLS. Reaching this server proves
    // the recovered refresh obtained a token and dispatched an API request.
    QTcpServer server;
    QVERIFY(server.listen(QHostAddress::LocalHost));
    m_service.serveSecret = true;
    m_service.locked = true;

    ProxmoxController controller;
    controller.setAutoRetry(false); // Keyring recovery must work independently.
    if (multiHost) {
        controller.setConnectionMode(QStringLiteral("multiHost"));
        controller.setMultiHostsJson(QStringLiteral(
            "[{\"host\":\"127.0.0.1\",\"port\":%1,\"tokenId\":\"test@pve!monitor\"}]")
                .arg(server.serverPort()));
    } else {
        controller.setHost(QStringLiteral("127.0.0.1"));
        controller.setPort(server.serverPort());
        controller.setTokenId(QStringLiteral("test@pve!monitor"));
    }
    auto *client = controller.findChild<ProxmoxClient *>();
    QVERIFY(client);

    auto unlock = [this]() {
        m_service.locked = false;
        QDBusMessage signal = QDBusMessage::createSignal(
            QStringLiteral("/org/freedesktop/secrets"),
            QStringLiteral("org.freedesktop.Secret.Service"), QStringLiteral("CollectionChanged"));
        signal << QVariant::fromValue(QDBusObjectPath(Collection));
        QVERIFY(QDBusConnection::sessionBus().send(signal));
    };

    controller.resolveSecretsIfNeeded();
    QTRY_COMPARE(controller.secretState(), QStringLiteral("error"));
    unlock();
    QTRY_COMPARE(controller.secretState(), QStringLiteral("ready"));

    // The initial unlock/read worked, but the next scoped read fails. This
    // used to leave secretState at ready and never arm the unlock retry.
    m_service.locked = true;
    const QString sessionKey = multiHost
        ? controller.endpoints().first().toMap().value(QStringLiteral("sessionKey")).toString()
        : QString();
    // The initial unlock retires refresh 0, so a children reply belongs to 1.
    const int failedSeq = children ? 1 : 2;
    if (children) {
        const QVariantMap nodes{{QStringLiteral("data"), QVariantList{
            QVariantMap{{QStringLiteral("node"), QStringLiteral("pve")}}}}};
        if (multiHost) emit client->replyFor(failedSeq, sessionKey, ProxmoxConst::Kind::Nodes, {}, nodes);
        else emit client->reply(failedSeq, ProxmoxConst::Kind::Nodes, {}, nodes);
    } else {
        controller.fetchData();
    }
    QTRY_COMPARE(controller.secretState(), QStringLiteral("error"));
    QTRY_VERIFY(!controller.loading() && !controller.isRefreshing());
    if (!multiHost) QCOMPARE(controller.errorMessage(), QStringLiteral("credentials unavailable"));

    QSignalSpy states(&controller, &ProxmoxController::secretStateChanged);
    controller.fetchData(); // Background ticks must respect keyring backoff.
    QTest::qWait(100);
    QCOMPARE(states.count(), 0);

    // Mirror main.qml: a successful resolution starts a fresh refresh.
    connect(&controller, &ProxmoxController::secretStateChanged, &controller, [&controller]() {
        if (controller.secretState() == QLatin1String("ready")
            && !controller.loading() && !controller.isRefreshing()) controller.fetchData();
    });
    const int readsBefore = m_service.secretReads;
    unlock();
    QTRY_VERIFY(server.hasPendingConnections());
    QCOMPARE(controller.secretState(), QStringLiteral("ready"));
    QVERIFY(m_service.secretReads >= readsBefore + 2); // Resolution and fetch.
    QVERIFY(controller.errorMessage().isEmpty());

    // A callback from the failed refresh must not restore its old error.
    if (multiHost) emit client->errorFor(failedSeq, sessionKey, ProxmoxConst::Kind::Nodes, {}, QStringLiteral("stale error"));
    else emit client->error(failedSeq, ProxmoxConst::Kind::Nodes, {}, QStringLiteral("stale error"));
    QVERIFY(controller.errorMessage().isEmpty());
    controller.cancelRefresh();
    m_service.serveSecret = false;
}

QTEST_MAIN(SecretServiceTest)
#include "tst_secretservice.moc"
