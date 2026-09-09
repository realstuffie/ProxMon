#pragma once

#include <QByteArray>

// Framing for the Proxmox LXC terminal auth reply.
//
// After the WebSocket upgrade the client sends "user:ticket\n" and the server
// answers with the literal bytes "OK", optionally followed by "\n" and then
// real terminal data. That reply can arrive split across any number of frames,
// so the decision has to be made against an accumulating buffer rather than
// against one frame.
//
// Extracted from LxcTerminal so the framing can be exercised without a
// QTermWidget, a window or a socket. Every side effect stays with the caller.
namespace LxcAuthFraming {

enum class Outcome {
    NeedMore,       // too few bytes to decide; keep buffering
    Authenticated,  // "OK" seen
    Rejected,       // at least two bytes, and they are not "OK"
};

struct Result {
    Outcome outcome = Outcome::NeedMore;

    // Authenticated: terminal data that followed "OK" and its optional
    // newline. Empty when the reply carried nothing beyond the marker.
    QByteArray passthrough;

    // Rejected: the bytes received, for the error message.
    QByteArray rejected;
};

// Appends incoming to buffer, then classifies what the buffer holds. The
// buffer is cleared on Authenticated and Rejected, and left intact on
// NeedMore so the next frame can extend it.
Result consume(QByteArray &buffer, const QByteArray &incoming);

} // namespace LxcAuthFraming
