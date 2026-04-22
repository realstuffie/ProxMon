#pragma once

#include <QString>

struct PBSSnapshot {
    int vmid = 0;
    QString backupType;
    qint64 backupTime = 0;
    qint64 size = 0;
    QString verifyState;
    QString datastoreName;
    QString pbsHost;
};

enum class BackupStatus {
    Unknown,
    Current,
    Warning,
    Stale,
    Never
};
