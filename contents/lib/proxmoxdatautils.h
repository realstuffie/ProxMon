#pragma once

#include <QVariant>

#include <QList>
#include <QSslCertificate>

class QSslConfiguration;

namespace ProxmoxDataUtils {

QVariantList parseMultiHostsJson(const QString &json, qsizetype maxEndpoints = 5);
QString pveSecretKey(const QString &host, int port, const QString &tokenId);
QString pbsSecretKey(const QString &host, int port, const QString &tokenId);
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
