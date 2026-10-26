#include <QtTest>
#include <QTimer>

#include "proxmoxcontroller.h"

// When a PBS cycle runs. refreshPBSNow() logs one "refreshPBS mode=" line per
// cycle, so counting those lines counts cycles without touching a keyring:
// every cycle here ends early because PBS is disabled or unconfigured.
// CMake points the session bus at a socket that does not exist, as for
// keyringfailure, so even a stray keychain access cannot reach a real wallet.
class PbsRefreshTest : public QObject {
    Q_OBJECT
private slots:
    void pbsSettingChangeRefreshes_data();
    void pbsSettingChangeRefreshes();
    void settingsWithoutPbsEffectDoNotRefresh();
    void secretWriteRefreshes();
    void cycleWithoutHostDoesNotArmTimer();

private:
    static int cycles(const ProxmoxController &c) {
        int n = 0;
        for (const QVariant &line : c.debugLog()) {
            if (line.toString().contains(QStringLiteral("refreshPBS mode="))) ++n;
        }
        return n;
    }
    // The debounce is 500ms; wait long enough for it to fire, and a bit more.
    static void settle() { QTest::qWait(900); }
};

void PbsRefreshTest::pbsSettingChangeRefreshes_data() {
    QTest::addColumn<QString>("property");
    QTest::addColumn<QVariant>("value");
    QTest::newRow("enabled") << "pbsEnabled" << QVariant(true);
    QTest::newRow("host") << "pbsHost" << QVariant(QStringLiteral("pbs.example"));
    QTest::newRow("port") << "pbsPort" << QVariant(8443);
    QTest::newRow("tokenId") << "pbsTokenId" << QVariant(QStringLiteral("backup@pbs!widget"));
    QTest::newRow("datastore") << "pbsDatastore" << QVariant(QStringLiteral("store1"));
    QTest::newRow("namespace") << "pbsNamespace" << QVariant(QStringLiteral("prod"));
    QTest::newRow("ignoreSsl") << "pbsIgnoreSsl" << QVariant(true);
    QTest::newRow("refreshInterval") << "pbsRefreshInterval" << QVariant(900);
}

void PbsRefreshTest::pbsSettingChangeRefreshes() {
    QFETCH(QString, property);
    QFETCH(QVariant, value);

    ProxmoxController controller;
    controller.setDebugEnabled(true);
    QCOMPARE(cycles(controller), 0);

    QVERIFY(controller.setProperty(property.toUtf8().constData(), value));
    QTRY_COMPARE_WITH_TIMEOUT(cycles(controller), 1, 3000);

    // One edit is one cycle, not one per timer that happens to be armed.
    settle();
    QCOMPARE(cycles(controller), 1);
}

void PbsRefreshTest::settingsWithoutPbsEffectDoNotRefresh() {
    ProxmoxController controller;
    controller.setDebugEnabled(true);

    controller.setConnectionMode(QStringLiteral("single"));
    controller.setHost(QStringLiteral("pve.example"));
    controller.setPort(8007);
    controller.setTokenId(QStringLiteral("monitor@pve!widget"));
    controller.setIgnoreSsl(true);
    controller.setPbsBackupWarningDays(3);
    controller.setPbsBackupStaleDays(9);
    controller.setPbsExcludeTag(QStringLiteral("nobackup"));
    controller.setPbsExcludeVmids(QStringLiteral("100,101"));
    settle();
    QCOMPARE(cycles(controller), 0);
}

// The secret is read from the keyring by the PBS fetch, so storing a new one
// has to trigger it. The write fails here (no bus); the refresh still runs, so
// the failure reaches the user as the PBS error.
void PbsRefreshTest::secretWriteRefreshes() {
    ProxmoxController controller;
    controller.setDebugEnabled(true);

    controller.storeSinglePBSSecret(QStringLiteral("pbs.example"), 8007,
                                    QStringLiteral("backup@pbs!widget"), QStringLiteral("secret"));
    QTRY_COMPARE_WITH_TIMEOUT(cycles(controller), 1, 5000);
    settle();
    QCOMPARE(cycles(controller), 1);

    controller.storeMultiHostPBSSecret(QStringLiteral("pbs2.example"), 8007,
                                       QStringLiteral("backup@pbs!widget"), QStringLiteral("secret"));
    QTRY_COMPARE_WITH_TIMEOUT(cycles(controller), 2, 5000);
}

// A cycle that runs before the PVE host is known has nothing to fetch. It must
// not arm the PBS timer: startSecretRead() only kicks PBS while the timer is
// idle, so an armed one would hold the first real PBS fetch back an interval.
void PbsRefreshTest::cycleWithoutHostDoesNotArmTimer() {
    ProxmoxController controller;
    controller.setDebugEnabled(true);
    controller.setConnectionMode(QStringLiteral("single"));
    controller.setPbsRefreshInterval(4242);

    QTimer *pbsTimer = nullptr;
    for (QTimer *t : controller.findChildren<QTimer *>()) {
        if (t->interval() == 4242 * 1000) pbsTimer = t;
    }
    QVERIFY(pbsTimer);

    QTRY_COMPARE_WITH_TIMEOUT(cycles(controller), 1, 3000);
    QVERIFY(!pbsTimer->isActive());

    controller.setHost(QStringLiteral("pve.example"));
    controller.setPbsHost(QStringLiteral("pbs.example"));
    QTRY_COMPARE_WITH_TIMEOUT(cycles(controller), 2, 3000);
    QVERIFY(pbsTimer->isActive());
}

QTEST_GUILESS_MAIN(PbsRefreshTest)
#include "tst_pbsrefresh.moc"
