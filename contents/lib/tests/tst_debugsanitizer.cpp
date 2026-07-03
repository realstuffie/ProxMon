#include <QtTest>

#include "proxmoxcontroller.h"

class DebugSanitizerTest : public QObject {
    Q_OBJECT

private slots:
    void redactsSensitiveValues_data();
    void redactsSensitiveValues();
};

void DebugSanitizerTest::redactsSensitiveValues_data() {
    QTest::addColumn<QString>("input");
    QTest::addColumn<QString>("expected");

    QTest::newRow("configured-pve-host")
        << QStringLiteral("host=PVE.EXAMPLE port=8006")
        << QStringLiteral("host=REDACTED_HOST port=8006");
    QTest::newRow("configured-pbs-host")
        << QStringLiteral("pbs=backup.example")
        << QStringLiteral("pbs=REDACTED_PBS_HOST");
    QTest::newRow("configured-token-id")
        << QStringLiteral("token=root@pam!monitor")
        << QStringLiteral("token=REDACTED_TOKEN");
    QTest::newRow("session-secret")
        << QStringLiteral("session=apiTokenSecret:super-secret count=1")
        << QStringLiteral("session=apiTokenSecret:REDACTED count=1");
    QTest::newRow("pve-api-token")
        << QStringLiteral("auth=PVEAPIToken=other@pam!reader=uuid-secret next=true")
        << QStringLiteral("auth=PVEAPIToken=REDACTED next=true");
    QTest::newRow("pbs-api-token")
        << QStringLiteral("PBSAPIToken=backup@pbs!monitor:uuid-secret")
        << QStringLiteral("PBSAPIToken=REDACTED");
    QTest::newRow("authorization-header")
        << QStringLiteral("Authorization: Bearer very-secret-token")
        << QStringLiteral("Authorization: REDACTED");
    QTest::newRow("ticket")
        << QStringLiteral("ticket=PVEVNC:very-secret-ticket node=pve-a")
        << QStringLiteral("ticket=REDACTED node=pve-a");
    QTest::newRow("password-field")
        << QStringLiteral("user=admin password=hunter2 result=failed")
        << QStringLiteral("user=admin password=REDACTED result=failed");
    QTest::newRow("url-credentials")
        << QStringLiteral("url=https://admin:password@pve.internal:8006/api2/json")
        << QStringLiteral("url=https://REDACTED@pve.internal:8006/api2/json");
    QTest::newRow("user-realm")
        << QStringLiteral("user=someone@pam")
        << QStringLiteral("user=REDACTED@pam");
    QTest::newRow("non-sensitive-fields-stay-readable")
        << QStringLiteral("secretEmpty=true nodes=2 status=running")
        << QStringLiteral("secretEmpty=true nodes=2 status=running");
}

void DebugSanitizerTest::redactsSensitiveValues() {
    QFETCH(QString, input);
    QFETCH(QString, expected);

    ProxmoxController controller;
    controller.setHost(QStringLiteral("pve.example"));
    controller.setPbsHost(QStringLiteral("backup.example"));
    controller.setTokenId(QStringLiteral("root@pam!monitor"));

    QCOMPARE(controller.sanitizeDebugString(input), expected);
}

QTEST_APPLESS_MAIN(DebugSanitizerTest)

#include "tst_debugsanitizer.moc"
