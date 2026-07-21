#pragma once

#include <QVariant>

namespace ProxmoxDataUtils {

QVariantList parseMultiHostsJson(const QString &json, qsizetype maxEndpoints = 5);
QString pveSecretKey(const QString &host, int port, const QString &tokenId);
QVariantList buildEndpointQueue(const QVariantList &entries, bool defaultIgnoreSsl);
QVariantList responseRows(const QVariant &response, const QVariantMap &context = {});
QVariantList mergeEndpointBuckets(const QVariantList &endpoints, const QVariantMap &buckets);

// Stable-sorts VM/CT rows in place. Modes mirror the QML sortByStatus():
// "status" (running first, then name, then vmid), "statusId" (running first,
// then vmid), "name", "nameDesc", "id", "idDesc". Unknown modes fall back to
// "status".
void sortItems(QVariantList &items, const QString &mode);

} // namespace ProxmoxDataUtils
