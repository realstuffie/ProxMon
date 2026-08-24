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

enum class BackupStatus {
    Unknown,
    Current,
    Warning,
    Stale,
    Never,
    Excluded
};
