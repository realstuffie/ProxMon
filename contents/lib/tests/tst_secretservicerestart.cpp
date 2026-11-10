// A Secret Service provider that quits and comes back must not leave reads
// failing.
//
// libsecret keeps one cached connection to the Secret Service for the whole
// process. When KeePassXC was closed and reopened, that connection still pointed
// at the dead instance, so every read failed until plasmashell restarted. This
// test replays that: a fake provider serves a read, it disappears from the
// private bus, a second provider takes the name, and the same SecretStore must
// read from the new one.
//
// The second provider rejects sessions it did not open, as KeePassXC does, so a
// read that reuses the old libsecret session fails instead of passing by luck.
//
// Own executable because libsecret's cached connection is process-wide and the
// other Secret Service test would already have created one.

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

#include <memory>

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
const QString Item = QStringLiteral("/org/freedesktop/secrets/collection/default/1");
const QString Key = QStringLiteral("apiTokenSecret:root@pam!a@pve1:8006");
const QString ServiceName = QStringLiteral("org.freedesktop.secrets");
}

// One running provider. The tag keeps its session paths apart from the other
// provider's, and only sessions it opened itself are accepted.
class FakeProvider : public QDBusVirtualObject {
    Q_OBJECT

public:
    FakeProvider(const QString &tag, const QByteArray &secret)
        : m_tag(tag), m_secret(secret) {}

    QString introspect(const QString &) const override { return QString(); }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override {
        const QString interface = message.interface();
        const QString member = message.member();

        if (interface == QLatin1String("org.freedesktop.Secret.Service")) {
            if (member == QLatin1String("OpenSession")) {
                if (message.arguments().value(0).toString() != QLatin1String("plain")) {
                    return connection.send(message.createErrorReply(
                        QDBusError::NotSupported, QStringLiteral("Use a plain test session")));
                }
                const QString session = QStringLiteral("/org/freedesktop/secrets/session/%1%2")
                                            .arg(m_tag).arg(++m_sessionCount);
                m_sessions << session;
                return connection.send(message.createReply({
                    QVariant::fromValue(QDBusVariant(QString())),
                    QVariant::fromValue(QDBusObjectPath(session))}));
            }
            if (member == QLatin1String("ReadAlias")) {
                QDBusMessage reply = message.createReply();
                reply << QVariant::fromValue(QDBusObjectPath(Collection));
                return connection.send(reply);
            }
            if (member == QLatin1String("SearchItems")) {
                QDBusMessage reply = message.createReply();
                reply << QVariant::fromValue(QList<QDBusObjectPath>{QDBusObjectPath(Item)})
                      << QVariant::fromValue(QList<QDBusObjectPath>{});
                return connection.send(reply);
            }
            if (member == QLatin1String("GetSecrets")) {
                const QString session = message.arguments().value(1).value<QDBusObjectPath>().path();
                if (!m_sessions.contains(session)) {
                    // What KeePassXC answers for a session from before its restart.
                    return connection.send(message.createErrorReply(
                        QStringLiteral("org.freedesktop.Secret.Error.NoSession"), QString()));
                }
                const TestSecret secret{QDBusObjectPath(session), {}, m_secret, QStringLiteral("text/plain")};
                return connection.send(message.createReply({QVariant::fromValue(
                    QMap<QDBusObjectPath, TestSecret>{{QDBusObjectPath(Item), secret}})}));
            }
        }
        if (interface == QLatin1String("org.freedesktop.DBus.Properties")) {
            if (member == QLatin1String("GetAll")) {
                return connection.send(message.createReply(QVariantList{QVariantMap{}}));
            }
            if (member == QLatin1String("Get") && message.arguments().value(1).toString() == QLatin1String("Locked")) {
                QDBusMessage reply = message.createReply();
                reply << QVariant::fromValue(QDBusVariant(false));
                return connection.send(reply);
            }
        }
        return false;
    }

private:
    QString m_tag;
    QByteArray m_secret;
    QStringList m_sessions;
    int m_sessionCount = 0;
};

class SecretServiceRestartTest : public QObject {
    Q_OBJECT

private slots:
    void initTestCase();
    void cleanupTestCase();
    void readsRecoverWhenTheProviderRestarts();

private:
    bool startProvider(const QString &connectionName, FakeProvider &provider);
    void stopProvider(const QString &connectionName);
    static QString readOnce(SecretStore &store);

    QProcess m_bus;
    QByteArray m_address;
};

void SecretServiceRestartTest::initTestCase() {
    if (!SecretStore::backendSelectionSupported()) {
        QSKIP("QtKeychain older than 0.16.0 cannot be pointed at the fake Secret Service");
    }
    m_bus.start(QStringLiteral("dbus-daemon"),
                {QStringLiteral("--session"), QStringLiteral("--nofork"), QStringLiteral("--print-address")});
    if (!m_bus.waitForStarted(5000)) {
        QSKIP("dbus-daemon is not installed, so the fake Secret Service cannot start");
    }
    QVERIFY(m_bus.waitForReadyRead(5000));
    m_address = m_bus.readLine().trimmed();
    QVERIFY(!m_address.isEmpty());
    // QtDBus reads this once, so it has to be set before the first sessionBus() use.
    qputenv("DBUS_SESSION_BUS_ADDRESS", m_address);

    qDBusRegisterMetaType<TestSecret>();
    qDBusRegisterMetaType<QMap<QDBusObjectPath, TestSecret>>();
    QVERIFY2(QDBusConnection::sessionBus().isConnected(), "could not reach the private bus");

    qunsetenv("QTKEYCHAIN_BACKEND");
    SecretStore::selectBackend(true);
    QVERIFY(SecretStore::usesSecretService());
}

void SecretServiceRestartTest::cleanupTestCase() {
    m_bus.terminate();
    m_bus.waitForFinished(3000);
}

// A provider lives on its own bus connection, so closing that connection makes
// its unique name vanish the way a quitting KeePassXC does.
bool SecretServiceRestartTest::startProvider(const QString &connectionName, FakeProvider &provider) {
    QDBusConnection connection = QDBusConnection::connectToBus(QString::fromLatin1(m_address), connectionName);
    const bool ok = connection.isConnected()
        && connection.registerVirtualObject(QStringLiteral("/org/freedesktop/secrets"), &provider,
                                            QDBusConnection::SubPath)
        && connection.registerService(ServiceName);
    if (!ok) {
        connection = QDBusConnection(QString());
        QDBusConnection::disconnectFromBus(connectionName);
    }
    return ok;
}

void SecretServiceRestartTest::stopProvider(const QString &connectionName) {
    QDBusConnection::disconnectFromBus(connectionName);
}

QString SecretServiceRestartTest::readOnce(SecretStore &store) {
    // The handlers can run after a timeout, so they share the result instead of
    // pointing at locals.
    struct State { bool done = false; QString result; };
    auto state = std::make_shared<State>();
    store.readSecret(Key,
                     [state](const QString &secret) { state->done = true; state->result = secret; },
                     [state](const QString &message) { state->done = true; state->result = QStringLiteral("error: ") + message; });
    if (!QTest::qWaitFor([state] { return state->done; }, 5000)) return QStringLiteral("error: timed out");
    return state->result;
}

void SecretServiceRestartTest::readsRecoverWhenTheProviderRestarts() {
    FakeProvider first(QStringLiteral("a"), QByteArray("token-a"));
    QVERIFY(startProvider(QStringLiteral("providerA"), first));

    SecretStore store;
    QCOMPARE(readOnce(store), QStringLiteral("token-a"));

    // KeePassXC quits and is started again: a new connection, a new unique name,
    // and none of the old sessions.
    stopProvider(QStringLiteral("providerA"));
    FakeProvider second(QStringLiteral("b"), QByteArray("token-b"));
    // The bus may not have noticed the old connection closing yet.
    QTRY_VERIFY_WITH_TIMEOUT(startProvider(QStringLiteral("providerB"), second), 5000);
    // Let the owner change reach the store before the next read.
    QTest::qWait(300);

    QCOMPARE(readOnce(store), QStringLiteral("token-b"));
    stopProvider(QStringLiteral("providerB"));
}

QTEST_MAIN(SecretServiceRestartTest)
#include "tst_secretservicerestart.moc"
