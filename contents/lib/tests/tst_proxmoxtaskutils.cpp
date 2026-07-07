#include <QtTest>

#include "proximoxtaskutils.h"

namespace {

QVariant taskResponse(const QString &status, const QString &exitStatus = {}) {
    return QVariantMap{
        {QStringLiteral("data"), QVariantMap{
            {QStringLiteral("status"), status},
            {QStringLiteral("exitstatus"), exitStatus},
        }},
    };
}

} // namespace

class ProxmoxTaskUtilsTest : public QObject {
    Q_OBJECT

private slots:
    void extractsUpid_data();
    void extractsUpid();
    void detectsRunningState_data();
    void detectsRunningState();
    void interpretsTaskExit_data();
    void interpretsTaskExit();
};

void ProxmoxTaskUtilsTest::extractsUpid_data() {
    QTest::addColumn<QVariant>("response");
    QTest::addColumn<QString>("expected");

    QTest::newRow("valid")
        << QVariant(QVariantMap{{QStringLiteral("data"), QStringLiteral(" UPID:pve-a:123 ")}})
        << QStringLiteral("UPID:pve-a:123");
    QTest::newRow("object-is-not-upid")
        << QVariant(QVariantMap{{QStringLiteral("data"), QVariantMap{{QStringLiteral("status"), QStringLiteral("running")}}}})
        << QString();
    QTest::newRow("missing") << QVariant(QVariantMap{}) << QString();
}

void ProxmoxTaskUtilsTest::extractsUpid() {
    QFETCH(QVariant, response);
    QFETCH(QString, expected);

    QCOMPARE(ProxmoxTaskUtils::extractUpid(response), expected);
}

void ProxmoxTaskUtilsTest::detectsRunningState_data() {
    QTest::addColumn<QVariant>("response");
    QTest::addColumn<bool>("expected");

    QTest::newRow("running") << taskResponse(QStringLiteral("running")) << true;
    QTest::newRow("case-and-whitespace") << taskResponse(QStringLiteral(" RUNNING ")) << true;
    QTest::newRow("stopped") << taskResponse(QStringLiteral("stopped")) << false;
    QTest::newRow("missing") << QVariant(QVariantMap{}) << false;
}

void ProxmoxTaskUtilsTest::detectsRunningState() {
    QFETCH(QVariant, response);
    QFETCH(bool, expected);

    QCOMPARE(ProxmoxTaskUtils::isRunning(response), expected);
}

void ProxmoxTaskUtilsTest::interpretsTaskExit_data() {
    QTest::addColumn<QVariant>("response");
    QTest::addColumn<QString>("expected");

    QTest::newRow("ok") << taskResponse(QStringLiteral("stopped"), QStringLiteral("OK")) << QString();
    QTest::newRow("task-ok") << taskResponse(QStringLiteral("stopped"), QStringLiteral("task ok")) << QString();
    QTest::newRow("warnings-are-success")
        << taskResponse(QStringLiteral("stopped"), QStringLiteral("TASK WARNINGS: 1")) << QString();
    QTest::newRow("explicit-failure")
        << taskResponse(QStringLiteral("stopped"), QStringLiteral("unable to acquire lock"))
        << QStringLiteral("unable to acquire lock");
    QTest::newRow("stopped-without-exit-status")
        << taskResponse(QStringLiteral("stopped"))
        << QStringLiteral("Task stopped without success");
    QTest::newRow("running-has-no-exit") << taskResponse(QStringLiteral("running")) << QString();
    QTest::newRow("missing") << QVariant(QVariantMap{}) << QString();
}

void ProxmoxTaskUtilsTest::interpretsTaskExit() {
    QFETCH(QVariant, response);
    QFETCH(QString, expected);

    QCOMPARE(ProxmoxTaskUtils::exitMessage(response), expected);
}

QTEST_APPLESS_MAIN(ProxmoxTaskUtilsTest)

#include "tst_proximoxtaskutils.moc"
