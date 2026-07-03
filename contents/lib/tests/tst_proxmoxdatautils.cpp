#include <QtTest>

#include "proxmoxdatautils.h"

class ProxmoxDataUtilsTest : public QObject {
    Q_OBJECT

private slots:
    void multiHostJsonRejectsMalformedInput();
    void multiHostJsonAppliesLimitAndEnabledDefault();
    void endpointQueueFiltersAndNormalizesConfiguration();
    void responseRowsPreserveNestedDataAndAddContext();
    void responseRowsHandleMissingData();
    void endpointBucketsMergeAndSort();
};

void ProxmoxDataUtilsTest::multiHostJsonRejectsMalformedInput() {
    QVERIFY(ProxmoxDataUtils::parseMultiHostsJson(QStringLiteral("not-json")).isEmpty());
    QVERIFY(ProxmoxDataUtils::parseMultiHostsJson(QStringLiteral("{}" )).isEmpty());
    QVERIFY(ProxmoxDataUtils::parseMultiHostsJson(QStringLiteral("[]"), 0).isEmpty());
}

void ProxmoxDataUtilsTest::multiHostJsonAppliesLimitAndEnabledDefault() {
    const QString json = QStringLiteral(R"json([
        {"host":"one"},
        {"host":"two","enabled":false},
        {"host":"three"},
        {"host":"four"},
        {"host":"five"},
        {"host":"six"}
    ])json");

    const QVariantList entries = ProxmoxDataUtils::parseMultiHostsJson(json);

    QCOMPARE(entries.size(), 5);
    QVERIFY(entries.at(0).toMap().value(QStringLiteral("enabled")).toBool());
    QVERIFY(!entries.at(1).toMap().value(QStringLiteral("enabled")).toBool());
    QCOMPARE(entries.at(4).toMap().value(QStringLiteral("host")).toString(), QStringLiteral("five"));
}

void ProxmoxDataUtilsTest::endpointQueueFiltersAndNormalizesConfiguration() {
    const QString json = QStringLiteral(R"json([
        {
            "name":" Primary ",
            "host":" PVE-A.EXAMPLE ",
            "port":0,
            "tokenId":" root@pam!one ",
            "trustedCertPem":"CERT-A",
            "trustedCertPath":"/certs/a.pem",
            "pbsEnabled":true,
            "pbsHost":" backup.example ",
            "pbsPort":0,
            "pbsTokenId":" backup@pbs!one ",
            "pbsTrustedCertPem":"PBS-CERT-A",
            "pbsTrustedCertPath":"/certs/pbs-a.pem",
            "pbsBackupWarningDays":0,
            "pbsBackupStaleDays":-2
        },
        {
            "enabled":false,
            "host":"disabled.example",
            "tokenId":"root@pam!disabled"
        },
        {
            "host":"missing-token.example"
        },
        {
            "host":"pve-b.example",
            "port":8443,
            "tokenId":"root@pam!two",
            "ignoreSsl":false,
            "pbsIgnoreSsl":true,
            "pbsBackupWarningDays":10,
            "pbsBackupStaleDays":20
        }
    ])json");

    const QVariantList parsed = ProxmoxDataUtils::parseMultiHostsJson(json);
    QCOMPARE(parsed.at(0).toMap().value(QStringLiteral("pbsTrustedCertPem")).toString(),
             QStringLiteral("PBS-CERT-A"));
    QCOMPARE(parsed.at(0).toMap().value(QStringLiteral("pbsTrustedCertPath")).toString(),
             QStringLiteral("/certs/pbs-a.pem"));
    const QVariantList queue = ProxmoxDataUtils::buildEndpointQueue(parsed, true);

    QCOMPARE(queue.size(), 2);

    const QVariantMap primary = queue.at(0).toMap();
    QCOMPARE(primary.value(QStringLiteral("label")).toString(), QStringLiteral("Primary"));
    QCOMPARE(primary.value(QStringLiteral("host")).toString(), QStringLiteral("PVE-A.EXAMPLE"));
    QCOMPARE(primary.value(QStringLiteral("port")).toInt(), 8006);
    QCOMPARE(primary.value(QStringLiteral("tokenId")).toString(), QStringLiteral("root@pam!one"));
    QCOMPARE(primary.value(QStringLiteral("sessionKey")).toString(),
             QStringLiteral("apiTokenSecret:root@pam!one@pve-a.example:8006"));
    QVERIFY(primary.value(QStringLiteral("ignoreSsl")).toBool());
    QCOMPARE(primary.value(QStringLiteral("trustedCertPem")).toString(), QStringLiteral("CERT-A"));
    QCOMPARE(primary.value(QStringLiteral("trustedCertPath")).toString(), QStringLiteral("/certs/a.pem"));
    QVERIFY(primary.value(QStringLiteral("pbsEnabled")).toBool());
    QCOMPARE(primary.value(QStringLiteral("pbsHost")).toString(), QStringLiteral("backup.example"));
    QCOMPARE(primary.value(QStringLiteral("pbsPort")).toInt(), 8007);
    QCOMPARE(primary.value(QStringLiteral("pbsTokenId")).toString(), QStringLiteral("backup@pbs!one"));
    QCOMPARE(primary.value(QStringLiteral("pbsBackupWarningDays")).toInt(), 1);
    QCOMPARE(primary.value(QStringLiteral("pbsBackupStaleDays")).toInt(), 1);

    const QVariantMap secondary = queue.at(1).toMap();
    QCOMPARE(secondary.value(QStringLiteral("port")).toInt(), 8443);
    QVERIFY(!secondary.value(QStringLiteral("ignoreSsl")).toBool());
    QVERIFY(secondary.value(QStringLiteral("pbsIgnoreSsl")).toBool());
    QCOMPARE(secondary.value(QStringLiteral("pbsBackupWarningDays")).toInt(), 10);
    QCOMPARE(secondary.value(QStringLiteral("pbsBackupStaleDays")).toInt(), 20);
}

void ProxmoxDataUtilsTest::responseRowsPreserveNestedDataAndAddContext() {
    const QVariantList disks{
        QVariantMap{{QStringLiteral("storage"), QStringLiteral("local-zfs")},
                    {QStringLiteral("size"), 34359738368LL}},
        QVariantMap{{QStringLiteral("storage"), QStringLiteral("pbs")},
                    {QStringLiteral("backup"), true}},
    };
    const QVariantMap response{
        {QStringLiteral("data"), QVariantList{
            QVariantMap{{QStringLiteral("vmid"), 101},
                        {QStringLiteral("name"), QStringLiteral("database")},
                        {QStringLiteral("status"), QStringLiteral("running")},
                        {QStringLiteral("disks"), disks}},
            QVariantMap{{QStringLiteral("vmid"), 102},
                        {QStringLiteral("name"), QStringLiteral("worker")},
                        {QStringLiteral("status"), QStringLiteral("stopped")}},
        }},
    };
    const QVariantMap context{
        {QStringLiteral("node"), QStringLiteral("pve-a")},
        {QStringLiteral("sessionKey"), QStringLiteral("endpoint-a")},
    };

    const QVariantList rows = ProxmoxDataUtils::responseRows(response, context);

    QCOMPARE(rows.size(), 2);
    const QVariantMap first = rows.at(0).toMap();
    QCOMPARE(first.value(QStringLiteral("vmid")).toInt(), 101);
    QCOMPARE(first.value(QStringLiteral("node")).toString(), QStringLiteral("pve-a"));
    QCOMPARE(first.value(QStringLiteral("sessionKey")).toString(), QStringLiteral("endpoint-a"));
    QCOMPARE(first.value(QStringLiteral("disks")).toList(), disks);
    QVERIFY(!response.value(QStringLiteral("data")).toList().at(0).toMap().contains(QStringLiteral("node")));
}

void ProxmoxDataUtilsTest::responseRowsHandleMissingData() {
    QVERIFY(ProxmoxDataUtils::responseRows(QVariantMap{}).isEmpty());
    QVERIFY(ProxmoxDataUtils::responseRows(QVariant()).isEmpty());
}

void ProxmoxDataUtilsTest::endpointBucketsMergeAndSort() {
    const QVariantList endpoints{
        QVariantMap{{QStringLiteral("sessionKey"), QStringLiteral("z")},
                    {QStringLiteral("host"), QStringLiteral("zeta.example")},
                    {QStringLiteral("port"), 8006}},
        QVariantMap{{QStringLiteral("sessionKey"), QStringLiteral("a")},
                    {QStringLiteral("label"), QStringLiteral("Alpha")},
                    {QStringLiteral("host"), QStringLiteral("alpha.example")},
                    {QStringLiteral("port"), 8443}},
    };
    const QVariantList alphaNodes{
        QVariantMap{{QStringLiteral("node"), QStringLiteral("pve-a")},
                    {QStringLiteral("status"), QStringLiteral("online")}},
    };
    const QVariantList alphaVms{
        QVariantMap{{QStringLiteral("vmid"), 101},
                    {QStringLiteral("node"), QStringLiteral("pve-a")}},
    };
    const QVariantMap buckets{
        {QStringLiteral("a"), QVariantMap{
            {QStringLiteral("error"), QString()},
            {QStringLiteral("offline"), false},
            {QStringLiteral("nodes"), alphaNodes},
            {QStringLiteral("vms"), alphaVms},
            {QStringLiteral("lxcs"), QVariantList{}},
        }},
        {QStringLiteral("z"), QVariantMap{
            {QStringLiteral("error"), QStringLiteral("timed out")},
            {QStringLiteral("offline"), true},
            {QStringLiteral("nodes"), QVariantList{}},
            {QStringLiteral("vms"), QVariantList{}},
            {QStringLiteral("lxcs"), QVariantList{}},
        }},
    };

    const QVariantList rows = ProxmoxDataUtils::mergeEndpointBuckets(endpoints, buckets);

    QCOMPARE(rows.size(), 2);
    const QVariantMap alpha = rows.at(0).toMap();
    QCOMPARE(alpha.value(QStringLiteral("sessionKey")).toString(), QStringLiteral("a"));
    QCOMPARE(alpha.value(QStringLiteral("port")).toInt(), 8443);
    QCOMPARE(alpha.value(QStringLiteral("nodes")).toList(), alphaNodes);
    QCOMPARE(alpha.value(QStringLiteral("vms")).toList(), alphaVms);

    const QVariantMap zeta = rows.at(1).toMap();
    QCOMPARE(zeta.value(QStringLiteral("sessionKey")).toString(), QStringLiteral("z"));
    QVERIFY(zeta.value(QStringLiteral("offline")).toBool());
    QCOMPARE(zeta.value(QStringLiteral("error")).toString(), QStringLiteral("timed out"));
}

QTEST_APPLESS_MAIN(ProxmoxDataUtilsTest)

#include "tst_proxmoxdatautils.moc"
