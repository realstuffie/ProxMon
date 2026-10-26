// Backend choice in SecretStore and the settings probe.
//
// QtKeychain fixes its backend at the first keychain job, so SecretStore keeps
// the choice in process-wide state. Each test below builds on the one before,
// in the order they are declared.
//
// CMake runs this with an unreachable session bus, so no real keyring is touched
// and the probe sees no D-Bus services.

#include <QtTest>
#include <QDBusConnection>
#include <QSignalSpy>

#include "keyringprobe.h"
#include "secretstore.h"

// A QtKeychain older than 0.16.0 ignores QTKEYCHAIN_BACKEND, so the tests that
// pick a backend through it cannot pass there.
#define SKIP_WITHOUT_BACKEND_SELECTION() \
    if (!SecretStore::backendSelectionSupported()) QSKIP("QtKeychain older than 0.16.0 ignores QTKEYCHAIN_BACKEND")

class KeyringSelectTest : public QObject {
    Q_OBJECT

private slots:
    void initTestCase();
    void selectionIsOffWithAnOldQtKeychain();
    void toggleSelectsAndClearsTheSecretService();
    void aUserSetBackendWins();
    void probeReportsTheChoiceAndAMissingBus();
    void ourEnvIsReleasedAfterTheFirstJob();
    void choiceIsFrozenOnceAJobStarts();
};

void KeyringSelectTest::initTestCase() {
    QVERIFY2(!QDBusConnection::sessionBus().isConnected(),
             "session bus must be unreachable; run through ctest, not directly");
    // Plasma sessions that ran an older ProxMon leak QTKEYCHAIN_BACKEND=kwallet6
    // into terminals, so start from a clean environment.
    qunsetenv("QTKEYCHAIN_BACKEND");
}

// With a QtKeychain that cannot choose a backend, ProxMon must not claim it did.
void KeyringSelectTest::selectionIsOffWithAnOldQtKeychain() {
    if (SecretStore::backendSelectionSupported()) {
        QSKIP("this build's QtKeychain can choose a backend");
    }
    SecretStore::selectBackend(true);
    QVERIFY(qEnvironmentVariableIsEmpty("QTKEYCHAIN_BACKEND"));
    QVERIFY(!SecretStore::usesSecretService());

    // The variable would not be honoured, so it is neither used nor an override.
    qputenv("QTKEYCHAIN_BACKEND", "libsecret");
    QVERIFY(!SecretStore::usesSecretService());
    QVERIFY(SecretStore::envOverride().isEmpty());
    qunsetenv("QTKEYCHAIN_BACKEND");

    QCOMPARE(KeyringProbe().probe(true).value("backendSelectable").toBool(), false);
}

void KeyringSelectTest::toggleSelectsAndClearsTheSecretService() {
    SKIP_WITHOUT_BACKEND_SELECTION();
    QVERIFY(!SecretStore::usesSecretService());

    SecretStore::selectBackend(true);
    QVERIFY(SecretStore::usesSecretService());
    QCOMPARE(qgetenv("QTKEYCHAIN_BACKEND"), QByteArray("libsecret"));
    // A value ProxMon set itself is not an override.
    QVERIFY(SecretStore::envOverride().isEmpty());

    // Turning it off hands the choice back to QtKeychain's own detection.
    SecretStore::selectBackend(false);
    QVERIFY(!SecretStore::usesSecretService());
    QVERIFY(qEnvironmentVariableIsEmpty("QTKEYCHAIN_BACKEND"));
}

void KeyringSelectTest::aUserSetBackendWins() {
    SKIP_WITHOUT_BACKEND_SELECTION();
    qputenv("QTKEYCHAIN_BACKEND", "kwallet6");
    SecretStore::selectBackend(true);
    QCOMPARE(qgetenv("QTKEYCHAIN_BACKEND"), QByteArray("kwallet6"));
    QVERIFY(!SecretStore::usesSecretService());
    QCOMPARE(SecretStore::envOverride(), QStringLiteral("kwallet6"));
    QCOMPARE(KeyringProbe().probe(true).value("envOverride").toString(), QStringLiteral("kwallet6"));

    // Turning the toggle off must not remove a value the user set.
    SecretStore::selectBackend(false);
    QCOMPARE(qgetenv("QTKEYCHAIN_BACKEND"), QByteArray("kwallet6"));

    qputenv("QTKEYCHAIN_BACKEND", "libsecret");
    QVERIFY(SecretStore::usesSecretService());
    qputenv("QTKEYCHAIN_BACKEND", "kwallet6");
}

void KeyringSelectTest::probeReportsTheChoiceAndAMissingBus() {
    KeyringProbe probe;

    // KWallet is in use here, so wanting KeePassXC means a restart is needed.
    QVariantMap info = probe.probe(true);
    QCOMPARE(info.value("usingSecretService").toBool(), false);
    QCOMPARE(info.value("restartNeeded").toBool(), true);
    QCOMPARE(probe.probe(false).value("restartNeeded").toBool(), false);

    // With no bus there is nothing to find, and nothing may block.
    QCOMPARE(info.value("kwalletRunning").toBool(), false);
    QCOMPARE(info.value("kwalletActivatable").toBool(), false);
    QCOMPARE(info.value("secretServiceOwner").toString(), QString());
    QCOMPARE(info.value("secretServiceActivatable").toBool(), false);
    QVERIFY(info.contains("libsecretBuilt"));
    QCOMPARE(info.value("backendSelectable").toBool(), SecretStore::backendSelectionSupported());
    QCOMPARE(probe.backendSelectable(), SecretStore::backendSelectionSupported());
}

// The variable ProxMon sets only has to live until QtKeychain has read it at
// its first job. If it stayed, every program plasmashell starts afterwards
// would inherit it and it would override their own choice.
void KeyringSelectTest::ourEnvIsReleasedAfterTheFirstJob() {
    SKIP_WITHOUT_BACKEND_SELECTION();
    qunsetenv("QTKEYCHAIN_BACKEND");
    SecretStore::selectBackend(true);
    QCOMPARE(qgetenv("QTKEYCHAIN_BACKEND"), QByteArray("libsecret"));

    // The unreachable bus makes this job fail fast without touching a keyring.
    SecretStore store;
    QSignalSpy done(&store, &SecretStore::deleteFinished);
    store.setKey(QStringLiteral("apiTokenSecret:test"));
    store.deleteSecret();
    QVERIFY(done.wait(10000));

    QVERIFY2(qEnvironmentVariableIsEmpty("QTKEYCHAIN_BACKEND"), "the backend variable was left in the environment");
    // The choice itself is remembered even though the variable is gone.
    QVERIFY(SecretStore::usesSecretService());
    QVERIFY(SecretStore::envOverride().isEmpty());
}

void KeyringSelectTest::choiceIsFrozenOnceAJobStarts() {
    SKIP_WITHOUT_BACKEND_SELECTION();
    // A job has started, so neither direction can change the backend any more.
    SecretStore::selectBackend(false);
    QVERIFY(SecretStore::usesSecretService());
    SecretStore::selectBackend(true);
    QVERIFY(qEnvironmentVariableIsEmpty("QTKEYCHAIN_BACKEND"));
    QVERIFY(SecretStore::usesSecretService());
}

QTEST_MAIN(KeyringSelectTest)
#include "tst_keyringselect.moc"
