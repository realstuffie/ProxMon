#include <QtTest>

#include "vncbuttonmask.h"

using namespace VncButtonMask;

// The mapping is constexpr, so the crossover can be asserted at compile time
// as well as at run time. If someone flattens it into a straight shift, this
// fails the build rather than the suite.
static_assert(fromQtButtons(QtRight)  == (1 << 2), "Qt Right must be RFB bit 2");
static_assert(fromQtButtons(QtMiddle) == (1 << 1), "Qt Middle must be RFB bit 1");
static_assert(fromQtButtons(QtRight) != fromQtButtons(QtMiddle),
              "right and middle must not collapse together");

class VncButtonMaskTest : public QObject {
    Q_OBJECT

private slots:
    void mapsSingleButtons_data();
    void mapsSingleButtons();
    void swapsMiddleAndRight();
    void combinesHeldButtons();
    void ignoresUnknownButtons();
    void mapsWheelDirections_data();
    void mapsWheelDirections();
    void keepsWheelBitsClearOfButtonBits();
};

void VncButtonMaskTest::mapsSingleButtons_data() {
    QTest::addColumn<int>("qtButton");
    QTest::addColumn<int>("expected");

    QTest::newRow("none")    << 0         << 0;
    QTest::newRow("left")    << QtLeft    << (1 << 0);
    QTest::newRow("middle")  << QtMiddle  << (1 << 1);
    QTest::newRow("right")   << QtRight   << (1 << 2);
    QTest::newRow("back")    << QtBack    << (1 << 7);
    QTest::newRow("forward") << QtForward << (1 << 8);
}

void VncButtonMaskTest::mapsSingleButtons() {
    QFETCH(int, qtButton);
    QFETCH(int, expected);
    QCOMPARE(fromQtButtons(qtButton), expected);
}

// Qt orders its mask Left, Right, Middle; RFB orders it Left, Middle, Right.
// Getting this backwards sends a middle-click on every right-click, which
// pastes the X selection into the guest instead of opening a context menu.
void VncButtonMaskTest::swapsMiddleAndRight() {
    QVERIFY(QtRight < QtMiddle);                          // Qt: right is lower
    QVERIFY(fromQtButtons(QtRight) > fromQtButtons(QtMiddle)); // RFB: right is higher
}

void VncButtonMaskTest::combinesHeldButtons() {
    QCOMPARE(fromQtButtons(QtLeft | QtRight), (1 << 0) | (1 << 2));
    QCOMPARE(fromQtButtons(QtLeft | QtMiddle | QtRight),
             (1 << 0) | (1 << 1) | (1 << 2));
    QCOMPARE(fromQtButtons(QtLeft | QtRight | QtMiddle | QtBack | QtForward),
             (1 << 0) | (1 << 1) | (1 << 2) | (1 << 7) | (1 << 8));
}

// An unrecognised Qt button must not fall through onto some RFB bit.
void VncButtonMaskTest::ignoresUnknownButtons() {
    QCOMPARE(fromQtButtons(0x20), 0);
    QCOMPARE(fromQtButtons(0x4000), 0);
    QCOMPARE(fromQtButtons(QtLeft | 0x20), (1 << 0));
}

void VncButtonMaskTest::mapsWheelDirections_data() {
    QTest::addColumn<bool>("up");
    QTest::addColumn<bool>("horizontal");
    QTest::addColumn<int>("expected");

    QTest::newRow("up")    << true  << false << (1 << 3);
    QTest::newRow("down")  << false << false << (1 << 4);
    QTest::newRow("left")  << true  << true  << (1 << 5);
    QTest::newRow("right") << false << true  << (1 << 6);
}

void VncButtonMaskTest::mapsWheelDirections() {
    QFETCH(bool, up);
    QFETCH(bool, horizontal);
    QFETCH(int, expected);
    QCOMPARE(forWheel(up, horizontal), expected);
}

// Scroll and click share one mask on the wire. An overlap would make a
// scroll register as a button press on the guest.
void VncButtonMaskTest::keepsWheelBitsClearOfButtonBits() {
    const int allButtons =
        fromQtButtons(QtLeft | QtRight | QtMiddle | QtBack | QtForward);

    for (bool horizontal : {false, true}) {
        for (bool up : {false, true}) {
            const int wheel = forWheel(up, horizontal);
            QVERIFY2((wheel & allButtons) == 0, "wheel bit collides with a button bit");
        }
    }
}

QTEST_APPLESS_MAIN(VncButtonMaskTest)
#include "tst_vncbuttonmask.moc"
