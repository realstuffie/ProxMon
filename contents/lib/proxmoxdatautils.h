#pragma once

#include <QVariant>

#include <QHash>
#include <QList>
#include <QStringList>
#include <QSslCertificate>
#include <QUrl>
#include "pbstypes.h"

class QSslConfiguration;

namespace ProxmoxDataUtils {

QVariantList parseMultiHostsJson(const QString &json, qsizetype maxEndpoints = 5);
QString pveSecretKey(const QString &host, int port, const QString &tokenId);
QString pbsSecretKey(const QString &host, int port, const QString &tokenId);

// Key under which a guest's PBS sources are stored and looked up.
// Built independently at insert and lookup time, so the exact form is a
// contract: sessionKey|normalized-host|backupType|vmid. The host is trimmed
// and lowercased to match ProxmoxController::normalizedHost().
// No field may contain '|' or a "%N" sequence: the trailing .arg(vmid)
// rescans text the preceding multi-arg call already substituted.
QString backupStatusKey(const QString &sessionKey,
                        const QString &host,
                        const QString &backupType,
                        int vmid);

// Keep the newest snapshot for each exact datastore/namespace pair. Sources
// belong to one endpoint, PBS host, guest type and VMID (backupStatusKey).
using PbsBackupSources = QHash<QString, PBSSnapshot>;
void recordPbsSnapshot(PbsBackupSources &sources, const PBSSnapshot &snapshot);

struct PbsBackupMatch {
    PBSSnapshot snapshot;
    bool ambiguous = false;
    // Set only when ambiguous: the matching sources, see describePbsSources.
    QString sources;
};

// Human-readable list of where snapshots came from, for tooltips. Grouped by
// datastore in sorted order, root namespace shown as "root":
// "pbs: root, clients/acme; other: archive".
QString describePbsSources(const QList<PBSSnapshot> &snapshots);

// Empty datastore searches all stores. Namespace "*" searches all namespaces;
// empty namespace selects root only. Multiple matching sources are ambiguous,
// even if one has a newer timestamp: they may belong to different clusters.
PbsBackupMatch selectPbsBackup(const PbsBackupSources &sources,
                              const QString &datastore,
                              const QString &backupNamespace);

// Fetch-time narrowing with the same rules as selectPbsBackup: an empty
// datastore keeps every store, "*" keeps every namespace, "" keeps root only
// and any other value keeps that exact namespace. Filters are trimmed and
// compared case-sensitively, so fetching never drops a source selection needs.
QList<QString> filterPbsDatastores(const QList<QString> &datastores, const QString &datastore);
QList<QString> filterPbsNamespaces(const QList<QString> &namespaces, const QString &backupNamespace);

// Namespace list from a PBS /admin/datastore/{store}/namespace response.
// Rows without an "ns" key are malformed and skipped; a row whose "ns" is an
// empty string is the root namespace and is kept. Always returns at least one
// entry: an unusable payload degrades to the root namespace so a datastore
// still yields its root snapshots rather than nothing.
QList<QString> parsePbsNamespaces(const QVariant &response);

QVariantList buildEndpointQueue(const QVariantList &entries, bool defaultIgnoreSsl);
QVariantList responseRows(const QVariant &response, const QVariantMap &context = {});
QVariantList mergeEndpointBuckets(const QVariantList &endpoints, const QVariantMap &buckets);

// Stable-sorts VM/CT rows in place. Modes: "status" (running first, then
// name, then vmid), "statusId" (running first, then vmid), "name",
// "nameDesc", "id", "idDesc", and "custom" (ascending rank from
// guestOrderRanks(), guests without a rank after them by ascending vmid).
// Unknown modes fall back to "status". ranks and scope are only read in
// "custom" mode.
void sortItems(QVariantList &items,
               const QString &mode,
               const QHash<QString, int> &ranks = {},
               const QString &scope = {});

// ---- Custom guest order ("custom" sort mode) ----
// Stored in KConfig as a list of "<host>:<port>/<vmid>" keys. vmids are
// unique across qemu and lxc within one cluster, and the node is left out so
// a guest keeps its place after migration. The stored list is user-editable
// config and is treated as untrusted: every read goes through
// sanitizeGuestOrder().
inline constexpr qsizetype kMaxGuestOrderEntries = 2048;

// "<normalized host>:<port>", or an empty string if the host contains
// characters outside [a-z0-9.-_:[]] or the port is out of range. An empty
// scope disables custom ordering for that cluster.
QString guestOrderScope(const QString &host, int port);
QString guestOrderKey(const QString &scope, int vmid);

// Drops malformed and duplicate keys (first occurrence wins) and keeps at
// most kMaxGuestOrderEntries, discarding the oldest (front) entries.
QStringList sanitizeGuestOrder(const QStringList &order);
QHash<QString, int> guestOrderRanks(const QStringList &order);

// Returns the order after moving sectionKeys[from] to position `to` within
// one displayed section. sectionKeys is the section's current on-screen
// order. The section's keys are removed from `order` and re-appended in
// their new order; other sections keep their relative ranks. Invalid
// indices or keys return sanitizeGuestOrder(order) unchanged.
QStringList applyGuestMove(const QStringList &order,
                           const QStringList &sectionKeys,
                           int from,
                           int to);

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

// Build the Proxmox console WebSocket URL. Shared by the VNC bridge
// (VncWsProxy) and the LXC/node terminal (LxcTerminal) so the two cannot
// drift apart.
//
// Transport encryption is not optional: the scheme is always wss. ignoreSsl
// governs peer verification only and never reaches this function.
//
// kind is the guest type ("qemu", "lxc"). Pass an empty kind for a
// node-level shell, in which case vmid is ignored and the shorter
// /api2/json/nodes/{node}/vncwebsocket path is used.
//
// node and kind are validated rather than encoded: anything outside
// [A-Za-z0-9._-] yields an invalid QUrl instead of reshaping the path.
// The ticket is percent-encoded so base64 '+' survives Proxmox's form-URL
// decoder. Returns an invalid QUrl on any rejected input; callers must
// check isValid() before opening a socket.
QUrl buildConsoleWebSocketUrl(const QString &host,
                              int apiPort,
                              const QString &node,
                              const QString &kind,
                              int vmid,
                              int port,
                              const QByteArray &ticket);

} // namespace ProxmoxDataUtils
