#include "proxmoxdatautils.h"

#include "proxmoxconsts.h"

#include <algorithm>

#include <QJsonArray>
#include <QJsonDocument>

namespace ProxmoxDataUtils {

QVariantList parseMultiHostsJson(const QString &json, qsizetype maxEndpoints) {
    const QJsonDocument document = QJsonDocument::fromJson(json.toUtf8());
    if (!document.isArray() || maxEndpoints <= 0) {
        return {};
    }

    QVariantList entries = document.array().toVariantList();
    if (entries.size() > maxEndpoints) {
        entries = entries.mid(0, maxEndpoints);
    }
    for (QVariant &entry : entries) {
        QVariantMap map = entry.toMap();
        if (!map.contains(QStringLiteral("enabled"))) {
            map.insert(QStringLiteral("enabled"), true);
        }
        entry = map;
    }
    return entries;
}

QString pveSecretKey(const QString &host, int port, const QString &tokenId) {
    return QStringLiteral("apiTokenSecret:%1@%2:%3")
        .arg(tokenId.trimmed(), host.trimmed().toLower())
        .arg(port);
}

QVariantList buildEndpointQueue(const QVariantList &entries, bool defaultIgnoreSsl) {
    QVariantList queue;
    for (const QVariant &entryValue : entries) {
        const QVariantMap entry = entryValue.toMap();
        if (!entry.value(QStringLiteral("enabled"), true).toBool()) {
            continue;
        }

        const QString host = entry.value(QStringLiteral("host")).toString().trimmed();
        const QString tokenId = entry.value(QStringLiteral("tokenId")).toString().trimmed();
        if (host.isEmpty() || tokenId.isEmpty()) {
            continue;
        }

        int port = entry.value(QStringLiteral("port"), ProxmoxConst::Defaults::PvePort).toInt();
        if (port <= 0) {
            port = ProxmoxConst::Defaults::PvePort;
        }
        int pbsPort = entry.value(QStringLiteral("pbsPort"), ProxmoxConst::Defaults::PbsPort).toInt();
        if (pbsPort <= 0) {
            pbsPort = ProxmoxConst::Defaults::PbsPort;
        }

        QVariantMap item;
        item.insert(QStringLiteral("sessionKey"), pveSecretKey(host, port, tokenId));
        item.insert(QStringLiteral("label"), entry.value(QStringLiteral("name")).toString().trimmed());
        item.insert(QStringLiteral("host"), host);
        item.insert(QStringLiteral("port"), port);
        item.insert(QStringLiteral("tokenId"), tokenId);
        item.insert(QStringLiteral("ignoreSsl"), entry.value(QStringLiteral("ignoreSsl"), defaultIgnoreSsl));
        item.insert(QStringLiteral("trustedCertPem"), entry.value(QStringLiteral("trustedCertPem")));
        item.insert(QStringLiteral("trustedCertPath"), entry.value(QStringLiteral("trustedCertPath")));
        item.insert(QStringLiteral("pbsEnabled"), entry.value(QStringLiteral("pbsEnabled"), false));
        item.insert(QStringLiteral("pbsHost"), entry.value(QStringLiteral("pbsHost")).toString().trimmed());
        item.insert(QStringLiteral("pbsPort"), pbsPort);
        item.insert(QStringLiteral("pbsTokenId"), entry.value(QStringLiteral("pbsTokenId")).toString().trimmed());
        item.insert(QStringLiteral("pbsIgnoreSsl"), entry.value(QStringLiteral("pbsIgnoreSsl"), false));
        item.insert(QStringLiteral("pbsBackupWarningDays"),
                    std::max(1, entry.value(QStringLiteral("pbsBackupWarningDays"), 7).toInt()));
        item.insert(QStringLiteral("pbsBackupStaleDays"),
                    std::max(1, entry.value(QStringLiteral("pbsBackupStaleDays"), 14).toInt()));
        queue.push_back(item);
    }
    return queue;
}

QVariantList responseRows(const QVariant &response, const QVariantMap &context) {
    QVariantList rows;
    const QVariantList payload = response.toMap().value(QStringLiteral("data")).toList();
    rows.reserve(payload.size());

    for (const QVariant &value : payload) {
        QVariantMap row = value.toMap();
        for (auto it = context.cbegin(); it != context.cend(); ++it) {
            row.insert(it.key(), it.value());
        }
        rows.push_back(row);
    }

    return rows;
}

QVariantList mergeEndpointBuckets(const QVariantList &endpoints, const QVariantMap &buckets) {
    QVariantList rows;
    rows.reserve(endpoints.size());

    for (const QVariant &endpointValue : endpoints) {
        const QVariantMap endpoint = endpointValue.toMap();
        const QString sessionKey = endpoint.value(QStringLiteral("sessionKey")).toString();
        const QVariantMap bucket = buckets.value(sessionKey).toMap();
        QVariantMap row = endpoint;
        row.insert(QStringLiteral("error"), bucket.value(QStringLiteral("error")).toString());
        row.insert(QStringLiteral("offline"), bucket.value(QStringLiteral("offline")).toBool());
        row.insert(QStringLiteral("nodes"), bucket.value(QStringLiteral("nodes")).toList());
        row.insert(QStringLiteral("vms"), bucket.value(QStringLiteral("vms")).toList());
        row.insert(QStringLiteral("lxcs"), bucket.value(QStringLiteral("lxcs")).toList());
        rows.push_back(row);
    }

    std::sort(rows.begin(), rows.end(), [](const QVariant &a, const QVariant &b) {
        const QVariantMap left = a.toMap();
        const QVariantMap right = b.toMap();
        const QString leftLabel = left.value(QStringLiteral("label")).toString().isEmpty()
            ? left.value(QStringLiteral("host")).toString()
            : left.value(QStringLiteral("label")).toString();
        const QString rightLabel = right.value(QStringLiteral("label")).toString().isEmpty()
            ? right.value(QStringLiteral("host")).toString()
            : right.value(QStringLiteral("label")).toString();
        return leftLabel.localeAwareCompare(rightLabel) < 0;
    });

    return rows;
}

} // namespace ProxmoxDataUtils
