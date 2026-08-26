#include <QtTest>

#include "pbsrequesttally.h"

class PbsRequestTallyTest : public QObject {
    Q_OBJECT

private slots:
    void singleEndpointNeverCompletesEarly();
    void interleavedDatastoresNeverCompleteEarly();
    void emptyTiersCompleteImmediately();
    void failuresDrainTheirTier();
    void decrementsAreFlooredAtZero();
    void resetAbandonsInFlightWork();
};

// One endpoint, one datastore, one namespace, one snapshot. The tally must be
// incomplete at every step until the final snapshot lands.
void PbsRequestTallyTest::singleEndpointNeverCompletesEarly() {
    PbsRequestTally t;
    QVERIFY(t.isComplete());          // nothing asked for yet

    t.addEndpoint();
    QVERIFY(!t.isComplete());

    t.datastoresReceived(1);          // endpoint drained, one namespace listing owed
    QVERIFY(!t.isComplete());
    QCOMPARE(t.pendingEndpoints(), 0);
    QCOMPARE(t.pendingNamespaces(), 1);

    t.namespacesReceived(1);          // namespace drained, one snapshot listing owed
    QVERIFY(!t.isComplete());
    QCOMPARE(t.pendingNamespaces(), 0);
    QCOMPARE(t.pendingSnapshots(), 1);

    t.snapshotFinished();
    QVERIFY(t.isComplete());
}

// The case the three-tier design exists for. Datastore A's namespace listing
// returns and all its snapshots complete while datastore B's namespace listing
// is still outstanding. A tally that only counted snapshots would read zero in
// the middle of this and fire correlation against half the data.
void PbsRequestTallyTest::interleavedDatastoresNeverCompleteEarly() {
    PbsRequestTally t;
    t.addEndpoint();
    t.datastoresReceived(2);          // two namespace listings owed
    QCOMPARE(t.pendingNamespaces(), 2);

    t.namespacesReceived(2);          // datastore A: root + one more
    QCOMPARE(t.pendingNamespaces(), 1);
    QCOMPARE(t.pendingSnapshots(), 2);

    t.snapshotFinished();
    QVERIFY(!t.isComplete());
    t.snapshotFinished();             // A fully drained, B not yet answered
    QCOMPARE(t.pendingSnapshots(), 0);
    QVERIFY(!t.isComplete());         // the assertion this whole type is for

    t.namespacesReceived(1);          // datastore B answers late
    QCOMPARE(t.pendingSnapshots(), 1);
    QVERIFY(!t.isComplete());

    t.snapshotFinished();
    QVERIFY(t.isComplete());
}

// A datastore with no namespaces, or an endpoint with no datastores, must not
// leave the tally waiting for requests that will never be issued.
void PbsRequestTallyTest::emptyTiersCompleteImmediately() {
    PbsRequestTally a;
    a.addEndpoint();
    a.datastoresReceived(0);
    QVERIFY(a.isComplete());

    PbsRequestTally b;
    b.addEndpoint();
    b.datastoresReceived(1);
    b.namespacesReceived(0);
    QVERIFY(b.isComplete());
}

// Errors drain their tier without spawning the next one.
void PbsRequestTallyTest::failuresDrainTheirTier() {
    PbsRequestTally t;
    t.addEndpoint();
    t.addEndpoint();

    t.endpointFailed();               // one secret read or datastore listing failed
    QVERIFY(!t.isComplete());
    QCOMPARE(t.pendingEndpoints(), 1);

    t.datastoresReceived(1);
    t.namespacesReceived(1);
    t.snapshotFinished();             // snapshot errors call this too
    QVERIFY(t.isComplete());
}

// A reply from a superseded refresh can arrive after reset(). It must not push
// a counter negative, which would leave the tally permanently incomplete.
void PbsRequestTallyTest::decrementsAreFlooredAtZero() {
    PbsRequestTally t;
    t.snapshotFinished();
    t.namespacesReceived(0);
    t.endpointFailed();
    QCOMPARE(t.pendingEndpoints(), 0);
    QCOMPARE(t.pendingNamespaces(), 0);
    QCOMPARE(t.pendingSnapshots(), 0);
    QVERIFY(t.isComplete());

    t.addEndpoint();
    t.datastoresReceived(1);
    t.namespacesReceived(1);
    t.snapshotFinished();
    t.snapshotFinished();             // duplicate, must not go negative
    QVERIFY(t.isComplete());
}

// refreshPBSNow() resets mid-flight. Whatever was outstanding is abandoned.
void PbsRequestTallyTest::resetAbandonsInFlightWork() {
    PbsRequestTally t;
    t.addEndpoint();
    t.datastoresReceived(3);
    t.namespacesReceived(4);
    QVERIFY(!t.isComplete());

    t.reset();
    QVERIFY(t.isComplete());
    QCOMPARE(t.pendingEndpoints(), 0);
    QCOMPARE(t.pendingNamespaces(), 0);
    QCOMPARE(t.pendingSnapshots(), 0);
}

QTEST_APPLESS_MAIN(PbsRequestTallyTest)

#include "tst_pbsrequesttally.moc"
