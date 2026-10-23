// Auto-retry policy in ProxmoxController: the attempt cap, the one-pending
// debounce and the multi-host path.
//
// Failures are injected through the client's signals, as tst_pbscorrelation
// does, so no network or wallet is involved. The controller starts at refresh
// sequence 0, which is what the injected signals carry.
//
// cancelRefresh() stops the pending retry timer without touching the attempt
// count, so the tests call it between failures to get past the debounce
// without waiting for the backoff delay.

#include <QtTest>

#include "proxmoxclient.h"
#include "proxmoxconsts.h"
#include "proxmoxcontroller.h"

namespace {
const QString Unreachable = ProxmoxConst::ErrorText::HostUnreachable + QStringLiteral(": Operation timed out (HTTP 0)");
constexpr int Cap = ProxmoxConst::Defaults::MaxAutoRetryAttempts;

void failSingle(ProxmoxClient *client, const QString &message) {
    emit client->error(0, ProxmoxConst::Kind::Nodes, QString(), message);
}

void failMulti(ProxmoxClient *client, const QString &message) {
    emit client->errorFor(0, QStringLiteral("k1"), ProxmoxConst::Kind::Nodes, QString(), message);
}
}

class RetryPolicyTest : public QObject {
    Q_OBJECT

private slots:
    void singleHostStopsAtCap();
    void capMessageNamesUnreachableHost();
    void capMessageForOtherErrorsCountsAttempts();
    void serverGatewayTimeoutIsNotHostUnreachable();
    void secondFailureWhilePendingIsNotAnotherAttempt();
    void multiHostFailureSchedulesRetry();
    void multiHostStopsAtCap();
    void cleanMultiHostRefreshDoesNotRetry();
};

void RetryPolicyTest::singleHostStopsAtCap() {
    ProxmoxController controller;
    auto *client = controller.findChild<ProxmoxClient *>();
    QVERIFY(client);

    for (int i = 1; i <= Cap; ++i) {
        failSingle(client, Unreachable);
        QCOMPARE(controller.retryAttempt(), i);
        QVERIFY(controller.retryNextDelayMs() > 0);
        controller.cancelRefresh();
    }

    failSingle(client, Unreachable);
    QCOMPARE(controller.retryAttempt(), Cap);
    QCOMPARE(controller.retryNextDelayMs(), 0);
}

void RetryPolicyTest::capMessageNamesUnreachableHost() {
    ProxmoxController controller;
    auto *client = controller.findChild<ProxmoxClient *>();
    QVERIFY(client);
    for (int i = 0; i < Cap; ++i) {
        failSingle(client, Unreachable);
        controller.cancelRefresh();
    }
    failSingle(client, Unreachable);
    QVERIFY(controller.retryStatusText().startsWith(QStringLiteral("Host unreachable")));
    QVERIFY(controller.retryStatusText().contains(QStringLiteral("stopped")));
}

void RetryPolicyTest::capMessageForOtherErrorsCountsAttempts() {
    ProxmoxController controller;
    auto *client = controller.findChild<ProxmoxClient *>();
    QVERIFY(client);
    const QString other = QStringLiteral("Forbidden (HTTP 403)");
    for (int i = 0; i < Cap; ++i) {
        failSingle(client, other);
        controller.cancelRefresh();
    }
    failSingle(client, other);
    QVERIFY(!controller.retryStatusText().startsWith(QStringLiteral("Host unreachable")));
    QVERIFY(controller.retryStatusText().contains(QString::number(Cap)));
    QVERIFY(controller.retryStatusText().contains(QStringLiteral("stopped")));
}

// A proxy in front of Proxmox answering "Gateway Timeout" reached the host's
// network, so it must not be classed as unreachable just because the text
// mentions a timeout. Only the client's tag counts.
void RetryPolicyTest::serverGatewayTimeoutIsNotHostUnreachable() {
    ProxmoxController controller;
    auto *client = controller.findChild<ProxmoxClient *>();
    QVERIFY(client);
    const QString gateway = QStringLiteral("Error transferring https://pve:8006/api2/json/nodes - server replied: Gateway Timeout (HTTP 504)");
    for (int i = 0; i < Cap; ++i) {
        failSingle(client, gateway);
        controller.cancelRefresh();
    }
    failSingle(client, gateway);
    QVERIFY(!controller.retryStatusText().startsWith(QStringLiteral("Host unreachable")));
    QVERIFY(controller.retryStatusText().contains(QStringLiteral("stopped")));
}

void RetryPolicyTest::secondFailureWhilePendingIsNotAnotherAttempt() {
    ProxmoxController controller;
    auto *client = controller.findChild<ProxmoxClient *>();
    QVERIFY(client);

    failSingle(client, Unreachable);
    const int delay = controller.retryNextDelayMs();
    failSingle(client, Unreachable);
    failSingle(client, Unreachable);

    QCOMPARE(controller.retryAttempt(), 1);
    QCOMPARE(controller.retryNextDelayMs(), delay);
}

void RetryPolicyTest::multiHostFailureSchedulesRetry() {
    ProxmoxController controller;
    controller.setConnectionMode(QStringLiteral("multiHost"));
    auto *client = controller.findChild<ProxmoxClient *>();
    QVERIFY(client);

    failMulti(client, Unreachable);

    QCOMPARE(controller.retryAttempt(), 1);
    QVERIFY(controller.retryNextDelayMs() > 0);
    QVERIFY(controller.retryStatusText().startsWith(QStringLiteral("Retrying")));
}

void RetryPolicyTest::multiHostStopsAtCap() {
    ProxmoxController controller;
    controller.setConnectionMode(QStringLiteral("multiHost"));
    auto *client = controller.findChild<ProxmoxClient *>();
    QVERIFY(client);

    for (int i = 1; i <= Cap; ++i) {
        failMulti(client, Unreachable);
        QCOMPARE(controller.retryAttempt(), i);
        controller.cancelRefresh();
    }
    failMulti(client, Unreachable);
    QCOMPARE(controller.retryAttempt(), Cap);
    QCOMPARE(controller.retryNextDelayMs(), 0);
}

void RetryPolicyTest::cleanMultiHostRefreshDoesNotRetry() {
    ProxmoxController controller;
    controller.setConnectionMode(QStringLiteral("multiHost"));
    auto *client = controller.findChild<ProxmoxClient *>();
    QVERIFY(client);

    emit client->replyFor(0, QStringLiteral("k1"), ProxmoxConst::Kind::Nodes, QString(),
                          QVariantMap{{QStringLiteral("data"), QVariantList()}});

    QCOMPARE(controller.retryAttempt(), 0);
    QCOMPARE(controller.retryNextDelayMs(), 0);
    QVERIFY(controller.retryStatusText().isEmpty());
}

QTEST_MAIN(RetryPolicyTest)
#include "tst_retrypolicy.moc"
