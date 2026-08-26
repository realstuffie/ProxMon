#include <QtTest>

#include "proxmoxcontroller.h"
#include "proxmoxdatautils.h"
#include "secretstore.h"

class SecretKeyDerivationTest : public QObject {
    Q_OBJECT

private slots:
    void pveKeysDiscriminateTokensOnSameHost();
    void pbsSecretKeyDiscriminatesTokensAndPorts();
    void pbsStoreKeysDiscriminateTokensOnSharedHost();
};

void SecretKeyDerivationTest::pveKeysDiscriminateTokensOnSameHost() {
    const QString a = ProxmoxDataUtils::pveSecretKey("pve.example", 8006, "mon-a@pve!a");
    const QString b = ProxmoxDataUtils::pveSecretKey("pve.example", 8006, "mon-b@pve!b");
    const QString otherPort = ProxmoxDataUtils::pveSecretKey("pve.example", 8443, "mon-a@pve!a");

    QVERIFY(a != b);
    QVERIFY(a != otherPort);
}

void SecretKeyDerivationTest::pbsSecretKeyDiscriminatesTokensAndPorts() {
    const QString a = ProxmoxDataUtils::pbsSecretKey("backup.example", 8007, "backup@pbs!a");
    const QString b = ProxmoxDataUtils::pbsSecretKey("backup.example", 8007, "backup@pbs!b");
    const QString otherPort = ProxmoxDataUtils::pbsSecretKey("backup.example", 8008, "backup@pbs!a");
    const QString caseVariant = ProxmoxDataUtils::pbsSecretKey("Backup.Example", 8007, "backup@pbs!a");

    QVERIFY(a != b);
    QVERIFY(a != otherPort);
    QCOMPARE(a, caseVariant);
    QCOMPARE(a, QStringLiteral("pbsTokenSecret:backup@pbs!a@backup.example:8007"));
}

void SecretKeyDerivationTest::pbsStoreKeysDiscriminateTokensOnSharedHost() {
    ProxmoxController controller;
    const auto stores = controller.findChildren<SecretStore *>();
    QVERIFY(stores.size() >= 2);

    QStringList keys;
    for (SecretStore *store : std::as_const(stores)) {
        QObject::connect(store, &SecretStore::keyChanged, this,
                         [&keys, store]() {
                             keys.append(store->key());
                         });
    }

    // Endpoint A: dedicated PBS token on a shared PBS host (the per-cluster
    // monitoring-user pattern the README recommends).
    controller.storeMultiHostPBSSecret(QStringLiteral("backup.example"), 8007, QStringLiteral("backup@pbs!a"), QStringLiteral("secret-a"));
    QCOMPARE(keys.size(), 1);
    const QString keyForTokenA = keys.first();
    QVERIFY(!keyForTokenA.isEmpty());

    // Endpoint B: a different token on the same PBS host.
    controller.storeMultiHostPBSSecret(QStringLiteral("backup.example"), 8007, QStringLiteral("backup@pbs!b"), QStringLiteral("secret-b"));

    QCOMPARE(keys.size(), 2);
    if (keyForTokenA == keys.last()) {
        QFAIL(qPrintable(QStringLiteral(
                    "distinct PBS tokens on one shared PBS host must not target the same "
                    "keyring slot; both targeted: %1")
                        .arg(keyForTokenA)));
    }
}

QTEST_APPLESS_MAIN(SecretKeyDerivationTest)

#include "tst_secretkeyderivation.moc"
