#include <QtTest>

#include "vnckeysym.h"

class VncKeysymTest : public QObject {
    Q_OBJECT

private slots:
    void mapsKeyToExpectedKeysym_data();
    void mapsKeyToExpectedKeysym();
};

void VncKeysymTest::mapsKeyToExpectedKeysym_data() {
    QTest::addColumn<int>("key");
    QTest::addColumn<QString>("text");
    QTest::addColumn<int>("location");
    QTest::addColumn<quint32>("expected");

    QTest::newRow("return")
        << int(Qt::Key_Return) << QString() << KEY_LOC_STANDARD << quint32(XK_Return);
    QTest::newRow("numpad-enter")
        << int(Qt::Key_Enter) << QString() << KEY_LOC_NUMPAD << quint32(XK_KP_Enter);
    QTest::newRow("left-control")
        << int(Qt::Key_Control) << QString() << KEY_LOC_LEFT << quint32(XK_Control_L);
    QTest::newRow("right-control")
        << int(Qt::Key_Control) << QString() << KEY_LOC_RIGHT << quint32(XK_Control_R);
    QTest::newRow("printable-latin")
        << int(Qt::Key_A) << QStringLiteral("a") << KEY_LOC_STANDARD << quint32('a');
    QTest::newRow("printable-unicode")
        << int(Qt::Key_unknown) << QString(QChar(0x0101)) << KEY_LOC_STANDARD << quint32(0x01000101);
    QTest::newRow("control-character-fallback")
        << int(Qt::Key_C) << QString(QChar(0x03)) << KEY_LOC_STANDARD << quint32('c');
    QTest::newRow("unknown")
        << int(Qt::Key_unknown) << QString() << KEY_LOC_STANDARD << quint32(0);
}

void VncKeysymTest::mapsKeyToExpectedKeysym() {
    QFETCH(int, key);
    QFETCH(QString, text);
    QFETCH(int, location);
    QFETCH(quint32, expected);

    QCOMPARE(getKeysym(Qt::Key(key), text, location), expected);
}

QTEST_APPLESS_MAIN(VncKeysymTest)

#include "tst_vnckeysym.moc"
