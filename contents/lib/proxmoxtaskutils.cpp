#include "proximoxtaskutils.h"

#include "proxmoxconsts.h"

namespace ProxmoxTaskUtils {

QString extractUpid(const QVariant &response) {
    const QVariant value = response.toMap().value(QStringLiteral("data"));
    if (value.metaType().id() != QMetaType::QString) {
        return {};
    }
    return value.toString().trimmed();
}

bool isRunning(const QVariant &response) {
    const QVariantMap payload = response.toMap().value(QStringLiteral("data")).toMap();
    const QString status = payload.value(QStringLiteral("status")).toString().trimmed();
    return status.compare(ProxmoxConst::Status::Running, Qt::CaseInsensitive) == 0;
}

QString exitMessage(const QVariant &response) {
    const QVariantMap payload = response.toMap().value(QStringLiteral("data")).toMap();
    const QString exitStatus = payload.value(QStringLiteral("exitstatus")).toString().trimmed();
    const QString status = payload.value(QStringLiteral("status")).toString().trimmed();

    if (exitStatus.compare(QStringLiteral("OK"), Qt::CaseInsensitive) == 0
        || exitStatus.compare(QStringLiteral("TASK OK"), Qt::CaseInsensitive) == 0
        || exitStatus.startsWith(QStringLiteral("TASK WARNINGS"), Qt::CaseInsensitive)) {
        return {};
    }
    if (!exitStatus.isEmpty()) {
        return exitStatus;
    }
    if (status.compare(ProxmoxConst::Status::Stopped, Qt::CaseInsensitive) == 0) {
        return QStringLiteral("Task stopped without success");
    }
    return {};
}

} // namespace ProxmoxTaskUtils
