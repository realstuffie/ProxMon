#include "lxcauthframing.h"

namespace LxcAuthFraming {

Result consume(QByteArray &buffer, const QByteArray &incoming) {
    buffer.append(incoming);

    Result result;

    // Proxmox replies with the literal bytes "OK" on success. Some versions
    // append a newline and others don't, so accept both.
    if (buffer.startsWith("OK")) {
        result.outcome = Outcome::Authenticated;

        qsizetype consumed = 2;
        if (buffer.size() > 2 && buffer.at(2) == '\n') {
            consumed = 3;
        }
        if (buffer.size() > consumed) {
            result.passthrough = buffer.mid(consumed);
        }
        buffer.clear();
        return result;
    }

    // Under two bytes this could still turn into "OK" on the next frame.
    if (buffer.size() < 2) {
        result.outcome = Outcome::NeedMore;
        return result;
    }

    result.outcome = Outcome::Rejected;
    result.rejected = buffer;
    buffer.clear();
    return result;
}

} // namespace LxcAuthFraming
