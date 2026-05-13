#pragma once

// Named constants shared across ProxmoxClient and ProxmoxController.
// Centralises magic strings and numbers so changes are made in one place.

#include <QString>

namespace ProxmoxConst {

// API / dispatch kind tags
namespace Kind {
    inline const QString Qemu     = QStringLiteral("qemu");
    inline const QString Lxc      = QStringLiteral("lxc");
    inline const QString Nodes    = QStringLiteral("nodes");
    inline const QString Children = QStringLiteral("children"); // internal multi-host dispatch
    inline const QString Action   = QStringLiteral("action");   // internal dispatch
    inline const QString Console  = QStringLiteral("console");  // internal dispatch
    inline const QString Fetch    = QStringLiteral("fetch");    // internal dispatch
} // namespace Kind

// VM / CT action verbs sent to the Proxmox API
namespace VmAction {
    inline const QString Start    = QStringLiteral("start");
    inline const QString Shutdown = QStringLiteral("shutdown");
    inline const QString Reboot   = QStringLiteral("reboot");
} // namespace VmAction

// VM / CT and task status values returned by the Proxmox API
namespace Status {
    inline const QString Running  = QStringLiteral("running");
    inline const QString Stopped  = QStringLiteral("stopped");
} // namespace Status

// Numeric defaults
namespace Defaults {
    constexpr int PvePort              = 8006;
    constexpr int PbsPort              = 8007;
    constexpr int PbsRefreshInterval   = 3600;  // seconds
    constexpr int SecondsPerHour       = 3600;
    constexpr int SecondsPerDay        = 86400;
    constexpr int RequestTimeoutMs     = 10000;
    constexpr int LowLatencyTimeoutMs  = 5000;
} // namespace Defaults

} // namespace ProxmoxConst
