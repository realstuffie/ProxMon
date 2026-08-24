#pragma once

#include <QVariant>

#include <QList>
#include <QSslCertificate>

class QSslConfiguration;

namespace ProxmoxDataUtils {

QVariantList parseMultiHostsJson(const QString &json, qsizetype maxEndpoints = 5);
QString pveSecretKey(const QString &host, int port, const QString &tokenId);
QString pbsSecretKey(const QString &host, int port, const QString &tokenId);

// Key under which a guest's most recent PBS snapshot is stored and looked up.
// Built independently at insert and lookup time, so the exact form is a
// contract: sessionKey|normalized-host|backupType|vmid. The host is trimmed
// and lowercased to match ProxmoxController::normalizedHost().
// No field may contain '|' or a "%N" sequence: the trailing .arg(vmid)
// rescans text the preceding multi-arg call already substituted.
QString backupStatusKey(const QString &sessionKey,
                        const QString &host,
                        const QString &backupType,
                        int vmid);

// Namespace list from a PBS /admin/datastore/{store}/namespace response.
// Rows without an "ns" key are malformed and skipped; a row whose "ns" is an
// empty string is the root namespace and is kept. Always returns at least one
// entry: an unusable payload degrades to the root namespace so a datastore
// still yields its root snapshots rather than nothing.
QList<QString> parsePbsNamespaces(const QVariant &response);

QVariantList buildEndpointQueue(const QVariantList &entries, bool defaultIgnoreSsl);
QVariantList responseRows(const QVariant &response, const QVariantMap &context = {});
QVariantList mergeEndpointBuckets(const QVariantList &endpoints, const QVariantMap &buckets);

// Stable-sorts VM/CT rows in place. Modes mirror the QML sortByStatus():
// "status" (running first, then name, then vmid), "statusId" (running first,
// then vmid), "name", "nameDesc", "id", "idDesc". Unknown modes fall back to
// "status".
void sortItems(QVariantList &items, const QString &mode);

// Load trusted CA certificates from PEM bytes, falling back to reading the
// file at trustedCertPath when the PEM is empty. Shared by the HTTP client
// and the console WebSocket transports (VncWsProxy, LxcTerminal) so every
// connection type honors the same configured CA.
QList<QSslCertificate> trustedCertificatesFromConfig(const QByteArray &trustedCertPem,
                                                     const QString &trustedCertPath);

// Append the configured CA certificates to an existing SSL configuration
// (no-op when neither PEM nor path yield certificates).
void appendTrustedCertificates(QSslConfiguration &config,
                               const QByteArray &trustedCertPem,
                               const QString &trustedCertPath);

} // namespace ProxmoxDataUtils
