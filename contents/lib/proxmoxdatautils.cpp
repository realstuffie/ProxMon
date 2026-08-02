#include "proxmoxdatautils.h"

#include "proxmoxconsts.h"

#include <algorithm>

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSslConfiguration>

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

void sortItems(QVariantList &items, const QString &mode) {
    auto nameOf = [](const QVariantMap &m) {
        QString n = m.value(QStringLiteral("name")).toString();
        if (n.isEmpty()) {
            n = m.value(QStringLiteral("hostname")).toString();
        }
        return n;
    };

    std::stable_sort(items.begin(), items.end(),
                     [&nameOf, &mode](const QVariant &av, const QVariant &bv) {
        const QVariantMap a = av.toMap();
        const QVariantMap b = bv.toMap();
        const int avmid = a.value(QStringLiteral("vmid")).toInt();
        const int bvmid = b.value(QStringLiteral("vmid")).toInt();

        if (mode == QLatin1String("id")) {
            return avmid < bvmid;
        }
        if (mode == QLatin1String("idDesc")) {
            return bvmid < avmid;
        }

        // Running-first grouping like "status", but ordered by vmid within
        // each group instead of by name.
        if (mode == QLatin1String("statusId")) {
            const int aRun = a.value(QStringLiteral("status")).toString() == ProxmoxConst::Status::Running ? 0 : 1;
            const int bRun = b.value(QStringLiteral("status")).toString() == ProxmoxConst::Status::Running ? 0 : 1;
            if (aRun != bRun) return aRun < bRun;
            return avmid < bvmid;
        }

        const QString an = nameOf(a);
        const QString bn = nameOf(b);
        if (mode == QLatin1String("name")) {
            const int c = an.localeAwareCompare(bn);
            if (c != 0) return c < 0;
            return avmid < bvmid;
        }
        if (mode == QLatin1String("nameDesc")) {
            const int c = bn.localeAwareCompare(an);
            if (c != 0) return c < 0;
            return avmid < bvmid;
        }

        // "status" and fallback
        const int aRun = a.value(QStringLiteral("status")).toString() == ProxmoxConst::Status::Running ? 0 : 1;
        const int bRun = b.value(QStringLiteral("status")).toString() == ProxmoxConst::Status::Running ? 0 : 1;
        if (aRun != bRun) return aRun < bRun;
        const int c = an.localeAwareCompare(bn);
        if (c != 0) return c < 0;
        return avmid < bvmid;
    });
}

QList<QSslCertificate> trustedCertificatesFromConfig(const QByteArray &trustedCertPem,
                                                     const QString &trustedCertPath) {
    QByteArray source = trustedCertPem;
    if (source.isEmpty() && !trustedCertPath.trimmed().isEmpty()) {
        QFile file(trustedCertPath.trimmed());
        if (file.open(QIODevice::ReadOnly)) {
            source = file.readAll();
        }
    }
    if (source.isEmpty()) {
        return {};
    }
    return QSslCertificate::fromData(source, QSsl::Pem);
}

void appendTrustedCertificates(QSslConfiguration &config,
                               const QByteArray &trustedCertPem,
                               const QString &trustedCertPath) {
    const QList<QSslCertificate> certs = trustedCertificatesFromConfig(trustedCertPem, trustedCertPath);
    if (certs.isEmpty()) {
        return;
    }
    QList<QSslCertificate> caCertificates = config.caCertificates();
    caCertificates.append(certs);
    config.setCaCertificates(caCertificates);
}

} // namespace ProxmoxDataUtils
