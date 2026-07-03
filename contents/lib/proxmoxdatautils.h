#pragma once

#include <QVariant>

namespace ProxmoxDataUtils {

QVariantList parseMultiHostsJson(const QString &json, qsizetype maxEndpoints = 5);
QString pveSecretKey(const QString &host, int port, const QString &tokenId);
QVariantList buildEndpointQueue(const QVariantList &entries, bool defaultIgnoreSsl);
QVariantList responseRows(const QVariant &response, const QVariantMap &context = {});
QVariantList mergeEndpointBuckets(const QVariantList &endpoints, const QVariantMap &buckets);

} // namespace ProxmoxDataUtils
