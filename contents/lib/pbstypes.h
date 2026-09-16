#pragma once

#include <QString>

struct PBSSnapshot {
    int vmid = 0;
    QString backupType;
    qint64 backupTime = 0;
    qint64 size = 0;
    QString verifyState;
    QString datastoreName;
    // PBS namespace the snapshot was listed from; empty means the root
    // namespace. Snapshot rows carry no namespace field, so this is
    // stamped from the request that produced the row.
    QString backupNamespace;
    QString pbsHost;
};

// QML reads these as ints through contents/ui/components/backupstatus.mjs.
// Append new values only, and update that file in the same change.
enum class BackupStatus {
    Unknown,
    Current,
    Warning,
    Stale,
    Never,
    Excluded,
    Ambiguous
};
