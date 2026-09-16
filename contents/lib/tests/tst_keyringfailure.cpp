#include <QtTest>
#include <QDBusConnection>

#include "proxmoxcontroller.h"

// Drives a real keychain read into a failure without touching the user's
// wallet: CMake runs this test with DBUS_SESSION_BUS_ADDRESS pointing at a
// socket that does not exist, so QtKeychain's kwallet6 backend reports
// "D-Bus is not running" and the controller takes its error path.
class KeyringFailureTest : public QObject {
    Q_OBJECT
private slots:
    void initTestCase();
    void failureIsLoggedAndNotRetriedOnEveryTick();
};

void KeyringFailureTest::initTestCase() {
    QVERIFY2(!QDBusConnection::sessionBus().isConnected(),
             "session bus must be unreachable; run through ctest, not directly");
}

void KeyringFailureTest::failureIsLoggedAndNotRetriedOnEveryTick() {
    ProxmoxController controller;
    QSignalSpy states(&controller, &ProxmoxController::secretStateChanged);

    const QRegularExpression keyringWarning(QStringLiteral("^ProxMon keyring: reading the API token secret failed: "));
    QTest::ignoreMessage(QtWarningMsg, keyringWarning);

    controller.setConnectionMode(QStringLiteral("single"));
    controller.setHost(QStringLiteral("pve.example"));
    controller.setTokenId(QStringLiteral("monitor@pve!widget"));
    controller.fetchData();
    QTRY_COMPARE(controller.secretState(), QStringLiteral("error"));

    // A refresh-timer tick while the retry is pending must not start a read.
    states.clear();
    controller.fetchData();
    QTest::qWait(200);
    QCOMPARE(states.count(), 0);
    QCOMPARE(controller.secretState(), QStringLiteral("error"));

    // A manual refresh retries at once. The same failure again is rate
    // limited, so it must not produce a second journal warning.
    QTest::failOnWarning(keyringWarning);
    controller.fetchData(true);
    QTRY_VERIFY(states.count() >= 2); // error -> loading -> error
    QTRY_COMPARE(controller.secretState(), QStringLiteral("error"));
}

QTEST_GUILESS_MAIN(KeyringFailureTest)
#include "tst_keyringfailure.moc"
