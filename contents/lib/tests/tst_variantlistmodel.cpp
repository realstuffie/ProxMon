#include <QSignalSpy>
#include <QTest>

#include "variantlistmodel.h"

/*  Verifies the diffing behaviour VariantListModel exists for: unchanged
    input emits nothing, per-row updates emit dataChanged only for that row,
    membership changes emit insert/remove, sort-order changes emit moves,
    and duplicate keys are dropped (first wins).
*/
class TestVariantListModel : public QObject {
    Q_OBJECT

private:
    static QVariantMap vm(const QString &node, int vmid, const QString &status, double cpu = 0.0) {
        return {
            {QStringLiteral("node"), node},
            {QStringLiteral("vmid"), vmid},
            {QStringLiteral("status"), status},
            {QStringLiteral("cpu"), cpu},
        };
    }

    static VariantListModel *makeModel(QObject *parent) {
        return new VariantListModel({QStringLiteral("node"), QStringLiteral("vmid")}, parent);
    }

private slots:
    void initialPopulate_insertsAll() {
        auto *model = makeModel(this);
        model->applyItems({vm("pve", 100, "running"), vm("pve", 101, "stopped")});
        QCOMPARE(model->count(), 2);
        QCOMPARE(model->runningCount(), 1);
        QCOMPARE(model->get(0).value(QStringLiteral("vmid")).toInt(), 100);
    }

    void identicalApply_emitsNothing() {
        auto *model = makeModel(this);
        const QVariantList items = {vm("pve", 100, "running"), vm("pve", 101, "stopped")};
        model->applyItems(items);

        QSignalSpy dataSpy(model, &QAbstractItemModel::dataChanged);
        QSignalSpy insertSpy(model, &QAbstractItemModel::rowsInserted);
        QSignalSpy removeSpy(model, &QAbstractItemModel::rowsRemoved);
        QSignalSpy moveSpy(model, &QAbstractItemModel::rowsMoved);
        QSignalSpy countSpy(model, &VariantListModel::countChanged);

        model->applyItems(items);

        QCOMPARE(dataSpy.count(), 0);
        QCOMPARE(insertSpy.count(), 0);
        QCOMPARE(removeSpy.count(), 0);
        QCOMPARE(moveSpy.count(), 0);
        QCOMPARE(countSpy.count(), 0);
    }

    void changedRow_emitsSingleDataChanged() {
        auto *model = makeModel(this);
        model->applyItems({vm("pve", 100, "running", 0.10), vm("pve", 101, "stopped")});

        QSignalSpy dataSpy(model, &QAbstractItemModel::dataChanged);
        QSignalSpy insertSpy(model, &QAbstractItemModel::rowsInserted);
        QSignalSpy removeSpy(model, &QAbstractItemModel::rowsRemoved);

        // Only vm 100's cpu changes.
        model->applyItems({vm("pve", 100, "running", 0.55), vm("pve", 101, "stopped")});

        QCOMPARE(dataSpy.count(), 1);
        QCOMPARE(dataSpy.at(0).at(0).toModelIndex().row(), 0);
        QCOMPARE(insertSpy.count(), 0);
        QCOMPARE(removeSpy.count(), 0);
        QCOMPARE(model->get(0).value(QStringLiteral("cpu")).toDouble(), 0.55);
    }

    void membershipChange_insertsAndRemoves() {
        auto *model = makeModel(this);
        model->applyItems({vm("pve", 100, "running"), vm("pve", 101, "stopped")});

        QSignalSpy insertSpy(model, &QAbstractItemModel::rowsInserted);
        QSignalSpy removeSpy(model, &QAbstractItemModel::rowsRemoved);

        // 101 gone, 102 new.
        model->applyItems({vm("pve", 100, "running"), vm("pve", 102, "running")});

        QCOMPARE(removeSpy.count(), 1);
        QCOMPARE(insertSpy.count(), 1);
        QCOMPARE(model->count(), 2);
        QCOMPARE(model->runningCount(), 2);
        QCOMPARE(model->get(1).value(QStringLiteral("vmid")).toInt(), 102);
    }

    void reorder_emitsMovesNotResets() {
        auto *model = makeModel(this);
        model->applyItems({vm("pve", 100, "running"), vm("pve", 101, "stopped"), vm("pve", 102, "stopped")});

        QSignalSpy moveSpy(model, &QAbstractItemModel::rowsMoved);
        QSignalSpy insertSpy(model, &QAbstractItemModel::rowsInserted);
        QSignalSpy removeSpy(model, &QAbstractItemModel::rowsRemoved);
        QSignalSpy resetSpy(model, &QAbstractItemModel::modelReset);

        // 102 started and sorts to the front (status sort done by caller).
        model->applyItems({vm("pve", 102, "running"), vm("pve", 100, "running"), vm("pve", 101, "stopped")});

        QVERIFY(moveSpy.count() >= 1);
        QCOMPARE(insertSpy.count(), 0);
        QCOMPARE(removeSpy.count(), 0);
        QCOMPARE(resetSpy.count(), 0);
        QCOMPARE(model->get(0).value(QStringLiteral("vmid")).toInt(), 102);
        QCOMPARE(model->get(1).value(QStringLiteral("vmid")).toInt(), 100);
        QCOMPARE(model->get(2).value(QStringLiteral("vmid")).toInt(), 101);
    }

    void duplicateKeys_firstWins() {
        auto *model = makeModel(this);
        model->applyItems({vm("pve", 100, "running", 0.10), vm("pve", 100, "stopped", 0.99)});
        QCOMPARE(model->count(), 1);
        QCOMPARE(model->get(0).value(QStringLiteral("status")).toString(), QStringLiteral("running"));
    }

    void reorder_moveDown_emitsMovesNotResets() {
        auto *model = makeModel(this);
        model->applyItems({vm("pve", 100, "running"), vm("pve", 101, "running"), vm("pve", 102, "running")});

        QSignalSpy moveSpy(model, &QAbstractItemModel::rowsMoved);
        QSignalSpy insertSpy(model, &QAbstractItemModel::rowsInserted);
        QSignalSpy removeSpy(model, &QAbstractItemModel::rowsRemoved);
        QSignalSpy resetSpy(model, &QAbstractItemModel::modelReset);

        // 100 stopped and sorts to the back: a row moving DOWN, expressed by
        // the diff as later rows moving up past it.
        model->applyItems({vm("pve", 101, "running"), vm("pve", 102, "running"), vm("pve", 100, "stopped")});

        QVERIFY(moveSpy.count() >= 1);
        QCOMPARE(insertSpy.count(), 0);
        QCOMPARE(removeSpy.count(), 0);
        QCOMPARE(resetSpy.count(), 0);
        QCOMPARE(model->get(0).value(QStringLiteral("vmid")).toInt(), 101);
        QCOMPARE(model->get(1).value(QStringLiteral("vmid")).toInt(), 102);
        QCOMPARE(model->get(2).value(QStringLiteral("vmid")).toInt(), 100);
    }

    void moveAndUpdate_inOneApply() {
        auto *model = makeModel(this);
        model->applyItems({vm("pve", 100, "running", 0.10), vm("pve", 101, "stopped", 0.00)});

        QSignalSpy moveSpy(model, &QAbstractItemModel::rowsMoved);
        QSignalSpy dataSpy(model, &QAbstractItemModel::dataChanged);

        // 101 started: it moves to the front AND its map changed.
        model->applyItems({vm("pve", 101, "running", 0.20), vm("pve", 100, "running", 0.10)});

        QVERIFY(moveSpy.count() >= 1);
        QVERIFY(dataSpy.count() >= 1);
        QCOMPARE(model->get(0).value(QStringLiteral("vmid")).toInt(), 101);
        QCOMPARE(model->get(0).value(QStringLiteral("status")).toString(), QStringLiteral("running"));
        QCOMPARE(model->get(0).value(QStringLiteral("cpu")).toDouble(), 0.20);
        QCOMPARE(model->runningCount(), 2);
    }

    /*  Multi-host child models key on sessionKey + node + vmid: the same
        guest seen through two endpoints stays distinct (matches the old JS
        dedupe in getVmsForNodeMulti, which keyed per endpoint). Dedupe only
        collapses true duplicates within one endpoint.
    */
    void multiHostKey_keepsSameGuestAcrossSessions() {
        auto *model = new VariantListModel(
            {QStringLiteral("sessionKey"), QStringLiteral("node"), QStringLiteral("vmid")}, this);

        QVariantMap a = vm("pve", 100, "running");
        a.insert(QStringLiteral("sessionKey"), QStringLiteral("hostA"));
        QVariantMap b = vm("pve", 100, "running");
        b.insert(QStringLiteral("sessionKey"), QStringLiteral("hostB"));
        QVariantMap aDup = a;

        model->applyItems({a, b, aDup});

        // a and b are distinct rows; aDup collapses into a (first wins).
        QCOMPARE(model->count(), 2);
        QCOMPARE(model->get(0).value(QStringLiteral("sessionKey")).toString(), QStringLiteral("hostA"));
        QCOMPARE(model->get(1).value(QStringLiteral("sessionKey")).toString(), QStringLiteral("hostB"));
    }

    void clear_resetsEverything() {
        auto *model = makeModel(this);
        model->applyItems({vm("pve", 100, "running")});
        QSignalSpy resetSpy(model, &QAbstractItemModel::modelReset);
        model->clear();
        QCOMPARE(resetSpy.count(), 1);
        QCOMPARE(model->count(), 0);
        QCOMPARE(model->runningCount(), 0);
        // clear() on an already-empty model is a no-op.
        model->clear();
        QCOMPARE(resetSpy.count(), 1);
    }

    /*  Node rows carry per-node submodels as QObject* values. The
        "unchanged node row emits nothing" property rests on QVariant
        comparing those by pointer identity (QMetaType::QObjectStar) and on
        the controller reusing the same pointer across refreshes. Pin the
        QVariant half here: same pointer -> silent, different pointer ->
        dataChanged, even when every other field is identical.
    */
    void objectPointerValues_compareByIdentity() {
        auto *model = new VariantListModel({QStringLiteral("node")}, this);
        QObject submodelA;
        QObject submodelB;

        QVariantMap row{{QStringLiteral("node"), QStringLiteral("pve1")},
                        {QStringLiteral("vmsModel"), QVariant::fromValue<QObject *>(&submodelA)}};
        model->applyItems({row});

        QSignalSpy dataSpy(model, &QAbstractItemModel::dataChanged);

        // Same pointer: no emission.
        model->applyItems({row});
        QCOMPARE(dataSpy.count(), 0);

        // Different pointer, same everything else: must emit.
        row.insert(QStringLiteral("vmsModel"), QVariant::fromValue<QObject *>(&submodelB));
        model->applyItems({row});
        QCOMPARE(dataSpy.count(), 1);
    }

    void nodeRows_countOnlineAsRunning() {
        auto *model = new VariantListModel({QStringLiteral("node")}, this);
        model->applyItems({
            QVariantMap{{QStringLiteral("node"), QStringLiteral("pve1")}, {QStringLiteral("status"), QStringLiteral("online")}},
            QVariantMap{{QStringLiteral("node"), QStringLiteral("pve2")}, {QStringLiteral("status"), QStringLiteral("offline")}},
        });
        QCOMPARE(model->runningCount(), 1);
    }
};

QTEST_GUILESS_MAIN(TestVariantListModel)
#include "tst_variantlistmodel.moc"
