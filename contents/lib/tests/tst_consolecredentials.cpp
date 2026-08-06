#include <QtTest>

#include "proxmoxclient.h"
#include "proxmoxcontroller.h"

class CredentialReceiver : public QObject {
    Q_OBJECT

public:
    int authCalls = 0;
    int ticketCalls = 0;
    QByteArray authHeader;
    QByteArray ticket;

public slots:
    void setAuthHeaderSecure(const QByteArray &value) {
        ++authCalls;
        authHeader = value;
    }

    void setTicketSecure(const QByteArray &value) {
        ++ticketCalls;
        ticket = value;
    }
};

class ConsoleCredentialsTest : public QObject {
    Q_OBJECT

private slots:
    void credentialsAreDeliveredOnce();
    void unconsumedCredentialsAreDiscarded();
    void unknownRequestDoesNothing();
};

void ConsoleCredentialsTest::credentialsAreDeliveredOnce() {
    ProxmoxController controller;
    ProxmoxClient *client = controller.findChild<ProxmoxClient *>();
    QVERIFY(client);

    const QString requestId = QStringLiteral("request-1");
    const QByteArray expectedAuth("PVEAPIToken=test@pam!monitor=secret");
    const QByteArray expectedTicket("PVE:console-ticket");
    CredentialReceiver first;
    CredentialReceiver secondary;

    connect(&controller, &ProxmoxController::lxcConsoleReady, this,
            [&controller, &first, &secondary, &requestId](const QString &,
                                                          const QString &readyRequestId,
                                                          const QString &,
                                                          int,
                                                          const QString &,
                                                          int,
                                                          const QString &,
                                                          int,
                                                          const QString &,
                                                          bool) {
        if (readyRequestId != requestId) return;
        controller.deliverConsoleAuth(readyRequestId, &first);
        controller.deliverConsoleTicket(readyRequestId, &first, &secondary);
    });

    client->nodeTermProxyReady(QString(),
                               requestId,
                               QStringLiteral("pve.example"),
                               QStringLiteral("pve-a"),
                               5900,
                               QString::fromUtf8(expectedTicket),
                               QStringLiteral("test@pam"),
                               expectedAuth);

    QCOMPARE(first.authCalls, 1);
    QCOMPARE(first.authHeader, expectedAuth);
    QCOMPARE(first.ticketCalls, 1);
    QCOMPARE(first.ticket, expectedTicket);
    QCOMPARE(secondary.ticketCalls, 1);
    QCOMPARE(secondary.ticket, expectedTicket);

    CredentialReceiver repeated;
    controller.deliverConsoleAuth(requestId, &repeated);
    controller.deliverConsoleTicket(requestId, &repeated);

    QCOMPARE(repeated.authCalls, 0);
    QCOMPARE(repeated.ticketCalls, 0);
}

void ConsoleCredentialsTest::unconsumedCredentialsAreDiscarded() {
    ProxmoxController controller;
    ProxmoxClient *client = controller.findChild<ProxmoxClient *>();
    QVERIFY(client);

    const QString requestId = QStringLiteral("unconsumed");
    client->nodeTermProxyReady(QString(),
                               requestId,
                               QStringLiteral("pve.example"),
                               QStringLiteral("pve-a"),
                               5900,
                               QStringLiteral("PVE:unused-ticket"),
                               QStringLiteral("test@pam"),
                               QByteArray("PVEAPIToken=test@pam!monitor=unused"));

    CredentialReceiver receiver;
    controller.deliverConsoleAuth(requestId, &receiver);
    controller.deliverConsoleTicket(requestId, &receiver);

    QCOMPARE(receiver.authCalls, 0);
    QCOMPARE(receiver.ticketCalls, 0);
}

void ConsoleCredentialsTest::unknownRequestDoesNothing() {
    ProxmoxController controller;
    CredentialReceiver receiver;

    controller.deliverConsoleAuth(QStringLiteral("missing"), &receiver);
    controller.deliverConsoleTicket(QStringLiteral("missing"), &receiver);

    QCOMPARE(receiver.authCalls, 0);
    QCOMPARE(receiver.ticketCalls, 0);
}

QTEST_APPLESS_MAIN(ConsoleCredentialsTest)

#include "tst_consolecredentials.moc"
