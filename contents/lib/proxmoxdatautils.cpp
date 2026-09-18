#include "proxmoxdatautils.h"

#include "proxmoxconsts.h"

#include <algorithm>

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QMap>
#include <QRegularExpression>
#include <QSet>
#include <QSslConfiguration>
#include <QUrlQuery>

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

QString pbsSecretKey(const QString &host, int port, const QString &tokenId) {
    return QStringLiteral("pbsTokenSecret:%1@%2:%3")
        .arg(tokenId.trimmed(), host.trimmed().toLower())
        .arg(port);
}

QString backupStatusKey(const QString &sessionKey,
                        const QString &host,
                        const QString &backupType,
                        int vmid) {
    return QStringLiteral("%1|%2|%3|%4")
        .arg(sessionKey, host.trimmed().toLower(), backupType)
        .arg(vmid);
}

void recordPbsSnapshot(PbsBackupSources &sources, const PBSSnapshot &snapshot) {
    // A structured key avoids delimiter collisions in nested namespace names.
    const QString sourceKey = QString::fromUtf8(QJsonDocument(
        QJsonArray{snapshot.datastoreName, snapshot.backupNamespace}).toJson(QJsonDocument::Compact));
    auto it = sources.find(sourceKey);
    if (it == sources.end() || snapshot.backupTime > it->backupTime) {
        sources.insert(sourceKey, snapshot);
    }
}

PbsBackupMatch selectPbsBackup(const PbsBackupSources &sources,
                              const QString &datastore,
                              const QString &backupNamespace) {
    PbsBackupMatch result;
    QList<PBSSnapshot> matches;
    const QString store = datastore.trimmed();
    const QString ns = backupNamespace.trimmed();
    for (const PBSSnapshot &snapshot : sources) {
        if (!store.isEmpty() && snapshot.datastoreName != store) continue;
        if (ns != QLatin1String("*") && snapshot.backupNamespace != ns) continue;
        matches.push_back(snapshot);
    }
    if (matches.size() == 1) {
        result.snapshot = matches.first();
    } else if (matches.size() > 1) {
        result.ambiguous = true;
        result.sources = describePbsSources(matches);
    }
    return result;
}

int nextKeyringRetryDelayMs(int currentDelayMs) {
    constexpr int startMs = 30 * 1000;
    constexpr int maxMs = 10 * 60 * 1000;
    if (currentDelayMs <= 0) return startMs;
    return currentDelayMs >= maxMs / 2 ? maxMs : currentDelayMs * 2;
}

bool shouldLogKeyringError(const QString &message, const QString &lastMessage,
                           qint64 msSinceLast, qint64 repeatIntervalMs) {
    if (message != lastMessage) return true;
    return msSinceLast < 0 || msSinceLast >= repeatIntervalMs;
}

QString describePbsSources(const QList<PBSSnapshot> &snapshots) {
    QMap<QString, QStringList> byStore; // QMap keeps datastores sorted.
    for (const PBSSnapshot &snapshot : snapshots) {
        const QString ns = snapshot.backupNamespace.isEmpty()
            ? QStringLiteral("root") : snapshot.backupNamespace;
        QStringList &names = byStore[snapshot.datastoreName];
        if (!names.contains(ns)) names.push_back(ns);
    }
    QStringList parts;
    for (auto it = byStore.begin(); it != byStore.end(); ++it) {
        QStringList names = it.value();
        // Root first, then namespaces alphabetically.
        std::sort(names.begin(), names.end(), [](const QString &a, const QString &b) {
            if (a == QLatin1String("root")) return b != QLatin1String("root");
            if (b == QLatin1String("root")) return false;
            return a < b;
        });
        parts.push_back(it.key() + QStringLiteral(": ") + names.join(QStringLiteral(", ")));
    }
    return parts.join(QStringLiteral("; "));
}

QList<QString> filterPbsDatastores(const QList<QString> &datastores, const QString &datastore) {
    const QString store = datastore.trimmed();
    if (store.isEmpty()) return datastores;
    QList<QString> filtered;
    for (const QString &candidate : datastores) {
        if (candidate == store) filtered.push_back(candidate);
    }
    return filtered;
}

QList<QString> filterPbsNamespaces(const QList<QString> &namespaces, const QString &backupNamespace) {
    const QString ns = backupNamespace.trimmed();
    if (ns == QLatin1String("*")) return namespaces;
    QList<QString> filtered;
    for (const QString &candidate : namespaces) {
        if (candidate == ns) filtered.push_back(candidate);
    }
    return filtered;
}

QList<QString> parsePbsNamespaces(const QVariant &response) {
    QList<QString> namespaces;
    const QVariantList rows = response.toMap().value(QStringLiteral("data")).toList();
    for (const QVariant &rowValue : rows) {
        const QVariantMap row = rowValue.toMap();
        if (!row.contains(QStringLiteral("ns"))) {
            continue;
        }
        const QString ns = row.value(QStringLiteral("ns")).toString();
        if (!namespaces.contains(ns)) {
            namespaces.push_back(ns);
        }
    }
    if (namespaces.isEmpty()) {
        namespaces.push_back(QString());
    }
    return namespaces;
}

QString storageTallyMessage(int replies, int repliesWithRows, int matches) {
    if (replies <= 0) return {};
    if (repliesWithRows <= 0) {
        return QStringLiteral(
            "No storage returned. Proxmox sends an empty list when a token lacks "
            "Datastore.Audit. Grant it on /storage, or turn off Storage Usage in settings.");
    }
    if (matches <= 0) {
        return QStringLiteral(
            "No storage matched the names in Storage Monitored. Check them, or clear the "
            "field to track the fullest store that holds guest disks.");
    }
    return {};
}

QList<QString> parseStorageFilter(const QString &value) {
    QList<QString> names;
    const QStringList parts = value.split(QLatin1Char(','), Qt::SkipEmptyParts);
    for (const QString &part : parts) {
        const QString name = part.trimmed();
        if (!name.isEmpty() && !names.contains(name)) names.push_back(name);
    }
    return names;
}

QVariantMap summarizeNodeStorage(const QVariant &response, const QList<QString> &selected) {
    struct Entry { QString name; double fraction; qint64 used; qint64 total; };
    QList<Entry> entries;
    const QVariantList rows = response.toMap().value(QStringLiteral("data")).toList();
    for (const QVariant &rowValue : rows) {
        const QVariantMap row = rowValue.toMap();
        const QString name = row.value(QStringLiteral("storage")).toString().trimmed();
        if (name.isEmpty()) continue;
        // Absent flags mean usable: only an explicit 0 disables a store.
        if (row.value(QStringLiteral("enabled"), 1).toInt() == 0) continue;
        if (row.value(QStringLiteral("active"), 1).toInt() == 0) continue;
        if (selected.isEmpty()) {
            const QString content = row.value(QStringLiteral("content")).toString();
            const QStringList kinds = content.split(QLatin1Char(','), Qt::SkipEmptyParts);
            bool holdsGuests = false;
            for (const QString &kind : kinds) {
                const QString trimmed = kind.trimmed();
                if (trimmed == QLatin1String("images") || trimmed == QLatin1String("rootfs")) {
                    holdsGuests = true;
                    break;
                }
            }
            if (!holdsGuests) continue;
        } else if (!selected.contains(name)) {
            continue;
        }
        const qint64 total = row.value(QStringLiteral("total")).toLongLong();
        const qint64 used = row.value(QStringLiteral("used")).toLongLong();
        if (total <= 0 || used < 0) continue;
        entries.push_back({name, double(used) / double(total), used, total});
    }
    if (entries.isEmpty()) return {};

    // Fullest first, then by name so equal usage keeps a stable order.
    std::sort(entries.begin(), entries.end(), [](const Entry &a, const Entry &b) {
        if (a.fraction != b.fraction) return a.fraction > b.fraction;
        return a.name < b.name;
    });
    QStringList detail;
    constexpr qsizetype maxDetailEntries = 8;
    for (qsizetype i = 0; i < entries.size() && i < maxDetailEntries; ++i) {
        detail.push_back(QStringLiteral("%1 %2%")
            .arg(entries.at(i).name)
            .arg(qRound(entries.at(i).fraction * 100)));
    }
    if (entries.size() > maxDetailEntries) {
        detail.push_back(QStringLiteral("and %1 more").arg(entries.size() - maxDetailEntries));
    }
    QVariantList bars;
    constexpr qsizetype maxBars = 6;
    const qsizetype barCount = selected.isEmpty() ? 1 : std::min<qsizetype>(entries.size(), maxBars);
    for (qsizetype i = 0; i < barCount; ++i) {
        const Entry &entry = entries.at(i);
        bars.push_back(QVariantMap{
            {QStringLiteral("name"), entry.name},
            {QStringLiteral("fraction"), entry.fraction},
            {QStringLiteral("used"), QVariant::fromValue(entry.used)},
            {QStringLiteral("total"), QVariant::fromValue(entry.total)},
        });
    }

    const Entry &fullest = entries.first();
    return QVariantMap{
        {QStringLiteral("storageBars"), bars},
        {QStringLiteral("storageName"), fullest.name},
        {QStringLiteral("storageUsed"), QVariant::fromValue(fullest.used)},
        {QStringLiteral("storageTotal"), QVariant::fromValue(fullest.total)},
        {QStringLiteral("storageFraction"), fullest.fraction},
        {QStringLiteral("storageDetail"), detail.join(QStringLiteral(", "))},
        {QStringLiteral("storageCount"), int(entries.size())},
    };
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
        item.insert(QStringLiteral("storageEnabled"), entry.value(QStringLiteral("storageEnabled"), true));
        item.insert(QStringLiteral("storageFilter"), entry.value(QStringLiteral("storageFilter")).toString().trimmed());
        item.insert(QStringLiteral("pbsEnabled"), entry.value(QStringLiteral("pbsEnabled"), false));
        item.insert(QStringLiteral("pbsHost"), entry.value(QStringLiteral("pbsHost")).toString().trimmed());
        item.insert(QStringLiteral("pbsDatastore"), entry.value(QStringLiteral("pbsDatastore")).toString().trimmed());
        item.insert(QStringLiteral("pbsNamespace"), entry.value(QStringLiteral("pbsNamespace"), QStringLiteral("*")).toString().trimmed());
        item.insert(QStringLiteral("pbsPort"), pbsPort);
        item.insert(QStringLiteral("pbsTokenId"), entry.value(QStringLiteral("pbsTokenId")).toString().trimmed());
        item.insert(QStringLiteral("pbsIgnoreSsl"), entry.value(QStringLiteral("pbsIgnoreSsl"), false));
        item.insert(QStringLiteral("pbsTrustedCertPem"), entry.value(QStringLiteral("pbsTrustedCertPem")));
        item.insert(QStringLiteral("pbsTrustedCertPath"), entry.value(QStringLiteral("pbsTrustedCertPath")).toString().trimmed());
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

void sortItems(QVariantList &items,
               const QString &mode,
               const QHash<QString, int> &ranks,
               const QString &scope) {
    if (mode == QLatin1String("custom")) {
        const auto rankOf = [&ranks, &scope](int vmid) {
            if (scope.isEmpty()) return -1;
            return ranks.value(guestOrderKey(scope, vmid), -1);
        };
        std::stable_sort(items.begin(), items.end(),
                         [&rankOf](const QVariant &av, const QVariant &bv) {
            const int avmid = av.toMap().value(QStringLiteral("vmid")).toInt();
            const int bvmid = bv.toMap().value(QStringLiteral("vmid")).toInt();
            const int ar = rankOf(avmid);
            const int br = rankOf(bvmid);
            if ((ar < 0) != (br < 0)) return ar >= 0;
            if (ar != br) return ar < br;
            return avmid < bvmid;
        });
        return;
    }

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

namespace {

bool isValidGuestOrderScope(const QString &scope) {
    // anchoredPattern: a bare '$' would also accept a trailing newline.
    static const QRegularExpression re(QRegularExpression::anchoredPattern(
        QStringLiteral(R"([a-z0-9._\-:\[\]]{1,253}:[0-9]{1,5})")));
    return re.match(scope).hasMatch();
}

bool isValidGuestOrderKey(const QString &key) {
    if (key.size() > 300) return false;
    const qsizetype slash = key.lastIndexOf(QLatin1Char('/'));
    if (slash <= 0 || slash == key.size() - 1) return false;
    const QStringView vmidPart = QStringView(key).mid(slash + 1);
    if (vmidPart.size() > 9) return false;
    for (const QChar ch : vmidPart) {
        if (ch < QLatin1Char('0') || ch > QLatin1Char('9')) return false;
    }
    return isValidGuestOrderScope(key.left(slash));
}

} // namespace

QString guestOrderScope(const QString &host, int port) {
    if (port < 1 || port > 65535) return {};
    const QString scope = host.trimmed().toLower() + QLatin1Char(':') + QString::number(port);
    return isValidGuestOrderScope(scope) ? scope : QString();
}

QString guestOrderKey(const QString &scope, int vmid) {
    if (scope.isEmpty() || vmid <= 0) return {};
    return scope + QLatin1Char('/') + QString::number(vmid);
}

QStringList sanitizeGuestOrder(const QStringList &order) {
    QStringList out;
    QSet<QString> seen;
    for (const QString &key : order) {
        if (!isValidGuestOrderKey(key) || seen.contains(key)) continue;
        seen.insert(key);
        out.push_back(key);
    }
    if (out.size() > kMaxGuestOrderEntries) {
        out = out.mid(out.size() - kMaxGuestOrderEntries);
    }
    return out;
}

QHash<QString, int> guestOrderRanks(const QStringList &order) {
    const QStringList clean = sanitizeGuestOrder(order);
    QHash<QString, int> ranks;
    ranks.reserve(clean.size());
    for (qsizetype i = 0; i < clean.size(); ++i) {
        ranks.insert(clean.at(i), int(i));
    }
    return ranks;
}

QStringList applyGuestMove(const QStringList &order,
                           const QStringList &sectionKeys,
                           int from,
                           int to) {
    const QStringList clean = sanitizeGuestOrder(order);
    if (from < 0 || to < 0 || from >= sectionKeys.size() || to >= sectionKeys.size()
        || sectionKeys.size() > kMaxGuestOrderEntries) {
        return clean;
    }
    QSet<QString> sectionSet;
    for (const QString &key : sectionKeys) {
        if (!isValidGuestOrderKey(key) || sectionSet.contains(key)) return clean;
        sectionSet.insert(key);
    }

    QStringList moved = sectionKeys;
    moved.move(from, to);

    QStringList result;
    result.reserve(clean.size() + moved.size());
    for (const QString &key : clean) {
        if (!sectionSet.contains(key)) result.push_back(key);
    }
    result.append(moved);
    if (result.size() > kMaxGuestOrderEntries) {
        result = result.mid(result.size() - kMaxGuestOrderEntries);
    }
    return result;
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

namespace {

// Proxmox node names are hostnames and kind is a fixed vocabulary, so a
// conservative allowlist is enough. Rejecting beats encoding here: a name
// that needs encoding is a name we did not expect.
bool isSafePathSegment(const QString &segment) {
    if (segment.isEmpty()) {
        return false;
    }
    // "." and ".." survive a character-class check but are traversal.
    if (segment == QLatin1String(".") || segment == QLatin1String("..")) {
        return false;
    }
    for (const QChar ch : segment) {
        const char16_t c = ch.unicode();
        const bool allowed = (c >= u'a' && c <= u'z')
                          || (c >= u'A' && c <= u'Z')
                          || (c >= u'0' && c <= u'9')
                          || c == u'.' || c == u'_' || c == u'-';
        if (!allowed) {
            return false;
        }
    }
    return true;
}

} // namespace

QUrl buildConsoleWebSocketUrl(const QString &host,
                              int apiPort,
                              const QString &node,
                              const QString &kind,
                              int vmid,
                              int port,
                              const QByteArray &ticket) {
    if (host.isEmpty() || !isSafePathSegment(node)) {
        return {};
    }
    if (!kind.isEmpty() && !isSafePathSegment(kind)) {
        return {};
    }

    QUrl url;
    url.setScheme(QStringLiteral("wss"));
    url.setHost(host);
    url.setPort(apiPort);
    url.setPath(kind.isEmpty()
                    ? QStringLiteral("/api2/json/nodes/%1/vncwebsocket").arg(node)
                    : QStringLiteral("/api2/json/nodes/%1/%2/%3/vncwebsocket")
                          .arg(node, kind).arg(vmid));

    QUrlQuery query;
    query.addQueryItem(QStringLiteral("port"), QString::number(port));
    // ticket is a QByteArray; percent-encoded output is ASCII-safe so
    // fromLatin1 is correct.
    query.addQueryItem(QStringLiteral("vncticket"),
                       QString::fromLatin1(ticket.toPercentEncoding()));
    url.setQuery(query);

    if (!url.isValid()) {
        return {};
    }
    return url;
}

} // namespace ProxmoxDataUtils
