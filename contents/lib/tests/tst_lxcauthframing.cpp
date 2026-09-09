#include <QtTest>

#include "lxcauthframing.h"

using LxcAuthFraming::Outcome;
using LxcAuthFraming::Result;

Q_DECLARE_METATYPE(Outcome)

namespace {

// Feed a sequence of frames through one buffer, returning the last result.
Result feed(QByteArray &buffer, const QList<QByteArray> &frames) {
    Result result;
    for (const QByteArray &frame : frames) {
        result = LxcAuthFraming::consume(buffer, frame);
    }
    return result;
}

} // namespace

class LxcAuthFramingTest : public QObject {
    Q_OBJECT

private slots:
    void acceptsOkMarker_data();
    void acceptsOkMarker();
    void reassemblesSplitMarker();
    void reassemblesSplitMarkerWithTrailingData();
    void buffersUntilTwoBytes();
    void rejectsNonOkReply_data();
    void rejectsNonOkReply();
    void clearsBufferOnceDecided();
    void keepsPassthroughBytesIntact();
    void treatsOkPrefixAsSuccess();
};

void LxcAuthFramingTest::acceptsOkMarker_data() {
    QTest::addColumn<QByteArray>("reply");
    QTest::addColumn<QByteArray>("passthrough");

    QTest::newRow("bare")            << QByteArrayLiteral("OK")        << QByteArray();
    QTest::newRow("trailing-nl")     << QByteArrayLiteral("OK\n")      << QByteArray();
    QTest::newRow("nl-then-data")    << QByteArrayLiteral("OK\nready") << QByteArrayLiteral("ready");
    // Some versions omit the newline, so data can butt straight against OK.
    QTest::newRow("data-no-nl")      << QByteArrayLiteral("OKready")   << QByteArrayLiteral("ready");
    QTest::newRow("two-newlines")    << QByteArrayLiteral("OK\n\n")    << QByteArrayLiteral("\n");
}

void LxcAuthFramingTest::acceptsOkMarker() {
    QFETCH(QByteArray, reply);
    QFETCH(QByteArray, passthrough);

    QByteArray buffer;
    const Result result = LxcAuthFraming::consume(buffer, reply);

    QCOMPARE(result.outcome, Outcome::Authenticated);
    QCOMPARE(result.passthrough, passthrough);
}

// The reply is a byte stream, so "OK" can straddle a frame boundary. A
// decision taken on the first frame alone would reject a good login.
void LxcAuthFramingTest::reassemblesSplitMarker() {
    QByteArray buffer;

    const Result first = LxcAuthFraming::consume(buffer, QByteArrayLiteral("O"));
    QCOMPARE(first.outcome, Outcome::NeedMore);

    const Result second = LxcAuthFraming::consume(buffer, QByteArrayLiteral("K"));
    QCOMPARE(second.outcome, Outcome::Authenticated);
    QVERIFY(second.passthrough.isEmpty());
}

void LxcAuthFramingTest::reassemblesSplitMarkerWithTrailingData() {
    QByteArray buffer;
    const Result result = feed(buffer, {QByteArrayLiteral("O"),
                                        QByteArrayLiteral("K\nroot@ct:~# ")});

    QCOMPARE(result.outcome, Outcome::Authenticated);
    QCOMPARE(result.passthrough, QByteArrayLiteral("root@ct:~# "));
}

// One byte is never enough to reject: it could still become "OK".
void LxcAuthFramingTest::buffersUntilTwoBytes() {
    QByteArray buffer;

    QCOMPARE(LxcAuthFraming::consume(buffer, QByteArrayLiteral("X")).outcome,
             Outcome::NeedMore);
    QCOMPARE(buffer, QByteArrayLiteral("X"));

    const Result second = LxcAuthFraming::consume(buffer, QByteArrayLiteral("Y"));
    QCOMPARE(second.outcome, Outcome::Rejected);
    QCOMPARE(second.rejected, QByteArrayLiteral("XY"));
}

void LxcAuthFramingTest::rejectsNonOkReply_data() {
    QTest::addColumn<QByteArray>("reply");

    QTest::newRow("no")          << QByteArrayLiteral("NO");
    QTest::newRow("error-text")  << QByteArrayLiteral("permission denied");
    QTest::newRow("lowercase")   << QByteArrayLiteral("ok");
    QTest::newRow("leading-ws")  << QByteArrayLiteral(" OK");
    QTest::newRow("leading-nl")  << QByteArrayLiteral("\nOK");
}

void LxcAuthFramingTest::rejectsNonOkReply() {
    QFETCH(QByteArray, reply);

    QByteArray buffer;
    const Result result = LxcAuthFraming::consume(buffer, reply);

    QCOMPARE(result.outcome, Outcome::Rejected);
    QCOMPARE(result.rejected, reply);
}

// A stale buffer would poison the next auth attempt on a reconnect.
void LxcAuthFramingTest::clearsBufferOnceDecided() {
    QByteArray accepted;
    LxcAuthFraming::consume(accepted, QByteArrayLiteral("OK\ndata"));
    QVERIFY(accepted.isEmpty());

    QByteArray refused;
    LxcAuthFraming::consume(refused, QByteArrayLiteral("NO"));
    QVERIFY(refused.isEmpty());
}

// Passthrough goes straight to the terminal, so embedded NULs and high
// bytes have to survive unaltered.
void LxcAuthFramingTest::keepsPassthroughBytesIntact() {
    const QByteArray payload("\x1b[32m\x00\xff ok", 11);

    QByteArray buffer;
    const Result result =
        LxcAuthFraming::consume(buffer, QByteArrayLiteral("OK\n") + payload);

    QCOMPARE(result.outcome, Outcome::Authenticated);
    QCOMPARE(result.passthrough, payload);
    QCOMPARE(result.passthrough.size(), payload.size());
}

// Documented behaviour rather than a preference: the check is a prefix
// match, so a hypothetical "OKAY" reads as OK plus terminal data "AY".
// Proxmox sends exactly "OK", and this pins what happens if that changes.
void LxcAuthFramingTest::treatsOkPrefixAsSuccess() {
    QByteArray buffer;
    const Result result = LxcAuthFraming::consume(buffer, QByteArrayLiteral("OKAY"));

    QCOMPARE(result.outcome, Outcome::Authenticated);
    QCOMPARE(result.passthrough, QByteArrayLiteral("AY"));
}

QTEST_APPLESS_MAIN(LxcAuthFramingTest)
#include "tst_lxcauthframing.moc"
