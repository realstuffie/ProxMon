#include <QtTest>

#include "proxmoxclient.h"
#include "proxmoxcontroller.h"

class PbsCorrelationTest : public QObject {
    Q_OBJECT
private slots:
    void duplicateVmidRequiresAnExactSource();
    void incompleteNamespaceListingDoesNotSelectFirstSource();
    void pveRefreshDuringPbsCycleKeepsPreviousResults();
};

namespace {
PBSSnapshot snapshot(const QString &ns, qint64 time, const QString &verify = QStringLiteral("ok")) {
    PBSSnapshot value;
    value.vmid = 100;
    value.backupType = QStringLiteral("vm");
    value.datastoreName = QStringLiteral("shared");
    value.backupNamespace = ns;
    value.backupTime = time;
    value.verifyState = verify;
    return value;
}

void receiveGuest(ProxmoxClient *client) {
    // Exercise the controller's normal reply and publication paths without
    // contacting PVE or reading credentials from the desktop wallet.
    emit client->reply(0, QStringLiteral("qemu"), QStringLiteral("node-a"),
                       QVariantMap{{"data", QVariantList{QVariantMap{{"vmid", 100}, {"status", "running"}}}}});
}
}

void PbsCorrelationTest::duplicateVmidRequiresAnExactSource() {
    ProxmoxController controller;
    controller.setPbsEnabled(true);
    controller.setPbsHost(QStringLiteral("pbs.example"));
    auto *client = controller.findChild<ProxmoxClient *>();
    QVERIFY(client);
    receiveGuest(client);
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    const auto a = snapshot("cluster-a", now - 86400, "failed");
    const auto b = snapshot("cluster-b", now);
    emit client->pbsSnapshotsReceived({}, "pbs.example", "shared", {a, b});

    auto row = controller.displayedVmData().first().toMap();
    QCOMPARE(row.value("backupStatus").toInt(), int(BackupStatus::Ambiguous));
    QCOMPARE(row.value("lastBackupTime").toLongLong(), 0);
    QVERIFY(row.value("verifyState").toString().isEmpty());

    controller.setPbsDatastore("shared");
    controller.setPbsNamespace("cluster-a");
    row = controller.displayedVmData().first().toMap();
    QCOMPARE(row.value("lastBackupTime").toLongLong(), a.backupTime);
    QCOMPARE(row.value("verifyState").toString(), QStringLiteral("failed"));
    QVERIFY(row.value("backupStatus").toInt() != int(BackupStatus::Ambiguous));

    controller.setPbsNamespace("cluster-b");
    QCOMPARE(controller.displayedVmData().first().toMap().value("lastBackupTime").toLongLong(), b.backupTime);
    controller.setPbsNamespace(""); // Root must not fall back to another namespace.
    row = controller.displayedVmData().first().toMap();
    QCOMPARE(row.value("backupStatus").toInt(), int(BackupStatus::Never));
    QCOMPARE(row.value("lastBackupTime").toLongLong(), 0);
    controller.setPbsNamespace("*");
    QCOMPARE(controller.displayedVmData().first().toMap().value("backupStatus").toInt(), int(BackupStatus::Ambiguous));
}

void PbsCorrelationTest::incompleteNamespaceListingDoesNotSelectFirstSource() {
    ProxmoxController controller;
    controller.setPbsEnabled(true);
    controller.setPbsHost("pbs.example");
    auto *client = controller.findChild<ProxmoxClient *>();
    QVERIFY(client);
    emit client->pbsNamespacesReceived("pbs.example", "shared", {"a", "b"});
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    emit client->pbsSnapshotsReceived({}, "pbs.example", "shared", {snapshot("a", now)});
    receiveGuest(client); // A PVE refresh finishes while PBS still has work.
    QVERIFY(controller.displayedVmData().first().toMap().value("lastBackupTime").toLongLong() == 0);
    emit client->pbsSnapshotsReceived({}, "pbs.example", "shared", {snapshot("b", now + 1)});
    QCOMPARE(controller.displayedVmData().first().toMap().value("backupStatus").toInt(), int(BackupStatus::Ambiguous));
}

void PbsCorrelationTest::pveRefreshDuringPbsCycleKeepsPreviousResults() {
    ProxmoxController controller;
    controller.setPbsEnabled(true);
    controller.setPbsHost("pbs.example");
    auto *client = controller.findChild<ProxmoxClient *>();
    QVERIFY(client);
    receiveGuest(client);
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    const auto first = snapshot("a", now - 3600);
    emit client->pbsSnapshotsReceived({}, "pbs.example", "shared", {first});
    QCOMPARE(controller.displayedVmData().first().toMap().value("lastBackupTime").toLongLong(), first.backupTime);

    // Next cycle: namespace listing done, snapshot listing still in flight.
    emit client->pbsNamespacesReceived("pbs.example", "shared", {"a"});
    receiveGuest(client); // Fresh PVE rows carry no backup fields.
    auto row = controller.displayedVmData().first().toMap();
    QCOMPARE(row.value("lastBackupTime").toLongLong(), first.backupTime);
    QVERIFY(row.value("backupStatus").toInt() != int(BackupStatus::Never));

    const auto second = snapshot("a", now);
    emit client->pbsSnapshotsReceived({}, "pbs.example", "shared", {second});
    QCOMPARE(controller.displayedVmData().first().toMap().value("lastBackupTime").toLongLong(), second.backupTime);
}

QTEST_GUILESS_MAIN(PbsCorrelationTest)
#include "tst_pbscorrelation.moc"
