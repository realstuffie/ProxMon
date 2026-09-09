#pragma once

// Qt mouse state to RFB pointer button mask.
//
// The two vocabularies disagree about the middle and right buttons, and they
// disagree by swapping: Qt's mask runs Left, Right, Middle while RFB's runs
// Left, Middle, Right. Collapsing this into a straight shift is the
// obvious-looking simplification, and it turns every right-click into a
// middle-click, which is the kind of bug that gets reported as "paste happens
// when I open the context menu".
//
// Qt:  Left 0x01, Right 0x02, Middle 0x04, Back 0x08, Forward 0x10
// RFB: Left bit0, Middle bit1, Right bit2, Back bit7, Forward bit8
namespace VncButtonMask {

// Qt::MouseButton values, restated so this header pulls in no Qt GUI types
// and stays usable from a guiless test.
constexpr int QtLeft    = 0x01;
constexpr int QtRight   = 0x02;
constexpr int QtMiddle  = 0x04;
constexpr int QtBack    = 0x08;
constexpr int QtForward = 0x10;

// Buttons outside the five above are ignored rather than passed through, so
// a future Qt button cannot land on an unintended RFB bit.
constexpr int fromQtButtons(int qtButtons) {
    int mask = 0;
    if (qtButtons & QtLeft)    mask |= (1 << 0);
    if (qtButtons & QtRight)   mask |= (1 << 2);
    if (qtButtons & QtMiddle)  mask |= (1 << 1);
    if (qtButtons & QtBack)    mask |= (1 << 7);
    if (qtButtons & QtForward) mask |= (1 << 8);
    return mask;
}

// RFB has no scroll axis: a wheel step is a momentary press and release of a
// dedicated button. For a horizontal wheel, `up` means left.
constexpr int forWheel(bool up, bool horizontal) {
    if (horizontal) {
        return up ? (1 << 5) : (1 << 6);
    }
    return up ? (1 << 3) : (1 << 4);
}

} // namespace VncButtonMask
