#include "proxmoxcontroller.h"

#include "proxmoxclient.h"
#include "proxmoxconsts.h"
#include "proxmoxdatautils.h"
#include "secretstore.h"

#include <algorithm>
#include <utility>

#include <QDateTime>
#include <QSet>
#include <QDebug>
#include <QHostAddress>
#include <QHostInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QUuid>
#include <QVariantList>
#include <QtGlobal>

ProxmoxController::ProxmoxController(QObject *parent)
    : QObject(parent)
    , m_api(new ProxmoxClient(this))
    , m_singleSecretStore(new SecretStore(this))
    , m_multiSecretStore(new SecretStore(this)) {
    m_singleSecretStore->setService(QStringLiteral("ProxMon"));
    m_multiSecretStore->setService(QStringLiteral("ProxMon"));

    m_nodesModel = new VariantListModel({QStringLiteral("node")}, this);
    m_endpointsModel = new VariantListModel({QStringLiteral("sessionKey")}, this);

    connect(m_api, &ProxmoxClient::statsReady, this,
        [this](const QString &sessionKey, const QString &statsKind, const QString &node, int vmid, const QVariant &data) {
            Q_UNUSED(statsKind)
            emit statsReady(sessionKey, node, vmid, data);
        });
    connect(m_api, &ProxmoxClient::statsError, this,
        [this](const QString &sessionKey, const QString &node, int vmid, const QString &message) {
            emit statsError(sessionKey, node, vmid, message);
        });
    connect(m_api, &ProxmoxClient::reply, this, [this](int seq, const QString &kind, const QString &node, const QVariant &data) {
        handleSingleReply(seq, kind, node, data);
    });
    connect(m_api, &ProxmoxClient::error, this, [this](int seq, const QString &kind, const QString &node, const QString &message) {
        handleSingleError(seq, kind, node, message);
    });
    connect(m_api, &ProxmoxClient::replyFor, this, [this](int seq, const QString &sessionKey, const QString &kind, const QString &node, const QVariant &data) {
        handleMultiReply(seq, sessionKey, kind, node, data);
    });
    connect(m_api, &ProxmoxClient::errorFor, this, [this](int seq, const QString &sessionKey, const QString &kind, const QString &node, const QString &message) {
        handleMultiError(seq, sessionKey, kind, node, message);
    });
    connect(m_api, &ProxmoxClient::actionReply, this, [this](int, const QString &actionKind, const QString &node, int vmid, const QString &action, const QVariant &data) {
        emit actionReply(QString(), actionKind, node, vmid, action, data);
    });
    connect(m_api, &ProxmoxClient::actionError, this, [this](int, const QString &actionKind, const QString &node, int vmid, const QString &action, const QString &message) {
        emit actionError(QString(), actionKind, node, vmid, action, message);
    });
    connect(m_api, &ProxmoxClient::actionReplyFor, this, [this](int, const QString &sessionKey, const QString &actionKind, const QString &node, int vmid, const QString &action, const QVariant &data) {
        emit actionReply(sessionKey, actionKind, node, vmid, action, data);
    });
    connect(m_api, &ProxmoxClient::actionErrorFor, this, [this](int, const QString &sessionKey, const QString &actionKind, const QString &node, int vmid, const QString &action, const QString &message) {
        emit actionError(sessionKey, actionKind, node, vmid, action, message);
    });
    connect(m_api, &ProxmoxClient::vncProxyReady, this, [this](const QString &sessionKey, const QString &requestId, const QString &host, const QString &node, const QString &kind, int vmid, int vncPort, const QString &ticket, int apiPort, const QByteArray &authHeader, bool ignoreSsl) {
        // Resolve per-session overrides (multi-host), falling back to controller-wide settings.
        int resolvedApiPort = apiPort;
        bool resolvedIgnoreSsl = ignoreSsl;
        QString resolvedCertPem = m_trustedCertPem;
        QString resolvedCertPath = m_trustedCertPath;
        if (!sessionKey.isEmpty()) {
            const QVariantMap endpoint = endpointBySession(sessionKey);
            if (!endpoint.isEmpty()) {
                resolvedApiPort    = endpoint.value(QStringLiteral("port"), apiPort).toInt();
                resolvedIgnoreSsl  = endpoint.value(QStringLiteral("ignoreSsl"), ignoreSsl).toBool();
                // Already resolved shared-vs-per-endpoint by readNextMultiSecret().
                resolvedCertPem    = endpoint.value(QStringLiteral("trustedCertPem")).toString();
                resolvedCertPath   = endpoint.value(QStringLiteral("trustedCertPath")).toString();
            }
        }
        const QString vmName = m_pendingConsoleNames.take(requestId);
        discardConsoleCredentials(requestId);
        m_pendingConsoleAuth[requestId] = authHeader;
        m_pendingConsoleTicket[requestId] = ticket.toUtf8();
        emit consoleReady(sessionKey, requestId, host, node, kind, vmid, vmName, vncPort,
                          resolvedApiPort, resolvedIgnoreSsl, resolvedCertPem, resolvedCertPath);
        // Delivery is deliberately synchronous. Anything QML did not consume
        // while handling consoleReady must not remain resident in the registry.
        discardConsoleCredentials(requestId);
    });
    connect(m_api, &ProxmoxClient::vncProxyError, this, [this](const QString &, const QString &requestId, const QString &node, const QString &kind, int vmid, const QString &message) {
        m_pendingConsoleNames.remove(requestId);
        emit consoleError(node, kind, vmid, message);
    });
    connect(m_api, &ProxmoxClient::nodeTermProxyReady, this, [this](const QString &sessionKey, const QString &requestId, const QString &host, const QString &node, int proxyPort, const QString &ticket, const QString &user, const QByteArray &authHeader) {
        int apiPort = m_port;
        bool ignoreSsl = m_ignoreSsl;
        QString certPem = m_trustedCertPem;
        QString certPath = m_trustedCertPath;
        if (!sessionKey.isEmpty()) {
            const QVariantMap endpoint = endpointBySession(sessionKey);
            apiPort   = endpoint.value(QStringLiteral("port"), m_port).toInt();
            ignoreSsl = endpoint.value(QStringLiteral("ignoreSsl"), m_ignoreSsl).toBool();
            certPem   = endpoint.value(QStringLiteral("trustedCertPem"), m_trustedCertPem).toString();
            certPath  = endpoint.value(QStringLiteral("trustedCertPath"), m_trustedCertPath).toString();
        }
        // Node consoles are labelled with the node name directly, but openConsole
        // still stashed a name entry for this request - drain it here too.
        m_pendingConsoleNames.remove(requestId);
        discardConsoleCredentials(requestId);
        m_pendingConsoleAuth[requestId] = authHeader;
        m_pendingConsoleTicket[requestId] = ticket.toUtf8();
        // vmid=0 is the sentinel for node-level console (Proxmox vmids start at 100)
        emit lxcConsoleReady(sessionKey, requestId, host, apiPort, node, 0, node,
                             proxyPort, user, ignoreSsl, certPem, certPath);
        discardConsoleCredentials(requestId);
    });
    connect(m_api, &ProxmoxClient::nodeTermProxyError, this, [this](const QString &, const QString &requestId, const QString &node, const QString &message) {
        m_pendingConsoleNames.remove(requestId);
        emit consoleError(node, ProxmoxConst::Kind::Node, 0, message);
    });
    connect(m_api, &ProxmoxClient::ttyProxyReady, this, [this](const QString &sessionKey, const QString &requestId, const QString &host, const QString &node, int vmid, int proxyPort, const QString &ticket, const QString &user, const QByteArray &authHeader) {
        // Resolve api port + ignoreSsl + vmName: for single-host fall back to
        // the controller-wide settings; for multi-host pull from the endpoint.
        int apiPort = m_port;
        bool ignoreSsl = m_ignoreSsl;
        QString certPem = m_trustedCertPem;
        QString certPath = m_trustedCertPath;
        if (!sessionKey.isEmpty()) {
            const QVariantMap endpoint = endpointBySession(sessionKey);
            apiPort   = endpoint.value(QStringLiteral("port"), m_port).toInt();
            ignoreSsl = endpoint.value(QStringLiteral("ignoreSsl"), m_ignoreSsl).toBool();
            certPem   = endpoint.value(QStringLiteral("trustedCertPem"), m_trustedCertPem).toString();
            certPath  = endpoint.value(QStringLiteral("trustedCertPath"), m_trustedCertPath).toString();
        }
        const QString vmName = m_pendingConsoleNames.take(requestId);
        discardConsoleCredentials(requestId);
        m_pendingConsoleAuth[requestId] = authHeader;
        m_pendingConsoleTicket[requestId] = ticket.toUtf8();
        emit lxcConsoleReady(sessionKey, requestId, host, apiPort, node, vmid, vmName,
                             proxyPort, user, ignoreSsl, certPem, certPath);
        discardConsoleCredentials(requestId);
    });
    connect(m_api, &ProxmoxClient::ttyProxyError, this, [this](const QString &, const QString &requestId, const QString &node, int vmid, const QString &message) {
        m_pendingConsoleNames.remove(requestId);
        emit consoleError(node, ProxmoxConst::Kind::Lxc, vmid, message);
    });
    connect(m_api, &ProxmoxClient::pbsSnapshotsReceived, this, [this](const QString &pbsHost, const QString &, const QList<PBSSnapshot> &snapshots) {
        for (const PBSSnapshot &snapshot : snapshots) {
            const QString backupKey = QStringLiteral("%1|%2|%3").arg(normalizedHost(pbsHost), snapshot.backupType, QString::number(snapshot.vmid));
            auto it = m_latestBackups.find(backupKey);
            if (it == m_latestBackups.end() || snapshot.backupTime > it.value().backupTime) {
                m_latestBackups.insert(backupKey, snapshot);
            }
        }
        if (m_pendingPbsSnapshotRequests > 0) {
            m_pendingPbsSnapshotRequests -= 1;
        }
        checkPBSRequestsComplete();
    });
    connect(m_api, &ProxmoxClient::pbsDatastoresReceived, this, [this](const QString &, const QList<QString> &datastores) {
        if (m_pendingPbsEndpoints > 0) {
            m_pendingPbsEndpoints -= 1;
        }
        m_pendingPbsSnapshotRequests += datastores.size();
        checkPBSRequestsComplete();
    });
    connect(m_api, &ProxmoxClient::pbsDatastoresError, this, [this](const QString &pbsHost, const QString &message) {
        appendDebugLog(QStringLiteral("[ProxmoxController] pbs datastore error host=%1 pendingSnapshots=%2 pendingEndpoints=%3 message=%4")
            .arg(pbsHost)
            .arg(m_pendingPbsSnapshotRequests)
            .arg(m_pendingPbsEndpoints)
            .arg(message));
        if (m_pbsRefreshError != message) {
            m_pbsRefreshError = message;
            emit pbsLastErrorChanged();
        }
        if (m_pendingPbsEndpoints > 0) {
            m_pendingPbsEndpoints -= 1;
        }
        checkPBSRequestsComplete();
    });
    connect(m_api, &ProxmoxClient::pbsSnapshotsError, this, [this](const QString &pbsHost, const QString &datastore, const QString &message) {
        appendDebugLog(QStringLiteral("[ProxmoxController] pbs snapshot error host=%1 datastore=%2 pendingSnapshots=%3 pendingEndpoints=%4 message=%5")
            .arg(pbsHost, datastore)
            .arg(m_pendingPbsSnapshotRequests)
            .arg(m_pendingPbsEndpoints)
            .arg(message));
        if (m_pbsRefreshError != message) {
            m_pbsRefreshError = message;
            emit pbsLastErrorChanged();
        }
        if (m_pendingPbsSnapshotRequests > 0) {
            m_pendingPbsSnapshotRequests -= 1;
        }
        checkPBSRequestsComplete();
    });
    m_pbsTimer = new QTimer(this);
    connect(m_pbsTimer, &QTimer::timeout, this, &ProxmoxController::refreshPBSNow);
    m_pbsTimer->setInterval(m_pbsRefreshInterval * 1000);
    m_pbsDebounceTimer = new QTimer(this);
    m_pbsDebounceTimer->setSingleShot(true);
    m_pbsDebounceTimer->setInterval(500);
    connect(m_pbsDebounceTimer, &QTimer::timeout, this, &ProxmoxController::refreshPBSNow);

    // Auto-retry: scheduleRetry() computes the backoff and arms this timer;
    // the timeout performs the actual retry. resetRetryState() disarms it.
    m_retryTimer = new QTimer(this);
    m_retryTimer->setSingleShot(true);
    connect(m_retryTimer, &QTimer::timeout, this, [this]() {
        appendDebugLog(QStringLiteral("[ProxmoxController] auto-retry firing attempt=%1").arg(QString::number(m_retryAttempt)));
        fetchData();
    });

    connect(m_singleSecretStore, &SecretStore::keysReady, this, [this](const QStringList &keys) {
        if (keys.isEmpty()) {
            return;
        }

        const bool hasCoreConfig = (m_connectionMode == QStringLiteral("multiHost"))
            ? !parseMultiHosts().isEmpty()
            : (!m_host.isEmpty() && !m_tokenId.isEmpty());
        if (hasCoreConfig) {
            return;
        }

        if (keys.size() == 1) {
            const QVariantMap parsed = parseKeyEntry(keys.first());
            if (!parsed.isEmpty()) {
                emit restoreSingleConfigRequested(parsed.value(QStringLiteral("host")).toString(),
                                                  parsed.value(QStringLiteral("port")).toInt(),
                                                  parsed.value(QStringLiteral("tokenId")).toString());
            }
            return;
        }

        const QVariantList entries = parseKeyEntries(keys);
        if (entries.size() > 1) {
            QJsonArray array;
            for (const QVariant &entry : entries) {
                array.append(QJsonObject::fromVariantMap(entry.toMap()));
            }
            emit restoreMultiHostConfigRequested(QString::fromUtf8(QJsonDocument(array).toJson(QJsonDocument::Compact)));
        }
    });

    connect(m_singleSecretStore, &SecretStore::keyListError, this, &ProxmoxController::keyListError);

}

ProxmoxController::~ProxmoxController() {
    if (m_api) {
        m_api->cancelAll();
    }
    clearPendingConsoleCredentials();
}

void ProxmoxController::setConnectionMode(const QString &value) {
    if (m_connectionMode == value) return;
    cancelRefresh();
    resetTransientStateForModeChange();
    m_connectionMode = value;
    emit connectionModeChanged();
}

void ProxmoxController::setHost(const QString &value) {
    if (m_host == value) return;
    m_host = value;
    emit hostChanged();
}

void ProxmoxController::setPort(int value) {
    if (m_port == value) return;
    m_port = value;
    emit portChanged();
}

void ProxmoxController::setTokenId(const QString &value) {
    if (m_tokenId == value) return;
    m_tokenId = value;
    emit tokenIdChanged();
}

void ProxmoxController::setTrustedCertPem(const QString &value) {
    if (m_trustedCertPem == value) return;
    m_trustedCertPem = value;
    emit trustedCertPemChanged();
}

void ProxmoxController::setTrustedCertPath(const QString &value) {
    if (m_trustedCertPath == value) return;
    m_trustedCertPath = value;
    emit trustedCertPathChanged();
}

void ProxmoxController::setMultiHostsJson(const QString &value) {
    if (m_multiHostsJson == value) return;
    m_multiHostsJson = value;
    emit multiHostsJsonChanged();
    refreshPBS();
}

void ProxmoxController::setPbsEnabled(bool value) {
    if (m_pbsEnabled == value) return;
    m_pbsEnabled = value;
    emit pbsEnabledChanged();
    refreshPBS();
}

void ProxmoxController::setPbsHost(const QString &value) {
    if (m_pbsHost == value) return;
    m_pbsHost = value;
    emit pbsHostChanged();
    refreshPBS();
}

void ProxmoxController::setPbsPort(int value) {
    if (m_pbsPort == value) return;
    m_pbsPort = value;
    emit pbsPortChanged();
    refreshPBS();
}

void ProxmoxController::setPbsTokenId(const QString &value) {
    if (m_pbsTokenId == value) return;
    m_pbsTokenId = value;
    emit pbsTokenIdChanged();
    refreshPBS();
}

void ProxmoxController::setPbsIgnoreSsl(bool value) {
    if (m_pbsIgnoreSsl == value) return;
    m_pbsIgnoreSsl = value;
    emit pbsIgnoreSslChanged();
    refreshPBS();
}

void ProxmoxController::setPbsBackupWarningDays(int value) {
    if (m_pbsBackupWarningDays == value) return;
    m_pbsBackupWarningDays = value;
    emit pbsBackupWarningDaysChanged();
}

void ProxmoxController::setPbsBackupStaleDays(int value) {
    if (m_pbsBackupStaleDays == value) return;
    m_pbsBackupStaleDays = value;
    emit pbsBackupStaleDaysChanged();
}

void ProxmoxController::setPbsRefreshInterval(int value) {
    if (m_pbsRefreshInterval == value) return;
    m_pbsRefreshInterval = value;
    if (m_pbsTimer) {
        m_pbsTimer->setInterval(m_pbsRefreshInterval * 1000);
    }
    emit pbsRefreshIntervalChanged();
}

void ProxmoxController::setPbsExcludeTag(const QString &value) {
    if (m_pbsExcludeTag == value) return;
    m_pbsExcludeTag = value;
    emit pbsExcludeTagChanged();
    correlateBackups();
}

void ProxmoxController::setPbsExcludeVmids(const QString &value) {
    if (m_pbsExcludeVmids == value) return;
    m_pbsExcludeVmids = value;
    emit pbsExcludeVmidsChanged();
    correlateBackups();
}

void ProxmoxController::setDebugEnabled(bool value) {
    if (m_debugEnabled == value) return;
    m_debugEnabled = value;
    m_api->setDebugEnabled(value);
    emit debugEnabledChanged();
}

void ProxmoxController::setIgnoreSsl(bool value) {
    if (m_ignoreSsl == value) return;
    m_ignoreSsl = value;
    emit ignoreSslChanged();
}

void ProxmoxController::setLowLatency(bool value) {
    if (m_lowLatency == value) return;
    m_lowLatency = value;
    m_api->setLowLatency(value);
    emit lowLatencyChanged();
}

void ProxmoxController::setDefaultSorting(const QString &value) {
    if (m_defaultSorting == value) return;
    m_defaultSorting = value;
    emit defaultSortingChanged();
    // Re-publish so the submodels re-sort; diffing turns this into row moves.
    // No-op while the popup is collapsed; the catch-up publish in
    // setViewActive() re-sorts from m_defaultSorting on the next expand.
    publishSingleHostModels();
    publishMultiHostModels();
}

void ProxmoxController::setViewActive(bool value) {
    if (m_viewActive == value) return;
    m_viewActive = value;
    emit viewActiveChanged();
    // Became visible: catch the models up from the latest displayed data.
    // Each publish no-ops in the wrong connection mode.
    if (value) {
        publishSingleHostModels();
        publishMultiHostModels();
    }
}

/*  Publish the current single-host displayed data into the delegate-facing
    models. Idempotent and diff-based: calling it with unchanged data emits
    nothing. Called after every refresh completes and after PBS correlation
    rewrites backup fields.
*/
void ProxmoxController::publishSingleHostModels() {
    if (!m_viewActive || m_connectionMode != QStringLiteral("single")) return;

    const QVariantList nodes = m_displayedProxmoxData.toMap().value(QStringLiteral("data")).toList();

    // Group children by node, sorted once in C++ (QML no longer sorts).
    QHash<QString, QVariantList> vmsByNode;
    for (const QVariant &vmValue : m_displayedVmData) {
        vmsByNode[vmValue.toMap().value(QStringLiteral("node")).toString()].push_back(vmValue);
    }
    QHash<QString, QVariantList> lxcsByNode;
    for (const QVariant &lxcValue : m_displayedLxcData) {
        lxcsByNode[lxcValue.toMap().value(QStringLiteral("node")).toString()].push_back(lxcValue);
    }

    QVariantList nodeRows;
    nodeRows.reserve(nodes.size());
    QSet<QString> liveNodes;
    for (const QVariant &nodeValue : nodes) {
        QVariantMap row = nodeValue.toMap();
        const QString nodeName = row.value(QStringLiteral("node")).toString();
        if (nodeName.isEmpty()) continue;
        liveNodes.insert(nodeName);

        VariantListModel *vmModel = m_vmModelsByNode.value(nodeName);
        if (!vmModel) {
            vmModel = new VariantListModel({QStringLiteral("node"), QStringLiteral("vmid")}, this);
            m_vmModelsByNode.insert(nodeName, vmModel);
        }
        VariantListModel *lxcModel = m_lxcModelsByNode.value(nodeName);
        if (!lxcModel) {
            lxcModel = new VariantListModel({QStringLiteral("node"), QStringLiteral("vmid")}, this);
            m_lxcModelsByNode.insert(nodeName, lxcModel);
        }

        QVariantList vms = vmsByNode.value(nodeName);
        ProxmoxDataUtils::sortItems(vms, m_defaultSorting);
        vmModel->applyItems(vms);

        QVariantList lxcs = lxcsByNode.value(nodeName);
        ProxmoxDataUtils::sortItems(lxcs, m_defaultSorting);
        lxcModel->applyItems(lxcs);

        // INVARIANT: submodel pointers must stay stable across refreshes and
        // must be stored as QObject* (QMetaType::QObjectStar compares by
        // address). Recreating models per refresh, or storing them as
        // VariantListModel*, would make every node row compare unequal and
        // silently reintroduce per-poll delegate churn. Pinned by
        // tst_variantlistmodel objectPointerValues_compareByIdentity.
        row.insert(QStringLiteral("vmsModel"), QVariant::fromValue<QObject *>(vmModel));
        row.insert(QStringLiteral("lxcsModel"), QVariant::fromValue<QObject *>(lxcModel));
        nodeRows.push_back(row);
    }

    // Remove vanished nodes' rows first (delegates release the submodels),
    // then drop the submodels.
    m_nodesModel->applyItems(nodeRows);
    for (auto it = m_vmModelsByNode.begin(); it != m_vmModelsByNode.end();) {
        if (!liveNodes.contains(it.key())) {
            it.value()->deleteLater();
            it = m_vmModelsByNode.erase(it);
        } else {
            ++it;
        }
    }
    for (auto it = m_lxcModelsByNode.begin(); it != m_lxcModelsByNode.end();) {
        if (!liveNodes.contains(it.key())) {
            it.value()->deleteLater();
            it = m_lxcModelsByNode.erase(it);
        } else {
            ++it;
        }
    }
}

void ProxmoxController::clearSingleHostModels() {
    if (m_nodesModel) {
        m_nodesModel->clear();
    }
    for (VariantListModel *model : std::as_const(m_vmModelsByNode)) {
        model->deleteLater();
    }
    m_vmModelsByNode.clear();
    for (VariantListModel *model : std::as_const(m_lxcModelsByNode)) {
        model->deleteLater();
    }
    m_lxcModelsByNode.clear();
}

/*  Multi-host mirror of publishSingleHostModels(), one level deeper:
    endpoints -> nodes -> vms/lxcs. Child keys keep sessionKey so the same
    node name (or vmid) behind two endpoints stays distinct; this matches
    the old JS dedupe in getVmsForNodeMulti, which keyed per endpoint.
    Same stable-pointer invariant as the single-host publish applies to
    "nodesModel" on endpoint rows and "vmsModel"/"lxcsModel" on node rows.

    Endpoint rows deliberately do NOT carry the nested nodes/vms/lxcs lists
    from m_displayedEndpoints: delegates read those through the submodels,
    and stripping them keeps row comparison cheap and quiet.
*/
void ProxmoxController::publishMultiHostModels() {
    if (!m_viewActive || m_connectionMode != QStringLiteral("multiHost")) return;

    QVariantList endpointRows;
    endpointRows.reserve(m_displayedEndpoints.size());
    QSet<QString> liveSessions;
    QSet<QString> liveNodeKeys;

    for (const QVariant &endpointValue : m_displayedEndpoints) {
        const QVariantMap endpoint = endpointValue.toMap();
        const QString sessionKey = endpoint.value(QStringLiteral("sessionKey")).toString();
        if (sessionKey.isEmpty()) continue;
        liveSessions.insert(sessionKey);

        VariantListModel *nodesModel = m_nodesModelsBySession.value(sessionKey);
        if (!nodesModel) {
            nodesModel = new VariantListModel({QStringLiteral("sessionKey"), QStringLiteral("node")}, this);
            m_nodesModelsBySession.insert(sessionKey, nodesModel);
        }

        // Group this endpoint's children by node, sorted once in C++.
        QHash<QString, QVariantList> vmsByNode;
        for (const QVariant &vmValue : endpoint.value(QStringLiteral("vms")).toList()) {
            vmsByNode[vmValue.toMap().value(QStringLiteral("node")).toString()].push_back(vmValue);
        }
        QHash<QString, QVariantList> lxcsByNode;
        for (const QVariant &lxcValue : endpoint.value(QStringLiteral("lxcs")).toList()) {
            lxcsByNode[lxcValue.toMap().value(QStringLiteral("node")).toString()].push_back(lxcValue);
        }

        QVariantList nodeRows;
        const QVariantList nodes = endpoint.value(QStringLiteral("nodes")).toList();
        nodeRows.reserve(nodes.size());
        for (const QVariant &nodeValue : nodes) {
            QVariantMap nodeRow = nodeValue.toMap();
            const QString nodeName = nodeRow.value(QStringLiteral("node")).toString();
            if (nodeName.isEmpty()) continue;
            const QString nodeKey = sessionKey + QLatin1Char('|') + nodeName;
            liveNodeKeys.insert(nodeKey);

            VariantListModel *vmModel = m_vmModelsBySessionNode.value(nodeKey);
            if (!vmModel) {
                vmModel = new VariantListModel({QStringLiteral("sessionKey"), QStringLiteral("node"), QStringLiteral("vmid")}, this);
                m_vmModelsBySessionNode.insert(nodeKey, vmModel);
            }
            VariantListModel *lxcModel = m_lxcModelsBySessionNode.value(nodeKey);
            if (!lxcModel) {
                lxcModel = new VariantListModel({QStringLiteral("sessionKey"), QStringLiteral("node"), QStringLiteral("vmid")}, this);
                m_lxcModelsBySessionNode.insert(nodeKey, lxcModel);
            }

            QVariantList vms = vmsByNode.value(nodeName);
            ProxmoxDataUtils::sortItems(vms, m_defaultSorting);
            vmModel->applyItems(vms);

            QVariantList lxcs = lxcsByNode.value(nodeName);
            ProxmoxDataUtils::sortItems(lxcs, m_defaultSorting);
            lxcModel->applyItems(lxcs);

            nodeRow.insert(QStringLiteral("sessionKey"), sessionKey);
            nodeRow.insert(QStringLiteral("vmsModel"), QVariant::fromValue<QObject *>(vmModel));
            nodeRow.insert(QStringLiteral("lxcsModel"), QVariant::fromValue<QObject *>(lxcModel));
            nodeRows.push_back(nodeRow);
        }
        nodesModel->applyItems(nodeRows);

        QVariantMap endpointRow{
            {QStringLiteral("sessionKey"), sessionKey},
            {QStringLiteral("label"), endpoint.value(QStringLiteral("label"))},
            {QStringLiteral("host"), endpoint.value(QStringLiteral("host"))},
            {QStringLiteral("port"), endpoint.value(QStringLiteral("port"))},
            {QStringLiteral("error"), endpoint.value(QStringLiteral("error"))},
            {QStringLiteral("offline"), endpoint.value(QStringLiteral("offline"))},
            {QStringLiteral("nodesModel"), QVariant::fromValue<QObject *>(nodesModel)},
        };
        endpointRows.push_back(endpointRow);
    }

    // Remove vanished rows first (delegates release the submodels), then
    // drop the submodels themselves.
    m_endpointsModel->applyItems(endpointRows);
    for (auto it = m_nodesModelsBySession.begin(); it != m_nodesModelsBySession.end();) {
        if (!liveSessions.contains(it.key())) {
            it.value()->deleteLater();
            it = m_nodesModelsBySession.erase(it);
        } else {
            ++it;
        }
    }
    for (auto it = m_vmModelsBySessionNode.begin(); it != m_vmModelsBySessionNode.end();) {
        if (!liveNodeKeys.contains(it.key())) {
            it.value()->deleteLater();
            it = m_vmModelsBySessionNode.erase(it);
        } else {
            ++it;
        }
    }
    for (auto it = m_lxcModelsBySessionNode.begin(); it != m_lxcModelsBySessionNode.end();) {
        if (!liveNodeKeys.contains(it.key())) {
            it.value()->deleteLater();
            it = m_lxcModelsBySessionNode.erase(it);
        } else {
            ++it;
        }
    }
}

void ProxmoxController::clearMultiHostModels() {
    if (m_endpointsModel) {
        m_endpointsModel->clear();
    }
    for (VariantListModel *model : std::as_const(m_nodesModelsBySession)) {
        model->deleteLater();
    }
    m_nodesModelsBySession.clear();
    for (VariantListModel *model : std::as_const(m_vmModelsBySessionNode)) {
        model->deleteLater();
    }
    m_vmModelsBySessionNode.clear();
    for (VariantListModel *model : std::as_const(m_lxcModelsBySessionNode)) {
        model->deleteLater();
    }
    m_lxcModelsBySessionNode.clear();
}

QString ProxmoxController::pbsKeyForHost(const QString &host) const {
    return QStringLiteral("proxmon-pbs-%1").arg(normalizedHost(host));
}

void ProxmoxController::resolveSecretsIfNeeded() {
    const bool hasCoreConfig = (m_connectionMode == QStringLiteral("multiHost"))
        ? !parseMultiHosts().isEmpty()
        : (!m_host.isEmpty() && !m_tokenId.isEmpty());
    appendDebugLog(QStringLiteral("[ProxmoxController] resolveSecretsIfNeeded mode=%1 hasCoreConfig=%2 host=%3 tokenIdEmpty=%4")
        .arg(m_connectionMode, hasCoreConfig ? QStringLiteral("true") : QStringLiteral("false"), m_host, m_tokenId.isEmpty() ? QStringLiteral("true") : QStringLiteral("false")));

    if (!hasCoreConfig) {
        m_secretResolutionGeneration += 1;
        m_activeSingleSecretKey.clear();
        m_activeMultiSecretRequest.clear();
        setEndpoints({});
        setRefreshResolvingSecrets(false);
        setSecretState(QStringLiteral("idle"));
        return;
    }

    if (m_connectionMode == QStringLiteral("multiHost")) {
        startMultiSecretResolution();
        return;
    }

    if (m_secretState == QStringLiteral("loading")) {
        return;
    }

    setSecretState(QStringLiteral("loading"));
    startSecretRead();
}

void ProxmoxController::listStoredKeys() {
    m_singleSecretStore->listKWalletKeys();
}

void ProxmoxController::storeSingleSecret(const QString &secret) {
    if (secret.trimmed().isEmpty() || m_host.trimmed().isEmpty() || m_tokenId.trimmed().isEmpty()) {
        return;
    }
    m_singleSecretStore->setKey(keyFor(m_host, m_port, m_tokenId));
    m_singleSecretStore->writeSecret(secret);
}

void ProxmoxController::storeSinglePBSSecret(const QString &host, const QString &secret) {
    const QString key = pbsKeyForHost(host);
    appendDebugLog(QStringLiteral("[ProxmoxController] storeSinglePBSSecret host=%1 key=%2 secretEmpty=%3")
        .arg(host, key, secret.trimmed().isEmpty() ? QStringLiteral("true") : QStringLiteral("false")));
    if (secret.trimmed().isEmpty() || host.trimmed().isEmpty()) {
        return;
    }
    m_singleSecretStore->setKey(key);
    m_singleSecretStore->writeSecret(secret);
}

void ProxmoxController::storeMultiHostSecret(const QString &host, int port, const QString &tokenId, const QString &secret) {
    if (secret.trimmed().isEmpty() || host.trimmed().isEmpty() || tokenId.trimmed().isEmpty()) {
        return;
    }
    m_multiSecretStore->setKey(keyFor(host, port, tokenId));
    m_multiSecretStore->writeSecret(secret);
}

void ProxmoxController::storeMultiHostPBSSecret(const QString &host, const QString &secret) {
    const QString key = pbsKeyForHost(host);
    appendDebugLog(QStringLiteral("[ProxmoxController] storeMultiHostPBSSecret host=%1 key=%2 secretEmpty=%3")
        .arg(host, key, secret.trimmed().isEmpty() ? QStringLiteral("true") : QStringLiteral("false")));
    if (secret.trimmed().isEmpty() || host.trimmed().isEmpty()) {
        return;
    }
    m_multiSecretStore->setKey(key);
    m_multiSecretStore->writeSecret(secret);
}

void ProxmoxController::setAutoRetry(bool value) {
    if (m_autoRetry == value) return;
    m_autoRetry = value;
    emit autoRetryChanged();
}

void ProxmoxController::setRetryStartMs(int value) {
    if (m_retryStartMs == value) return;
    m_retryStartMs = value;
    emit retryStartMsChanged();
}

void ProxmoxController::setRetryMaxMs(int value) {
    if (m_retryMaxMs == value) return;
    m_retryMaxMs = value;
    emit retryMaxMsChanged();
}

void ProxmoxController::fetchData() {
    const bool hasCoreConfig = (m_connectionMode == QStringLiteral("multiHost"))
        ? !parseMultiHosts().isEmpty()
        : (!m_host.isEmpty() && !m_tokenId.isEmpty());
    appendDebugLog(QStringLiteral("[ProxmoxController] fetchData mode=%1 hasCoreConfig=%2 secretState=%3 endpoints=%4")
        .arg(m_connectionMode, hasCoreConfig ? QStringLiteral("true") : QStringLiteral("false"), m_secretState, QString::number(m_endpoints.size())));
    if (!hasCoreConfig) {
        return;
    }

    if (m_connectionMode == QStringLiteral("multiHost")) {
        const bool needsMultiSecrets = m_endpoints.isEmpty();
        if (m_secretState != QStringLiteral("ready") || needsMultiSecrets) {
            setRefreshResolvingSecrets(true);
            startMultiSecretResolution();
            return;
        }
    } else {
        if (m_secretState != QStringLiteral("ready")) {
            setRefreshResolvingSecrets(true);
            resolveSecretsIfNeeded();
            return;
        }
    }

    cancelRefresh();
    m_refreshSeq += 1;

    const bool isInitial = (m_connectionMode == QStringLiteral("multiHost"))
        ? m_displayedEndpoints.isEmpty()
        : !m_displayedProxmoxData.isValid() || m_displayedProxmoxData.isNull();

    if (isInitial) {
        setLoading(true);
    } else {
        setIsRefreshing(true);
    }

    m_pendingNodeRequests = 0;
    m_tempVmData.clear();
    m_tempLxcData.clear();
    setErrorMessage(QString());
    setPartialFailure(false);
    resetMultiTempData();

    if (m_connectionMode == QStringLiteral("multiHost")) {
        m_pendingNodeRequests = m_endpoints.size();
            for (const QVariant &endpointValue : m_endpoints) {
            const QVariantMap endpoint = endpointValue.toMap();
            readMultiSecretFor({
                {QStringLiteral("kind"), ProxmoxConst::Kind::Nodes},
                {QStringLiteral("sessionKey"), endpoint.value(QStringLiteral("sessionKey")).toString()},
                {QStringLiteral("seq"), m_refreshSeq},
            });
        }
        return;
    }

    readSingleSecretFor({
        {QStringLiteral("kind"), ProxmoxConst::Kind::Fetch},
        {QStringLiteral("seq"), m_refreshSeq},
    });
}

void ProxmoxController::cancelRefresh() {
    m_api->cancelRefreshRequests();
    m_pendingNodeRequests = 0;
    // Explicit refreshes (manual, config change, retry timer fire) supersede
    // any pending auto-retry; a failed attempt re-arms via scheduleRetry().
    if (m_retryTimer) {
        m_retryTimer->stop();
    }
}

bool ProxmoxController::runAction(const QString &sessionKey,
                                  const QString &kind,
                                  const QString &node,
                                  int vmid,
                                  const QString &action) {
    if (sessionKey.isEmpty()) {
        readSingleSecretFor({
            {QStringLiteral("kind"), ProxmoxConst::Kind::Action},
            {QStringLiteral("actionKind"), kind},
            {QStringLiteral("node"), node},
            {QStringLiteral("vmid"), vmid},
            {QStringLiteral("action"), action},
        });
        return true;
    }

    const QVariantMap endpoint = endpointBySession(sessionKey);
    if (endpoint.isEmpty()) {
        emit actionError(sessionKey, kind, node, vmid, action, QStringLiteral("Action failed: endpoint not found"));
        return false;
    }

    readMultiSecretFor({
        {QStringLiteral("kind"), ProxmoxConst::Kind::Action},
        {QStringLiteral("sessionKey"), sessionKey},
        {QStringLiteral("actionKind"), kind},
        {QStringLiteral("node"), node},
        {QStringLiteral("vmid"), vmid},
        {QStringLiteral("action"), action},
    });
    return true;
}

void ProxmoxController::fetchStats(const QString &sessionKey,
                                   const QString &kind,
                                   const QString &node,
                                   int vmid) {
    if (sessionKey.isEmpty()) {
        readSingleSecretFor({
            {QStringLiteral("kind"), ProxmoxConst::Kind::Stats},
            {QStringLiteral("sessionKey"), sessionKey},
            {QStringLiteral("statsKind"), kind},
            {QStringLiteral("node"), node},
            {QStringLiteral("vmid"), vmid},
        });
        return;
    }

    // Multi-host stats dispatch isn't wired yet - readMultiSecretFor has no
    // Kind::Stats branch. Report clearly instead of silently doing nothing.
    emit statsError(sessionKey, node, vmid, QStringLiteral("Multi-host stats not yet supported"));
}

void ProxmoxController::deliverConsoleAuth(const QString &requestId, QObject *target)
{
    auto it = m_pendingConsoleAuth.find(requestId);
    if (it == m_pendingConsoleAuth.end() || !target) return;
    QByteArray header = it.value();
    it.value().fill(0);
    m_pendingConsoleAuth.erase(it);
    QMetaObject::invokeMethod(target, "setAuthHeaderSecure",
                              Qt::DirectConnection,
                              Q_ARG(QByteArray, header));
    header.fill(0);
}

void ProxmoxController::deliverConsoleTicket(const QString &requestId,
                                              QObject *primary,
                                              QObject *secondary)
{
    auto it = m_pendingConsoleTicket.find(requestId);
    if (it == m_pendingConsoleTicket.end() || !primary) return;
    QByteArray ticket = it.value();
    it.value().fill(0);
    m_pendingConsoleTicket.erase(it);
    QMetaObject::invokeMethod(primary, "setTicketSecure",
                              Qt::DirectConnection,
                              Q_ARG(QByteArray, ticket));
    if (secondary) {
        QMetaObject::invokeMethod(secondary, "setTicketSecure",
                                  Qt::DirectConnection,
                                  Q_ARG(QByteArray, ticket));
    }
    ticket.fill(0);
}

void ProxmoxController::discardConsoleCredentials(const QString &requestId)
{
    auto authIt = m_pendingConsoleAuth.find(requestId);
    if (authIt != m_pendingConsoleAuth.end()) {
        authIt.value().fill(0);
        m_pendingConsoleAuth.erase(authIt);
    }

    auto ticketIt = m_pendingConsoleTicket.find(requestId);
    if (ticketIt != m_pendingConsoleTicket.end()) {
        ticketIt.value().fill(0);
        m_pendingConsoleTicket.erase(ticketIt);
    }
}

void ProxmoxController::clearPendingConsoleCredentials()
{
    for (QByteArray &authHeader : m_pendingConsoleAuth) {
        authHeader.fill(0);
    }
    m_pendingConsoleAuth.clear();

    for (QByteArray &ticket : m_pendingConsoleTicket) {
        ticket.fill(0);
    }
    m_pendingConsoleTicket.clear();
}

void ProxmoxController::openConsole(const QString &sessionKey,
                                     const QString &kind,
                                     const QString &node,
                                     int vmid,
                                     const QString &vmName)
{
    const QString requestId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    if (sessionKey.isEmpty()) {
        readSingleSecretFor({
            {QStringLiteral("kind"), ProxmoxConst::Kind::Console},
            {QStringLiteral("requestId"), requestId},
            {QStringLiteral("actionKind"), kind},
            {QStringLiteral("node"), node},
            {QStringLiteral("vmid"), vmid},
            {QStringLiteral("vmName"), vmName},
        });
        return;
    }
    const QVariantMap endpoint = endpointBySession(sessionKey);
    if (endpoint.isEmpty()) {
        emit consoleError(node, kind, vmid, QStringLiteral("Endpoint not found"));
        return;
    }
    readMultiSecretFor({
        {QStringLiteral("kind"), ProxmoxConst::Kind::Console},
        {QStringLiteral("requestId"), requestId},
        {QStringLiteral("sessionKey"), sessionKey},
        {QStringLiteral("actionKind"), kind},
        {QStringLiteral("node"), node},
        {QStringLiteral("vmid"), vmid},
        {QStringLiteral("vmName"), vmName},
    });
}

void ProxmoxController::setSecretState(const QString &value) {
    if (m_secretState == value) return;
    appendDebugLog(QStringLiteral("[ProxmoxController] secretState %1 -> %2").arg(m_secretState, value));
    m_secretState = value;
    emit secretStateChanged();
}

void ProxmoxController::setLoading(bool value) {
    if (m_loading == value) return;
    m_loading = value;
    emit loadingChanged();
}

void ProxmoxController::setIsRefreshing(bool value) {
    if (m_isRefreshing == value) return;
    m_isRefreshing = value;
    emit isRefreshingChanged();
}

void ProxmoxController::setErrorMessage(const QString &value) {
    if (m_errorMessage == value) return;
    m_errorMessage = value;
    emit errorMessageChanged();
}

void ProxmoxController::setLastUpdate(const QString &value) {
    if (m_lastUpdate == value) return;
    m_lastUpdate = value;
    emit lastUpdateChanged();
}

void ProxmoxController::setPartialFailure(bool value) {
    if (m_partialFailure == value) return;
    m_partialFailure = value;
    emit partialFailureChanged();
}

void ProxmoxController::setRetryAttempt(int value) {
    if (m_retryAttempt == value) return;
    m_retryAttempt = value;
    emit retryAttemptChanged();
}

void ProxmoxController::setRetryNextDelayMs(int value) {
    if (m_retryNextDelayMs == value) return;
    m_retryNextDelayMs = value;
    emit retryNextDelayMsChanged();
}

void ProxmoxController::setRetryStatusText(const QString &value) {
    if (m_retryStatusText == value) return;
    m_retryStatusText = value;
    emit retryStatusTextChanged();
}

void ProxmoxController::setDisplayedProxmoxData(const QVariant &value) {
    if (m_displayedProxmoxData == value) return;
    m_displayedProxmoxData = value;
    emit displayedProxmoxDataChanged();
}

void ProxmoxController::setDisplayedVmData(const QVariantList &value) {
    if (m_displayedVmData == value) return;
    m_displayedVmData = value;
    emit displayedVmDataChanged();
    emit runningVMsChanged();
}

void ProxmoxController::setDisplayedLxcData(const QVariantList &value) {
    if (m_displayedLxcData == value) return;
    m_displayedLxcData = value;
    emit displayedLxcDataChanged();
    emit runningLXCChanged();
}

void ProxmoxController::setDisplayedEndpoints(const QVariantList &value) {
    if (m_displayedEndpoints == value) return;
    m_displayedEndpoints = value;
    emit displayedEndpointsChanged();
}

void ProxmoxController::setDisplayedNodeList(const QVariantList &value) {
    if (m_displayedNodeList == value) return;
    m_displayedNodeList = value;
    emit displayedNodeListChanged();
}

void ProxmoxController::resetRetryState() {
    if (m_retryTimer) {
        m_retryTimer->stop();
    }
    setRetryAttempt(0);
    setRetryNextDelayMs(0);
    setRetryStatusText(QString());
}

void ProxmoxController::scheduleRetry(const QString &reason) {
    if (!m_autoRetry) return;
    setRetryAttempt(m_retryAttempt + 1);
    int delay = int(m_retryStartMs * qPow(2.0, m_retryAttempt - 1));
    delay = qMin(delay, m_retryMaxMs);
    setRetryNextDelayMs(delay);
    setRetryStatusText(QStringLiteral("Retrying in %1s…").arg(qRound(double(delay) / 1000.0)));
    if (m_retryTimer) {
        m_retryTimer->start(delay);
    }
    Q_UNUSED(reason)
}

int ProxmoxController::runningVMs() const {
    int count = 0;
    for (const QVariant &item : m_displayedVmData) {
        if (item.toMap().value(QStringLiteral("status")).toString() == ProxmoxConst::Status::Running) count++;
    }
    return count;
}

int ProxmoxController::runningLXC() const {
    int count = 0;
    for (const QVariant &item : m_displayedLxcData) {
        if (item.toMap().value(QStringLiteral("status")).toString() == ProxmoxConst::Status::Running) count++;
    }
    return count;
}

void ProxmoxController::setRefreshResolvingSecrets(bool value) {
    if (m_refreshResolvingSecrets == value) return;
    m_refreshResolvingSecrets = value;
    emit refreshResolvingSecretsChanged();
}

void ProxmoxController::setEndpoints(const QVariantList &value) {
    if (m_endpoints == value) return;
    m_endpoints = value;
    emit endpointsChanged();
}

QString ProxmoxController::sanitizeDebugString(const QString &value) const {
    QString sanitized = value;
    static const auto caseInsensitive = QRegularExpression::CaseInsensitiveOption;
    static const QRegularExpression reAuthorization(
        QStringLiteral("(Authorization\\s*[:=]\\s*)[^\\r\\n]+"), caseInsensitive);
    static const QRegularExpression reApiToken(
        QStringLiteral("((?:PVE|PBS)APIToken\\s*=\\s*)[^\\s,;]+"), caseInsensitive);
    static const QRegularExpression reSecretField(
        QStringLiteral("((?:apiTokenSecret|tokenSecret|secret|password)\\s*[:=]\\s*)[^\\s,;]+"),
        caseInsensitive);
    static const QRegularExpression reTicketField(
        QStringLiteral("((?:vncTicket|ticket)\\s*[:=]\\s*)[^\\s,;]+"), caseInsensitive);
    static const QRegularExpression reUrlCredentials(
        QStringLiteral("([A-Za-z][A-Za-z0-9+.-]*://)[^/@\\s]+@"));
    static const QRegularExpression reUserRealm(QStringLiteral("([A-Za-z0-9._-]+)@([A-Za-z0-9._-]+)"));
    static const QRegularExpression reTokenId(QStringLiteral("!([A-Za-z0-9._:-]+)"));

    sanitized.replace(reAuthorization, QStringLiteral("\\1REDACTED"));
    sanitized.replace(reApiToken, QStringLiteral("\\1REDACTED"));
    sanitized.replace(reSecretField, QStringLiteral("\\1REDACTED"));
    sanitized.replace(reTicketField, QStringLiteral("\\1REDACTED"));
    sanitized.replace(reUrlCredentials, QStringLiteral("\\1REDACTED@"));
    if (!m_host.isEmpty()) {
        sanitized.replace(m_host, QStringLiteral("REDACTED_HOST"), Qt::CaseInsensitive);
    }
    if (!m_pbsHost.isEmpty()) {
        sanitized.replace(m_pbsHost, QStringLiteral("REDACTED_PBS_HOST"), Qt::CaseInsensitive);
    }
    if (!m_tokenId.isEmpty()) {
        sanitized.replace(m_tokenId, QStringLiteral("REDACTED_TOKEN"));
    }
    sanitized.replace(reUserRealm, QStringLiteral("REDACTED@\\2"));
    sanitized.replace(reTokenId, QStringLiteral("!REDACTED"));
    return sanitized;
}

void ProxmoxController::appendDebugLog(const QString &message) {
    if (!m_debugEnabled) return;

    constexpr bool debugLogToJournal = true;
    const QString timestamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd hh:mm:ss.zzz"));
    const QString line = QStringLiteral("[Proxmox %1] %2").arg(timestamp, sanitizeDebugString(message));
    if (debugLogToJournal) {
        qDebug().noquote() << line;
    }
    m_debugLog.push_back(line);
    constexpr int maxLines = 100;
    while (m_debugLog.size() > maxLines) {
        m_debugLog.removeFirst();
    }
    emit debugLogChanged();
}

void ProxmoxController::setSecretsResolved(int value) {
    if (m_secretsResolved == value) return;
    m_secretsResolved = value;
    emit secretsResolvedChanged();
}

void ProxmoxController::setSecretsTotal(int value) {
    if (m_secretsTotal == value) return;
    m_secretsTotal = value;
    emit secretsTotalChanged();
}

void ProxmoxController::setMultiSecretHadError(bool value) {
    if (m_multiSecretHadError == value) return;
    m_multiSecretHadError = value;
    emit multiSecretHadErrorChanged();
}

void ProxmoxController::startSecretRead() {
    const QString key = keyFor(m_host, m_port, m_tokenId);
    if (key.isEmpty()) {
        setRefreshResolvingSecrets(false);
        setSecretState(QStringLiteral("missing"));
        return;
    }

    setRefreshResolvingSecrets(true);
    const quint64 generation = ++m_secretResolutionGeneration;
    m_activeSingleSecretKey = key;
    m_singleSecretStore->readSecret(
        key,
        [this, key, generation](const QString &secret) {
            // Configuration may have changed while the keyring job was active.
            // Never apply a credential result to a different endpoint identity.
            if (m_secretResolutionGeneration != generation
                || m_activeSingleSecretKey != key) return;
            m_activeSingleSecretKey.clear();

            setRefreshResolvingSecrets(false);
            if (secret.isEmpty()) {
                setSecretState(QStringLiteral("missing"));
                return;
            }

            setSecretState(QStringLiteral("ready"));
            if (m_pbsTimer && !m_pbsTimer->isActive()) {
                refreshPBS();
            }
        },
        [this, key, generation](const QString &) {
            if (m_secretResolutionGeneration != generation
                || m_activeSingleSecretKey != key) return;
            m_activeSingleSecretKey.clear();
            setRefreshResolvingSecrets(false);
            setSecretState(QStringLiteral("error"));
        });
}

void ProxmoxController::startMultiSecretResolution() {
    m_secretResolutionGeneration += 1;
    setSecretsResolved(0);
    setSecretsTotal(0);
    setMultiSecretHadError(false);
    m_tempEndpoints.clear();
    m_secretQueue = buildSecretQueue();
    setSecretsTotal(m_secretQueue.size());
    m_secretQueueIndex = 0;
    m_activeMultiSecretRequest.clear();

    if (m_secretQueue.isEmpty()) {
        setEndpoints({});
        setRefreshResolvingSecrets(false);
        setSecretState(parseMultiHosts().isEmpty() ? QStringLiteral("idle") : QStringLiteral("missing"));
        return;
    }

    setRefreshResolvingSecrets(true);
    setSecretState(QStringLiteral("loading"));
    readNextMultiSecret();
}

void ProxmoxController::readNextMultiSecret() {
    if (m_secretQueueIndex >= m_secretQueue.size()) {
        setEndpoints(m_tempEndpoints);
        if (!m_tempEndpoints.isEmpty()) {
            setSecretState(QStringLiteral("ready"));
        } else if (m_multiSecretHadError) {
            setSecretState(QStringLiteral("error"));
        } else {
            setSecretState(QStringLiteral("missing"));
        }
        setRefreshResolvingSecrets(false);
        return;
    }

    const QVariantMap item = m_secretQueue.at(m_secretQueueIndex).toMap();
    m_activeMultiSecretRequest = {
        {QStringLiteral("sessionKey"), item.value(QStringLiteral("sessionKey"))},
        {QStringLiteral("item"), item},
    };
    const QString sessionKey = item.value(QStringLiteral("sessionKey")).toString();
    const quint64 generation = m_secretResolutionGeneration;
    m_multiSecretStore->readSecret(
        sessionKey,
        [this, sessionKey, item, generation](const QString &secret) {
            if (m_secretResolutionGeneration != generation
                || m_activeMultiSecretRequest.value(QStringLiteral("sessionKey")).toString() != sessionKey) {
                return;
            }

            if (!secret.isEmpty()) {
                QVariantMap endpoint;
                endpoint.insert(QStringLiteral("sessionKey"), sessionKey);
                endpoint.insert(QStringLiteral("label"), item.value(QStringLiteral("label")));
                endpoint.insert(QStringLiteral("host"), item.value(QStringLiteral("host")));
                endpoint.insert(QStringLiteral("port"), item.value(QStringLiteral("port")));
                endpoint.insert(QStringLiteral("tokenId"), item.value(QStringLiteral("tokenId")));
                endpoint.insert(QStringLiteral("ignoreSsl"), item.value(QStringLiteral("ignoreSsl")));
                endpoint.insert(QStringLiteral("pbsEnabled"), item.value(QStringLiteral("pbsEnabled")));
                endpoint.insert(QStringLiteral("pbsHost"), item.value(QStringLiteral("pbsHost")));
                endpoint.insert(QStringLiteral("pbsPort"), item.value(QStringLiteral("pbsPort")));
                endpoint.insert(QStringLiteral("pbsTokenId"), item.value(QStringLiteral("pbsTokenId")));
                endpoint.insert(QStringLiteral("pbsIgnoreSsl"), item.value(QStringLiteral("pbsIgnoreSsl")));
                endpoint.insert(QStringLiteral("pbsBackupWarningDays"), item.value(QStringLiteral("pbsBackupWarningDays")));
                endpoint.insert(QStringLiteral("pbsBackupStaleDays"), item.value(QStringLiteral("pbsBackupStaleDays")));
                // Per-endpoint cert: use shared global cert if multiHostSharedCert is true,
                // otherwise use the cert stored per-endpoint in the JSON config.
                const QString epCertPem = m_multiHostSharedCert
                    ? m_trustedCertPem
                    : item.value(QStringLiteral("trustedCertPem")).toString();
                const QString epCertPath = m_multiHostSharedCert
                    ? m_trustedCertPath
                    : item.value(QStringLiteral("trustedCertPath")).toString();
                endpoint.insert(QStringLiteral("trustedCertPem"), epCertPem);
                endpoint.insert(QStringLiteral("trustedCertPath"), epCertPath);
                m_tempEndpoints.push_back(endpoint);
            }

            setSecretsResolved(m_secretsResolved + 1);
            m_secretQueueIndex += 1;
            m_activeMultiSecretRequest.clear();
            readNextMultiSecret();
        },
        [this, sessionKey, generation](const QString &) {
            if (m_secretResolutionGeneration != generation
                || m_activeMultiSecretRequest.value(QStringLiteral("sessionKey")).toString() != sessionKey) {
                return;
            }
            setMultiSecretHadError(true);
            setSecretsResolved(m_secretsResolved + 1);
            m_secretQueueIndex += 1;
            m_activeMultiSecretRequest.clear();
            readNextMultiSecret();
        });
}

void ProxmoxController::resetTransientStateForModeChange() {
    m_secretResolutionGeneration += 1;
    m_activeSingleSecretKey.clear();
    m_secretQueue.clear();
    m_secretQueueIndex = 0;
    m_activeMultiSecretRequest.clear();
    m_tempEndpoints.clear();
    m_pendingNodeRequests = 0;
    m_tempVmData.clear();
    m_tempLxcData.clear();
    m_tempEndpointsData.clear();
    setRefreshResolvingSecrets(false);
    setLoading(false);
    setIsRefreshing(false);
    setErrorMessage(QString());
    resetRetryState();

    setEndpoints({});
    setDisplayedEndpoints({});
    setDisplayedNodeList({});
    setDisplayedVmData({});
    setDisplayedLxcData({});
    setDisplayedProxmoxData(QVariant());
    clearSingleHostModels();
    clearMultiHostModels();
}

void ProxmoxController::resetMultiTempData() {
    m_tempEndpointsData.clear();
    for (const QVariant &endpointValue : m_endpoints) {
        const QString sessionKey = endpointValue.toMap().value(QStringLiteral("sessionKey")).toString();
        if (!sessionKey.isEmpty()) {
            ensureEndpointBucket(sessionKey);
        }
    }
}

void ProxmoxController::dispatchSingleFetchWithSecret(const QString &secret) {
    if (secret.isEmpty()) {
        setErrorMessage(QStringLiteral("credentials unavailable"));
        setIsRefreshing(false);
        setLoading(false);
        return;
    }

    appendDebugLog(QStringLiteral("[ProxmoxController] single fetch dispatch host=%1 port=%2 ignoreSsl=%3 trustedPem=%4 trustedPath=%5")
        .arg(m_host,
             QString::number(m_port),
             m_ignoreSsl ? QStringLiteral("true") : QStringLiteral("false"),
             m_trustedCertPem.trimmed().isEmpty() ? QStringLiteral("false") : QStringLiteral("true"),
             m_trustedCertPath.trimmed().isEmpty() ? QStringLiteral("false") : QStringLiteral("true")));
    m_api->requestNodesFor(QString(),
                           m_host,
                           m_port,
                           m_tokenId,
                           secret,
                           m_ignoreSsl,
                           m_trustedCertPem.toUtf8(),
                           m_trustedCertPath,
                           m_refreshSeq);
}

void ProxmoxController::dispatchSingleNodeChildrenWithSecret(const QVariantList &nodeNames,
                                                             const QString &secret) {
    if (secret.isEmpty()) {
        setErrorMessage(QStringLiteral("credentials unavailable"));
        setPartialFailure(true);
        m_pendingNodeRequests -= nodeNames.size() * 2;
        if (m_pendingNodeRequests < 0) m_pendingNodeRequests = 0;
        checkRequestsComplete();
        return;
    }

    for (const QVariant &nodeNameValue : nodeNames) {
        const QString nodeName = nodeNameValue.toString();
        m_api->requestQemuFor(QString(), m_host, m_port, m_tokenId, secret,
                              m_ignoreSsl, m_trustedCertPem.toUtf8(), m_trustedCertPath,
                              nodeName, m_refreshSeq);
        m_api->requestLxcFor(QString(), m_host, m_port, m_tokenId, secret,
                             m_ignoreSsl, m_trustedCertPem.toUtf8(), m_trustedCertPath,
                             nodeName, m_refreshSeq);
    }
}



void ProxmoxController::readSingleSecretFor(const QVariantMap &request) {
    const QString key = keyFor(m_host, m_port, m_tokenId);
    m_singleSecretStore->readSecret(
        key,
        [this, request, key](const QString &secret) {
            if (m_connectionMode != QStringLiteral("single")
                || key != keyFor(m_host, m_port, m_tokenId)) {
                return;
            }
            const QVariant requestSeq = request.value(QStringLiteral("seq"));
            if (requestSeq.isValid() && requestSeq.toInt() != m_refreshSeq) return;

            const QString kind = request.value(QStringLiteral("kind")).toString();
            if (kind == ProxmoxConst::Kind::Fetch) {
                dispatchSingleFetchWithSecret(secret);
                return;
            }
            if (kind == ProxmoxConst::Kind::Children) {
                dispatchSingleNodeChildrenWithSecret(
                    request.value(QStringLiteral("nodeNames")).toList(), secret);
                return;
            }
            if (kind == ProxmoxConst::Kind::Action) {
                dispatchSingleActionWithSecret(request.value(QStringLiteral("actionKind")).toString(),
                                               request.value(QStringLiteral("node")).toString(),
                                               request.value(QStringLiteral("vmid")).toInt(),
                                               request.value(QStringLiteral("action")).toString(),
                                               secret);
                return;
            }
            if (kind == ProxmoxConst::Kind::Stats) {
                dispatchSingleStatsWithSecret(
                    request.value(QStringLiteral("sessionKey")).toString(),
                    request.value(QStringLiteral("statsKind")).toString(),
                    request.value(QStringLiteral("node")).toString(),
                    request.value(QStringLiteral("vmid")).toInt(),
                    secret);
                return;
            }
            if (kind != ProxmoxConst::Kind::Console) return;

            const QString actionKind = request.value(QStringLiteral("actionKind")).toString();
            const QString requestId = request.value(QStringLiteral("requestId")).toString();
            const QString node = request.value(QStringLiteral("node")).toString();
            const int vmid = request.value(QStringLiteral("vmid")).toInt();
            const QString vmName = request.value(QStringLiteral("vmName")).toString();

            if (!vmName.isEmpty()) {
                m_pendingConsoleNames.insert(requestId, vmName);
            }

            if (actionKind == ProxmoxConst::Kind::Node) {
                m_api->requestNodeTermProxy(QString(), requestId, m_host, m_port, m_tokenId, secret,
                                            m_ignoreSsl, m_trustedCertPem.toUtf8(), m_trustedCertPath,
                                            node);
            } else if (actionKind == ProxmoxConst::Kind::Lxc) {
                m_api->requestTtyProxy(QString(), requestId, m_host, m_port, m_tokenId, secret,
                                       m_ignoreSsl, m_trustedCertPem.toUtf8(), m_trustedCertPath,
                                       node, vmid);
            } else {
                m_api->requestVncProxy(QString(), requestId, m_host, m_port, m_tokenId, secret,
                                       m_ignoreSsl, m_trustedCertPem.toUtf8(), m_trustedCertPath,
                                       node, actionKind, vmid);
            }
        },
        [this, request, key](const QString &) {
            if (m_connectionMode != QStringLiteral("single")
                || key != keyFor(m_host, m_port, m_tokenId)) {
                return;
            }
            const QVariant requestSeq = request.value(QStringLiteral("seq"));
            if (requestSeq.isValid() && requestSeq.toInt() != m_refreshSeq) return;

            const QString kind = request.value(QStringLiteral("kind")).toString();
            if (kind == ProxmoxConst::Kind::Fetch) {
                dispatchSingleFetchWithSecret(QString());
                return;
            }
            if (kind == ProxmoxConst::Kind::Children) {
                dispatchSingleNodeChildrenWithSecret(
                    request.value(QStringLiteral("nodeNames")).toList(), QString());
                return;
            }
            if (kind == ProxmoxConst::Kind::Console) {
                m_pendingConsoleNames.remove(request.value(QStringLiteral("requestId")).toString());
                emit consoleError(request.value(QStringLiteral("node")).toString(),
                                  request.value(QStringLiteral("actionKind")).toString(),
                                  request.value(QStringLiteral("vmid")).toInt(),
                                  QStringLiteral("credentials unavailable"));
            } else if (kind == ProxmoxConst::Kind::Action) {
                emit actionError(QString(),
                                 request.value(QStringLiteral("actionKind")).toString(),
                                 request.value(QStringLiteral("node")).toString(),
                                 request.value(QStringLiteral("vmid")).toInt(),
                                 request.value(QStringLiteral("action")).toString(),
                                 QStringLiteral("credentials unavailable"));
            } else if (kind == ProxmoxConst::Kind::Stats) {
                emit statsError(request.value(QStringLiteral("sessionKey")).toString(),
                                request.value(QStringLiteral("node")).toString(),
                                request.value(QStringLiteral("vmid")).toInt(),
                                QStringLiteral("credentials unavailable"));
            }
        });
}

bool ProxmoxController::dispatchSingleStatsWithSecret(const QString &sessionKey,
                                                       const QString &statsKind,
                                                       const QString &node,
                                                       int vmid,
                                                       const QString &secret) {
    if (secret.isEmpty()) {
        emit statsError(sessionKey, node, vmid, QStringLiteral("credentials unavailable"));
        return false;
    }

    m_api->requestStatsFor(QString(),
                           m_host,
                           m_port,
                           m_tokenId,
                           secret,
                           m_ignoreSsl,
                           m_trustedCertPem.toUtf8(),
                           m_trustedCertPath,
                           statsKind,
                           node,
                           vmid,
                           ++m_refreshSeq);
    return true;
}

bool ProxmoxController::dispatchSingleActionWithSecret(const QString &kind,
                                                       const QString &node,
                                                       int vmid,
                                                       const QString &action,
                                                       const QString &secret) {
    if (secret.isEmpty()) {
        emit actionError(QString(), kind, node, vmid, action, QStringLiteral("credentials unavailable"));
        return false;
    }

    cancelRefresh();
    setIsRefreshing(false);
    setLoading(false);

    m_api->requestActionFor(QString(),
                            m_host,
                            m_port,
                            m_tokenId,
                            secret,
                            m_ignoreSsl,
                            m_trustedCertPem.toUtf8(),
                            m_trustedCertPath,
                            kind,
                            node,
                            vmid,
                            action,
                            ++m_refreshSeq);
    return true;
}

void ProxmoxController::readMultiSecretFor(const QVariantMap &request) {
    const QString sessionKey = request.value(QStringLiteral("sessionKey")).toString();
    if (sessionKey.isEmpty()) {
        return;
    }

    m_multiSecretStore->readSecret(sessionKey, [this, request](const QString &secret) {
        const QString kind = request.value(QStringLiteral("kind")).toString();
        const QString sessionKey = request.value(QStringLiteral("sessionKey")).toString();
        const QVariant requestSeq = request.value(QStringLiteral("seq"));
        if (requestSeq.isValid() && requestSeq.toInt() != m_refreshSeq) return;
        const QVariantMap endpoint = endpointBySession(sessionKey);

        if (kind == ProxmoxConst::Kind::Nodes) {
            dispatchMultiNodesWithSecret(sessionKey, endpoint, secret);
            return;
        }

        if (kind == ProxmoxConst::Kind::Children) {
            appendDebugLog(QStringLiteral("[ProxmoxController] multi child secret ready session=%1 nodes=%2 secretEmpty=%3")
                .arg(sessionKey,
                     QString::number(request.value(QStringLiteral("nodeNames")).toList().size()),
                     secret.isEmpty() ? QStringLiteral("true") : QStringLiteral("false")));
            dispatchMultiNodeChildrenWithSecret(sessionKey,
                                               endpoint,
                                               request.value(QStringLiteral("nodeNames")).toList(),
                                               secret);
            return;
        }

        if (kind == ProxmoxConst::Kind::Action) {
            if (endpoint.isEmpty()) {
                emit actionError(sessionKey,
                                 request.value(QStringLiteral("actionKind")).toString(),
                                 request.value(QStringLiteral("node")).toString(),
                                 request.value(QStringLiteral("vmid")).toInt(),
                                 request.value(QStringLiteral("action")).toString(),
                                 QStringLiteral("Action failed: endpoint not found"));
                return;
            }

            dispatchMultiActionWithSecret(sessionKey,
                                          endpoint,
                                          request.value(QStringLiteral("actionKind")).toString(),
                                          request.value(QStringLiteral("node")).toString(),
                                          request.value(QStringLiteral("vmid")).toInt(),
                                          request.value(QStringLiteral("action")).toString(),
                                          secret);
            return;
        }

        if (kind == ProxmoxConst::Kind::Console) {
            const QString actionKind = request.value(QStringLiteral("actionKind")).toString();
            const QString requestId  = request.value(QStringLiteral("requestId")).toString();
            const QString node       = request.value(QStringLiteral("node")).toString();
            const int vmid           = request.value(QStringLiteral("vmid")).toInt();
            const QString vmName     = request.value(QStringLiteral("vmName")).toString();

            if (endpoint.isEmpty() || secret.isEmpty()) {
                emit consoleError(node, actionKind, vmid, QStringLiteral("endpoint credentials unavailable"));
                return;
            }

            // Stash vmName so the ttyProxyReady/vncProxyReady forwarder can
            // attach it to consoleReady (the underlying API doesn't carry it).
            if (!vmName.isEmpty()) {
                m_pendingConsoleNames.insert(requestId, vmName);
            }

            const QString epHost     = endpoint.value(QStringLiteral("host")).toString();
            const int     epPort     = endpoint.value(QStringLiteral("port"), ProxmoxConst::Defaults::PvePort).toInt();
            const QString epTokenId  = endpoint.value(QStringLiteral("tokenId")).toString();
            const bool    epIgnore   = endpoint.value(QStringLiteral("ignoreSsl")).toBool();
            const QByteArray epCertPem  = endpoint.value(QStringLiteral("trustedCertPem")).toString().toUtf8();
            const QString    epCertPath = endpoint.value(QStringLiteral("trustedCertPath")).toString();

            if (actionKind == ProxmoxConst::Kind::Node) {
                m_api->requestNodeTermProxy(sessionKey, requestId, epHost, epPort, epTokenId, secret,
                                            epIgnore, epCertPem, epCertPath, node);
            } else if (actionKind == ProxmoxConst::Kind::Lxc) {
                m_api->requestTtyProxy(sessionKey, requestId, epHost, epPort, epTokenId, secret,
                                       epIgnore, epCertPem, epCertPath, node, vmid);
            } else {
                m_api->requestVncProxy(sessionKey, requestId, epHost, epPort, epTokenId, secret,
                                       epIgnore, epCertPem, epCertPath, node, actionKind, vmid);
            }
        }
    }, [this, request](const QString &) {
        const QString kind = request.value(QStringLiteral("kind")).toString();
        const QString sessionKey = request.value(QStringLiteral("sessionKey")).toString();
        const QVariant requestSeq = request.value(QStringLiteral("seq"));
        if (requestSeq.isValid() && requestSeq.toInt() != m_refreshSeq) return;

        if (kind == ProxmoxConst::Kind::Nodes) {
            dispatchMultiNodesWithSecret(sessionKey, endpointBySession(sessionKey), QString());
            return;
        }

        if (kind == ProxmoxConst::Kind::Children) {
            appendDebugLog(QStringLiteral("[ProxmoxController] multi child secret error session=%1 nodes=%2")
                .arg(sessionKey,
                     QString::number(request.value(QStringLiteral("nodeNames")).toList().size())));
            dispatchMultiNodeChildrenWithSecret(sessionKey,
                                               endpointBySession(sessionKey),
                                               request.value(QStringLiteral("nodeNames")).toList(),
                                               QString());
            return;
        }

        if (kind == ProxmoxConst::Kind::Action) {
            emit actionError(sessionKey,
                             request.value(QStringLiteral("actionKind")).toString(),
                             request.value(QStringLiteral("node")).toString(),
                             request.value(QStringLiteral("vmid")).toInt(),
                             request.value(QStringLiteral("action")).toString(),
                             QStringLiteral("endpoint credentials unavailable"));
            return;
        }

        if (kind == ProxmoxConst::Kind::Console) {
            m_pendingConsoleNames.remove(request.value(QStringLiteral("requestId")).toString());
            emit consoleError(request.value(QStringLiteral("node")).toString(),
                              request.value(QStringLiteral("actionKind")).toString(),
                              request.value(QStringLiteral("vmid")).toInt(),
                              QStringLiteral("endpoint credentials unavailable"));
        }
    });
}

void ProxmoxController::dispatchMultiNodesWithSecret(const QString &sessionKey,
                                                     const QVariantMap &endpoint,
                                                     const QString &secret) {
    if (endpoint.isEmpty()) {
        m_pendingNodeRequests -= 1;
        if (m_pendingNodeRequests < 0) m_pendingNodeRequests = 0;
        checkMultiRequestsComplete();
        return;
    }

    if (secret.isEmpty()) {
        QVariantMap bucket = ensureEndpointBucket(sessionKey);
        bucket.insert(QStringLiteral("error"), QStringLiteral("endpoint credentials unavailable"));
        bucket.insert(QStringLiteral("offline"), false);
        bucket.insert(QStringLiteral("nodes"), QVariantList());
        bucket.insert(QStringLiteral("vms"), QVariantList());
        bucket.insert(QStringLiteral("lxcs"), QVariantList());
        m_tempEndpointsData.insert(sessionKey, bucket);
        m_pendingNodeRequests -= 1;
        if (m_pendingNodeRequests < 0) m_pendingNodeRequests = 0;
        checkMultiRequestsComplete();
        return;
    }

    m_api->requestNodesFor(sessionKey,
                           endpoint.value(QStringLiteral("host")).toString(),
                           endpoint.value(QStringLiteral("port"), ProxmoxConst::Defaults::PvePort).toInt(),
                           endpoint.value(QStringLiteral("tokenId")).toString(),
                           secret,
                           endpoint.value(QStringLiteral("ignoreSsl")).toBool(),
                           endpoint.value(QStringLiteral("trustedCertPem")).toString().toUtf8(),
                           endpoint.value(QStringLiteral("trustedCertPath")).toString(),
                           m_refreshSeq);
}

void ProxmoxController::dispatchMultiNodeChildrenWithSecret(const QString &sessionKey,
                                                            const QVariantMap &endpoint,
                                                            const QVariantList &nodeNames,
                                                            const QString &secret) {
    if (secret.isEmpty()) {
        QVariantMap bucket = ensureEndpointBucket(sessionKey);
        bucket.insert(QStringLiteral("error"), QStringLiteral("endpoint credentials unavailable"));
        bucket.insert(QStringLiteral("offline"), false);
        m_tempEndpointsData.insert(sessionKey, bucket);
        m_pendingNodeRequests -= nodeNames.size() * 2;
        if (m_pendingNodeRequests < 0) m_pendingNodeRequests = 0;
        checkMultiRequestsComplete();
        return;
    }

    for (const QVariant &nodeNameValue : nodeNames) {
        const QString nodeName = nodeNameValue.toString();
        m_api->requestQemuFor(sessionKey,
                              endpoint.value(QStringLiteral("host")).toString(),
                              endpoint.value(QStringLiteral("port"), ProxmoxConst::Defaults::PvePort).toInt(),
                              endpoint.value(QStringLiteral("tokenId")).toString(),
                              secret,
                              endpoint.value(QStringLiteral("ignoreSsl")).toBool(),
                              endpoint.value(QStringLiteral("trustedCertPem")).toString().toUtf8(),
                              endpoint.value(QStringLiteral("trustedCertPath")).toString(),
                              nodeName,
                              m_refreshSeq);
        m_api->requestLxcFor(sessionKey,
                             endpoint.value(QStringLiteral("host")).toString(),
                             endpoint.value(QStringLiteral("port"), ProxmoxConst::Defaults::PvePort).toInt(),
                             endpoint.value(QStringLiteral("tokenId")).toString(),
                             secret,
                             endpoint.value(QStringLiteral("ignoreSsl")).toBool(),
                             endpoint.value(QStringLiteral("trustedCertPem")).toString().toUtf8(),
                             endpoint.value(QStringLiteral("trustedCertPath")).toString(),
                             nodeName,
                             m_refreshSeq);
    }
}

bool ProxmoxController::dispatchMultiActionWithSecret(const QString &sessionKey,
                                                      const QVariantMap &endpoint,
                                                      const QString &kind,
                                                      const QString &node,
                                                      int vmid,
                                                      const QString &action,
                                                      const QString &secret) {
    if (secret.isEmpty()) {
        emit actionError(sessionKey, kind, node, vmid, action, QStringLiteral("endpoint credentials unavailable"));
        return false;
    }

    cancelRefresh();
    resetMultiTempData();
    setIsRefreshing(false);
    setLoading(false);

    m_api->requestActionFor(sessionKey,
                            endpoint.value(QStringLiteral("host")).toString(),
                            endpoint.value(QStringLiteral("port"), ProxmoxConst::Defaults::PvePort).toInt(),
                            endpoint.value(QStringLiteral("tokenId")).toString(),
                            secret,
                            endpoint.value(QStringLiteral("ignoreSsl")).toBool(),
                            endpoint.value(QStringLiteral("trustedCertPem")).toString().toUtf8(),
                            endpoint.value(QStringLiteral("trustedCertPath")).toString(),
                            kind,
                            node,
                            vmid,
                            action,
                            ++m_refreshSeq);
    return true;
}

QVariantMap ProxmoxController::endpointBySession(const QString &sessionKey) const {
    for (const QVariant &endpointValue : m_endpoints) {
        const QVariantMap endpoint = endpointValue.toMap();
        if (endpoint.value(QStringLiteral("sessionKey")).toString() == sessionKey) return endpoint;
    }
    return {};
}

QVariantMap ProxmoxController::ensureEndpointBucket(const QString &sessionKey) {
    QVariantMap bucket = m_tempEndpointsData.value(sessionKey).toMap();
    if (!bucket.isEmpty()) return bucket;

    const QVariantMap endpoint = endpointBySession(sessionKey);
    bucket = {
        {QStringLiteral("sessionKey"), sessionKey},
        {QStringLiteral("label"), endpoint.value(QStringLiteral("label"))},
        {QStringLiteral("host"), endpoint.value(QStringLiteral("host"))},
        {QStringLiteral("port"), endpoint.value(QStringLiteral("port"), ProxmoxConst::Defaults::PvePort)},
        {QStringLiteral("error"), QString()},
        {QStringLiteral("offline"), false},
        {QStringLiteral("nodes"), QVariantList()},
        {QStringLiteral("vms"), QVariantList()},
        {QStringLiteral("lxcs"), QVariantList()},
    };
    m_tempEndpointsData.insert(sessionKey, bucket);
    return bucket;
}

QVariantList ProxmoxController::bucketsToArray(const QVariantMap &map) const {
    return ProxmoxDataUtils::mergeEndpointBuckets(m_endpoints, map);
}

void ProxmoxController::handleSingleReply(int seq, const QString &kind, const QString &node, const QVariant &data) {
    if (seq != m_refreshSeq || m_connectionMode != QStringLiteral("single")) return;

    if (kind == ProxmoxConst::Kind::Nodes) {
        QVariantMap payload = data.toMap();
        QVariantList nodes = payload.value(QStringLiteral("data")).toList();
        appendDebugLog(QStringLiteral("[ProxmoxController] single nodes reply count=%1").arg(QString::number(nodes.size())));
        std::sort(nodes.begin(), nodes.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap().value(QStringLiteral("node")).toString().localeAwareCompare(b.toMap().value(QStringLiteral("node")).toString()) < 0;
        });
        payload.insert(QStringLiteral("data"), nodes);
        m_proxmoxData = payload;
        setErrorMessage(QString());
        setLastUpdate(QDateTime::currentDateTime().toString(QStringLiteral("hh:mm:ss")));
        resetRetryState();

        if (!nodes.isEmpty()) {
            m_nodeList.clear();
            for (const QVariant &nodeValue : nodes) {
                m_nodeList.push_back(nodeValue.toMap().value(QStringLiteral("node")).toString());
            }
            std::sort(m_nodeList.begin(), m_nodeList.end(), [](const QVariant &a, const QVariant &b) {
                return a.toString().localeAwareCompare(b.toString()) < 0;
            });
            m_tempVmData.clear();
            m_tempLxcData.clear();
            m_pendingNodeRequests = m_nodeList.size() * 2;
            readSingleSecretFor({
                {QStringLiteral("kind"), ProxmoxConst::Kind::Children},
                {QStringLiteral("nodeNames"), m_nodeList},
                {QStringLiteral("seq"), m_refreshSeq},
            });
        } else {
            setDisplayedProxmoxData(m_proxmoxData);
            setDisplayedNodeList({});
            setDisplayedVmData({});
            setDisplayedLxcData({});
            publishSingleHostModels();
            setIsRefreshing(false);
            setLoading(false);
        }
        return;
    }

    if (kind == ProxmoxConst::Kind::Qemu) {
        m_tempVmData += ProxmoxDataUtils::responseRows(data, {
            {QStringLiteral("node"), node},
        });
        m_pendingNodeRequests -= 1;
        checkRequestsComplete();
        return;
    }

    if (kind == ProxmoxConst::Kind::Lxc) {
        m_tempLxcData += ProxmoxDataUtils::responseRows(data, {
            {QStringLiteral("node"), node},
        });
        m_pendingNodeRequests -= 1;
        checkRequestsComplete();
    }
}

void ProxmoxController::handleSingleError(int seq, const QString &kind, const QString &node, const QString &message) {
    if (seq != m_refreshSeq || m_connectionMode != QStringLiteral("single")) return;
    Q_UNUSED(node)
    appendDebugLog(QStringLiteral("[ProxmoxController] single error kind=%1 message=%2").arg(kind, message));

    if (kind == ProxmoxConst::Kind::Nodes) {
        setErrorMessage(message.isEmpty() ? QStringLiteral("Connection failed") : message);
        m_pendingNodeRequests = 0;
        setIsRefreshing(false);
        setLoading(false);
        scheduleRetry(m_errorMessage);
        return;
    }

    setPartialFailure(true);
    m_pendingNodeRequests -= 1;
    if (m_pendingNodeRequests < 0) m_pendingNodeRequests = 0;
    checkRequestsComplete();
}

void ProxmoxController::checkRequestsComplete() {
    if (m_pendingNodeRequests > 0) return;
    appendDebugLog(QStringLiteral("[ProxmoxController] checkRequestsComplete nodes=%1 vms=%2 lxcs=%3")
        .arg(QString::number(m_nodeList.size()), QString::number(m_tempVmData.size()), QString::number(m_tempLxcData.size())));
    setDisplayedProxmoxData(m_proxmoxData);
    setDisplayedNodeList(m_nodeList);
    setDisplayedVmData(m_tempVmData);
    setDisplayedLxcData(m_tempLxcData);
    correlateBackups();
    m_vmData = m_tempVmData;
    m_lxcData = m_tempLxcData;
    m_tempVmData.clear();
    m_tempLxcData.clear();
    setIsRefreshing(false);
    setLoading(false);
    if (m_partialFailure) {
        setLastUpdate(QDateTime::currentDateTime().toString(QStringLiteral("hh:mm:ss")) + QStringLiteral(" ⚠"));
    }
}

void ProxmoxController::handleMultiReply(int seq, const QString &sessionKey, const QString &kind, const QString &node, const QVariant &data) {
    if (seq != m_refreshSeq || m_connectionMode != QStringLiteral("multiHost") || sessionKey.isEmpty()) return;

    if (kind == ProxmoxConst::Kind::Nodes) {
        QVariantMap bucket = ensureEndpointBucket(sessionKey);
        const QVariantList nodes = ProxmoxDataUtils::responseRows(data, {
            {QStringLiteral("sessionKey"), sessionKey},
        });
        appendDebugLog(QStringLiteral("[ProxmoxController] multi nodes reply session=%1 count=%2")
            .arg(sessionKey, QString::number(nodes.size())));
        bucket.insert(QStringLiteral("offline"), false);
        bucket.insert(QStringLiteral("error"), QString());
        bucket.insert(QStringLiteral("nodes"), nodes);
        m_tempEndpointsData.insert(sessionKey, bucket);

        QVariantList nodeNames;
        for (const QVariant &nodeValue : nodes) {
            nodeNames.push_back(nodeValue.toMap().value(QStringLiteral("node")).toString());
        }
        if (nodeNames.isEmpty()) {
            m_pendingNodeRequests -= 1;
            if (m_pendingNodeRequests < 0) m_pendingNodeRequests = 0;
            checkMultiRequestsComplete();
            return;
        }
        m_pendingNodeRequests += nodeNames.size() * 2;
        readMultiSecretFor({
            {QStringLiteral("kind"), ProxmoxConst::Kind::Children},
            {QStringLiteral("sessionKey"), sessionKey},
            {QStringLiteral("nodeNames"), nodeNames},
            {QStringLiteral("seq"), m_refreshSeq},
        });
        m_pendingNodeRequests -= 1;
        checkMultiRequestsComplete();
        return;
    }

    if (kind == ProxmoxConst::Kind::Qemu || kind == ProxmoxConst::Kind::Lxc) {
        appendDebugLog(QStringLiteral("[ProxmoxController] multi %1 reply session=%2 node=%3 count=%4")
            .arg(kind,
                 sessionKey,
                 node,
                 QString::number(data.toMap().value(QStringLiteral("data")).toList().size())));
        QVariantMap bucket = ensureEndpointBucket(sessionKey);
        QVariantList items = (kind == ProxmoxConst::Kind::Qemu) ? bucket.value(QStringLiteral("vms")).toList() : bucket.value(QStringLiteral("lxcs")).toList();
        items += ProxmoxDataUtils::responseRows(data, {
            {QStringLiteral("node"), node},
            {QStringLiteral("sessionKey"), sessionKey},
        });
        bucket.insert(kind == ProxmoxConst::Kind::Qemu ? QStringLiteral("vms") : QStringLiteral("lxcs"), items);
        m_tempEndpointsData.insert(sessionKey, bucket);
        m_pendingNodeRequests -= 1;
        checkMultiRequestsComplete();
    }
}

void ProxmoxController::handleMultiError(int seq, const QString &sessionKey, const QString &kind, const QString &node, const QString &message) {
    if (seq != m_refreshSeq || m_connectionMode != QStringLiteral("multiHost")) return;
    setErrorMessage(message.isEmpty() ? QStringLiteral("Connection failed") : message);
    setPartialFailure(true);
    appendDebugLog(QStringLiteral("[ProxmoxController] multi error session=%1 kind=%2 message=%3")
        .arg(sessionKey, kind, m_errorMessage));

    QVariantMap bucket = ensureEndpointBucket(sessionKey);
    if (kind == ProxmoxConst::Kind::Nodes) {
        bucket.insert(QStringLiteral("error"), m_errorMessage);
        const bool offline = m_errorMessage.contains(QStringLiteral("timed out"), Qt::CaseInsensitive) || m_errorMessage.contains(QStringLiteral("timeout"), Qt::CaseInsensitive);
        bucket.insert(QStringLiteral("offline"), offline);
        if (offline) {
            bucket.insert(QStringLiteral("nodes"), QVariantList());
            bucket.insert(QStringLiteral("vms"), QVariantList());
            bucket.insert(QStringLiteral("lxcs"), QVariantList());
        }
        m_tempEndpointsData.insert(sessionKey, bucket);
    } else {
        const QString childError = node.isEmpty()
            ? QStringLiteral("%1: %2").arg(kind, m_errorMessage)
            : QStringLiteral("%1 (%2): %3").arg(node, kind, m_errorMessage);
        const QString existingError = bucket.value(QStringLiteral("error")).toString();
        bucket.insert(QStringLiteral("error"), existingError.isEmpty()
            ? childError
            : existingError + QLatin1Char('\n') + childError);
        m_tempEndpointsData.insert(sessionKey, bucket);
    }

    m_pendingNodeRequests -= 1;
    if (m_pendingNodeRequests < 0) m_pendingNodeRequests = 0;
    checkMultiRequestsComplete();
}

void ProxmoxController::checkMultiRequestsComplete() {
    if (m_pendingNodeRequests > 0) return;
    setDisplayedEndpoints(bucketsToArray(m_tempEndpointsData));
    appendDebugLog(QStringLiteral("[ProxmoxController] checkMultiRequestsComplete endpoints=%1").arg(QString::number(m_displayedEndpoints.size())));

    QVariantList aggNodes;
    QVariantList aggVms;
    QVariantList aggLxcs;
    for (const QVariant &endpointValue : m_displayedEndpoints) {
        const QVariantMap endpoint = endpointValue.toMap();
        for (const QVariant &nodeValue : endpoint.value(QStringLiteral("nodes")).toList()) {
            aggNodes.push_back(nodeValue.toMap().value(QStringLiteral("node")).toString());
        }
        for (const QVariant &vmValue : endpoint.value(QStringLiteral("vms")).toList()) {
            aggVms.push_back(vmValue);
        }
        for (const QVariant &lxcValue : endpoint.value(QStringLiteral("lxcs")).toList()) {
            aggLxcs.push_back(lxcValue);
        }
    }

    appendDebugLog(QStringLiteral("[ProxmoxController] multi aggregate nodes=%1 vms=%2 lxcs=%3")
        .arg(QString::number(aggNodes.size()))
        .arg(QString::number(aggVms.size()))
        .arg(QString::number(aggLxcs.size())));
    setDisplayedNodeList(aggNodes);
    setDisplayedVmData(aggVms);
    setDisplayedLxcData(aggLxcs);
    correlateBackups();
    setDisplayedProxmoxData(QVariant());
    if (!m_displayedEndpoints.isEmpty()) {
        setErrorMessage(QString());
    }
    const QString completedAt = QDateTime::currentDateTime().toString(QStringLiteral("hh:mm:ss"));
    setLastUpdate(m_partialFailure ? completedAt + QStringLiteral(" ⚠") : completedAt);
    resetRetryState();
    setIsRefreshing(false);
    setLoading(false);
}

QVariantList ProxmoxController::parseMultiHosts() const {
    return ProxmoxDataUtils::parseMultiHostsJson(m_multiHostsJson);
}

QVariantList ProxmoxController::buildSecretQueue() const {
    return ProxmoxDataUtils::buildEndpointQueue(parseMultiHosts(), m_ignoreSsl);
}

void ProxmoxController::refreshPBS() {
    if (m_pbsDebounceTimer) {
        m_pbsDebounceTimer->start();
    }
}

void ProxmoxController::checkPBSRequestsComplete() {
    if (m_pendingPbsSnapshotRequests > 0 || m_pendingPbsEndpoints > 0) {
        return;
    }

    m_pendingPbsSnapshotRequests = 0;
    m_pendingPbsEndpoints = 0;
    correlateBackups();
}

void ProxmoxController::refreshPBSNow() {
    m_api->cancelPBS();
    // Keychain reads started by an earlier cycle cannot be cancelled; bumping
    // the generation makes their callbacks drop themselves instead of fetching
    // with stale settings or clobbering this cycle's counters.
    const quint64 generation = ++m_pbsRefreshGeneration;
    appendDebugLog(QStringLiteral("[ProxmoxController] refreshPBS mode=%1").arg(m_connectionMode));
    m_latestBackups.clear();
    m_pendingPbsSnapshotRequests = 0;
    m_pendingPbsEndpoints = 0;
    if (!m_pbsRefreshError.isEmpty()) {
        m_pbsRefreshError.clear();
        emit pbsLastErrorChanged();
    }

    m_pbsRefreshInterval = m_pbsRefreshInterval > 0 ? m_pbsRefreshInterval : ProxmoxConst::Defaults::PbsRefreshInterval;
    if (m_pbsTimer) {
        m_pbsTimer->setInterval(m_pbsRefreshInterval * 1000);
        if (!m_pbsTimer->isActive()) {
            m_pbsTimer->start();
        }
    }

    if (m_connectionMode == QStringLiteral("single")) {
        if (!m_host.trimmed().isEmpty()) {
            auto *store = new SecretStore(this);
            store->setService(QStringLiteral("ProxMon"));
            const QString pbsHost = m_pbsHost.trimmed();
            const QString key = pbsKeyForHost(pbsHost);
            appendDebugLog(QStringLiteral("[ProxmoxController] refreshPBS single readKey host=%1 key=%2").arg(pbsHost, key));
            const int pbsPort = m_pbsPort > 0 ? m_pbsPort : ProxmoxConst::Defaults::PbsPort;
            const QString pbsTokenId = m_pbsTokenId.trimmed();
            const bool pbsEnabled = m_pbsEnabled;
            const bool pbsIgnoreSsl = m_pbsIgnoreSsl;
            m_pbsRefreshInterval = m_pbsRefreshInterval > 0 ? m_pbsRefreshInterval : ProxmoxConst::Defaults::PbsRefreshInterval;
            if (m_pbsTimer) {
                m_pbsTimer->setInterval(m_pbsRefreshInterval * 1000);
            }
            appendDebugLog(QStringLiteral("[ProxmoxController] refreshPBS single enabled=%1 pbsHost=%2 tokenIdEmpty=%3 interval=%4")
                .arg(pbsEnabled ? QStringLiteral("true") : QStringLiteral("false"))
                .arg(pbsHost)
                .arg(pbsTokenId.isEmpty() ? QStringLiteral("true") : QStringLiteral("false"))
                .arg(m_pbsRefreshInterval));
            if (!pbsEnabled || pbsHost.isEmpty() || pbsTokenId.isEmpty()) {
                store->deleteLater();
                correlateBackups();
                return;
            }
            store->readSecret(key, [this, store, generation, pbsHost, pbsPort, pbsTokenId, pbsIgnoreSsl](const QString &secret) {
                appendDebugLog(QStringLiteral("[ProxmoxController] refreshPBS single secretReady host=%1 secretEmpty=%2")
                    .arg(pbsHost, secret.isEmpty() ? QStringLiteral("true") : QStringLiteral("false")));
                store->deleteLater();
                if (generation != m_pbsRefreshGeneration) return;
                if (secret.isEmpty()) {
                    correlateBackups();
                    return;
                }
                m_pendingPbsEndpoints = 1;
                m_api->fetchPBSDatastores(pbsHost, pbsPort, pbsTokenId, secret, pbsIgnoreSsl, m_pbsTrustedCertPem.toUtf8(), m_pbsTrustedCertPath);
            }, [this, store, generation, pbsHost](const QString &message) {
                appendDebugLog(QStringLiteral("[ProxmoxController] refreshPBS single secretError host=%1 message=%2").arg(pbsHost, message));
                store->deleteLater();
                if (generation != m_pbsRefreshGeneration) return;
                if (m_pbsRefreshError != message) {
                    m_pbsRefreshError = message;
                    emit pbsLastErrorChanged();
                }
                if (m_pendingPbsEndpoints > 0) {
                    m_pendingPbsEndpoints -= 1;
                }
                checkPBSRequestsComplete();
            });
            return;
        }
        correlateBackups();
        return;
    }

    const QVariantList entries = parseMultiHosts();
    bool anyConfigured = false;
    for (const QVariant &entryValue : entries) {
        const QVariantMap entry = entryValue.toMap();
        if (entry.value(QStringLiteral("enabled"), true).toBool() == false) continue;
        if (!entry.value(QStringLiteral("pbsEnabled"), false).toBool()) continue;
        const QString pbsHost = entry.value(QStringLiteral("pbsHost")).toString().trimmed();
        const QString pbsTokenId = entry.value(QStringLiteral("pbsTokenId")).toString().trimmed();
        if (pbsHost.isEmpty() || pbsTokenId.isEmpty()) continue;
        anyConfigured = true;
        auto *store = new SecretStore(this);
        const QString key = pbsKeyForHost(pbsHost);
        appendDebugLog(QStringLiteral("[ProxmoxController] refreshPBS multi readKey host=%1 key=%2").arg(pbsHost, key));
        store->setService(QStringLiteral("ProxMon"));
        m_pendingPbsEndpoints += 1;
        const int pbsPort = entry.value(QStringLiteral("pbsPort"), ProxmoxConst::Defaults::PbsPort).toInt() > 0 ? entry.value(QStringLiteral("pbsPort"), ProxmoxConst::Defaults::PbsPort).toInt() : ProxmoxConst::Defaults::PbsPort;
        const bool pbsIgnoreSsl = entry.value(QStringLiteral("pbsIgnoreSsl"), false).toBool();
        const QString pbsTrustedCertPem = entry.contains(QStringLiteral("pbsTrustedCertPem"))
            ? entry.value(QStringLiteral("pbsTrustedCertPem")).toString()
            : m_pbsTrustedCertPem;
        const QString pbsTrustedCertPath = entry.contains(QStringLiteral("pbsTrustedCertPath"))
            ? entry.value(QStringLiteral("pbsTrustedCertPath")).toString().trimmed()
            : m_pbsTrustedCertPath;
        store->readSecret(key, [this, store, generation, pbsHost, pbsPort, pbsTokenId, pbsIgnoreSsl, pbsTrustedCertPem, pbsTrustedCertPath](const QString &secret) {
            store->deleteLater();
            if (generation != m_pbsRefreshGeneration) return;
            if (secret.isEmpty()) {
                if (m_pendingPbsEndpoints > 0) {
                    m_pendingPbsEndpoints -= 1;
                }
                checkPBSRequestsComplete();
                return;
            }
            m_api->fetchPBSDatastores(pbsHost, pbsPort, pbsTokenId, secret, pbsIgnoreSsl, pbsTrustedCertPem.toUtf8(), pbsTrustedCertPath);
        }, [this, store, generation, pbsHost](const QString &message) {
            appendDebugLog(QStringLiteral("[ProxmoxController] refreshPBS multi secretError host=%1 message=%2").arg(pbsHost, message));
            store->deleteLater();
            if (generation != m_pbsRefreshGeneration) return;
            if (m_pbsRefreshError != message) {
                m_pbsRefreshError = message;
                emit pbsLastErrorChanged();
            }
            if (m_pendingPbsEndpoints > 0) {
                m_pendingPbsEndpoints -= 1;
            }
            checkPBSRequestsComplete();
        });
    }

    if (!anyConfigured) {
        correlateBackups();
    }
}

BackupStatus ProxmoxController::evaluateBackupStatus(qint64 lastBackupTime, int warningDays, int staleDays) const {
    if (lastBackupTime == 0) return BackupStatus::Never;
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    const qint64 age = std::max<qint64>(0, now - lastBackupTime);
    if (age <= qint64(warningDays) * ProxmoxConst::Defaults::SecondsPerDay) return BackupStatus::Current;
    if (age <= qint64(staleDays) * ProxmoxConst::Defaults::SecondsPerDay) return BackupStatus::Warning;
    return BackupStatus::Stale;
}

QString ProxmoxController::lastBackupDisplay(qint64 backupTime) const {
    if (backupTime == 0) return QStringLiteral("Never");
    const qint64 age = std::max<qint64>(0, QDateTime::currentSecsSinceEpoch() - backupTime);
    const qint64 hours = age / ProxmoxConst::Defaults::SecondsPerHour;
    const qint64 days = age / ProxmoxConst::Defaults::SecondsPerDay;
    const qint64 weeks = days / 7;
    const qint64 years = days / 365;
    if (hours < 1) return QStringLiteral("Just now");
    if (hours < 24) return QStringLiteral("%1h ago").arg(hours);
    if (days < 7) return QStringLiteral("%1d ago").arg(days);
    if (weeks < 52) return QStringLiteral("%1w ago").arg(weeks);
    return QStringLiteral("%1y ago").arg(years);
}

bool ProxmoxController::isBackupExcluded(int vmid, const QString &tags) const {
    if (!m_pbsExcludeTag.trimmed().isEmpty()) {
        if (tags.contains(m_pbsExcludeTag.trimmed(), Qt::CaseInsensitive))
            return true;
    }
    if (!m_pbsExcludeVmids.trimmed().isEmpty()) {
        const QStringList vmids = m_pbsExcludeVmids.split(QLatin1Char(','), Qt::SkipEmptyParts);
        for (const QString &v : vmids) {
            if (v.trimmed().toInt() == vmid)
                return true;
        }
    }
    return false;
}

void ProxmoxController::applyBackupState(QVariantList &items, const QVariantMap &endpointMap, bool isLxc, bool &anyChanged) {
    for (QVariant &itemValue : items) {
        QVariantMap item = itemValue.toMap();
        const int vmid = item.value(QStringLiteral("vmid")).toInt();
        const QString sessionKey = item.value(QStringLiteral("sessionKey")).toString();
        const QVariantMap endpoint = sessionKey.isEmpty() ? QVariantMap() : endpointMap.value(sessionKey).toMap();
        const bool pbsEnabled = sessionKey.isEmpty()
            ? m_pbsEnabled
            : endpoint.value(QStringLiteral("pbsEnabled"), false).toBool();
        if (!pbsEnabled) {
            const int oldStatus = item.value(QStringLiteral("backupStatus"), int(BackupStatus::Unknown)).toInt();
            const QString oldDisplay = item.value(QStringLiteral("lastBackupDisplay")).toString();
            const QString oldVerify = item.value(QStringLiteral("verifyState")).toString();
            if (oldStatus != int(BackupStatus::Unknown) || !oldDisplay.isEmpty() || !oldVerify.isEmpty()) {
                item.insert(QStringLiteral("backupStatus"), int(BackupStatus::Unknown));
                item.insert(QStringLiteral("lastBackupTime"), 0);
                item.insert(QStringLiteral("lastBackupDisplay"), QString());
                item.insert(QStringLiteral("verifyState"), QString());
                anyChanged = true;
            }
            itemValue = item;
            continue;
        }
        // Check exclusions
        const QString itemTags = item.value(QStringLiteral("tags")).toString();
        if (isBackupExcluded(vmid, itemTags)) {
            const int exOldStatus = item.value(QStringLiteral("backupStatus"), int(BackupStatus::Unknown)).toInt();
            const QString exOldDisplay = item.value(QStringLiteral("lastBackupDisplay")).toString();
            const QString exOldVerify = item.value(QStringLiteral("verifyState")).toString();
            if (exOldStatus != int(BackupStatus::Excluded) || !exOldDisplay.isEmpty() || !exOldVerify.isEmpty()) {
                item.insert(QStringLiteral("backupStatus"), int(BackupStatus::Excluded));
                item.insert(QStringLiteral("lastBackupTime"), 0);
                item.insert(QStringLiteral("lastBackupDisplay"), QString());
                item.insert(QStringLiteral("verifyState"), QString());
                anyChanged = true;
            }
            itemValue = item;
            continue;
        }

        const int warningDays = sessionKey.isEmpty()
            ? std::max(1, m_pbsBackupWarningDays)
            : std::max(1, endpoint.value(QStringLiteral("pbsBackupWarningDays"), 7).toInt());
        const int staleDays = sessionKey.isEmpty()
            ? std::max(warningDays, m_pbsBackupStaleDays)
            : std::max(warningDays, endpoint.value(QStringLiteral("pbsBackupStaleDays"), 14).toInt());

        const QString expectedType = isLxc ? QStringLiteral("ct") : QStringLiteral("vm");
        const QString pbsHost = sessionKey.isEmpty()
            ? m_pbsHost.trimmed()
            : endpoint.value(QStringLiteral("pbsHost")).toString().trimmed();
        const QString backupKey = QStringLiteral("%1|%2|%3").arg(normalizedHost(pbsHost), expectedType, QString::number(vmid));
        const auto backupIt = m_latestBackups.constFind(QStringView{backupKey});
        const PBSSnapshot snapshot = backupIt == m_latestBackups.constEnd() ? PBSSnapshot{} : backupIt.value();
        const bool typeMatch = snapshot.backupType.isEmpty() || snapshot.backupType == expectedType;
        const qint64 backupTime = typeMatch ? snapshot.backupTime : 0;
        const BackupStatus status = evaluateBackupStatus(backupTime, warningDays, staleDays);
        const int oldStatus = item.value(QStringLiteral("backupStatus"), int(BackupStatus::Unknown)).toInt();
        const QString oldDisplay = item.value(QStringLiteral("lastBackupDisplay")).toString();
        const QString oldVerify = item.value(QStringLiteral("verifyState")).toString();
        const QString newDisplay = lastBackupDisplay(backupTime);
        const QString newVerify = typeMatch ? snapshot.verifyState : QString();

        if (oldStatus != int(status) || oldDisplay != newDisplay || oldVerify != newVerify) {
            item.insert(QStringLiteral("backupStatus"), int(status));
            item.insert(QStringLiteral("lastBackupTime"), backupTime);
            item.insert(QStringLiteral("lastBackupDisplay"), newDisplay);
            item.insert(QStringLiteral("verifyState"), newVerify);
            anyChanged = true;
        }
        itemValue = item;
    }
}

void ProxmoxController::correlateBackups() {
    bool anyChanged = false;
    QVariantMap endpointMap;
    for (const QVariant &endpointValue : m_displayedEndpoints) {
        const QVariantMap endpoint = endpointValue.toMap();
        endpointMap.insert(endpoint.value(QStringLiteral("sessionKey")).toString(), endpoint);
    }

    // Multi-host delegates render the nested endpoint lists, not the flattened
    // aggregate models below. Keep both representations correlated.
    QVariantList endpoints = m_displayedEndpoints;
    for (QVariant &endpointValue : endpoints) {
        QVariantMap endpoint = endpointValue.toMap();

        QVariantList endpointVms = endpoint.value(QStringLiteral("vms")).toList();
        applyBackupState(endpointVms, endpointMap, false, anyChanged);
        endpoint.insert(QStringLiteral("vms"), endpointVms);

        QVariantList endpointLxcs = endpoint.value(QStringLiteral("lxcs")).toList();
        applyBackupState(endpointLxcs, endpointMap, true, anyChanged);
        endpoint.insert(QStringLiteral("lxcs"), endpointLxcs);

        endpointValue = endpoint;
    }
    if (endpoints != m_displayedEndpoints) {
        setDisplayedEndpoints(endpoints);
    }

    QVariantList vms = m_displayedVmData;
    applyBackupState(vms, endpointMap, false, anyChanged);
    if (vms != m_displayedVmData) {
        setDisplayedVmData(vms);
    }

    QVariantList lxcs = m_displayedLxcData;
    applyBackupState(lxcs, endpointMap, true, anyChanged);
    if (lxcs != m_displayedLxcData) {
        setDisplayedLxcData(lxcs);
    }

    // Push the (possibly backup-annotated) data into the delegate models.
    // Each publish no-ops in the wrong mode and is cheap when nothing changed.
    publishSingleHostModels();
    publishMultiHostModels();
}

QString ProxmoxController::normalizedHost(const QString &host) const {
    return host.trimmed().toLower();
}

QString ProxmoxController::resolvedHostFingerprint(const QString &host) const {
    const QString normalized = normalizedHost(host);
    if (normalized.isEmpty()) {
        return {};
    }

    QHostAddress address;
    if (address.setAddress(normalized)) {
        return address.toString().toLower();
    }

    const QHostInfo info = QHostInfo::fromName(normalized);
    for (const QHostAddress &candidate : info.addresses()) {
        if (candidate.protocol() == QAbstractSocket::IPv4Protocol || candidate.protocol() == QAbstractSocket::IPv6Protocol) {
            return candidate.toString().toLower();
        }
    }

    return {};
}

QString ProxmoxController::normalizedTokenId(const QString &tokenId) const {
    return tokenId.trimmed();
}

QString ProxmoxController::keyFor(const QString &host, int port, const QString &tokenId) const {
    return ProxmoxDataUtils::pveSecretKey(host, port, tokenId);
}

QVariantMap ProxmoxController::parseKeyEntry(const QString &key) const {
    if (!key.startsWith(QStringLiteral("apiTokenSecret:"))) {
        return {};
    }
    const QString body = key.mid(QStringLiteral("apiTokenSecret:").size());
    const int colon = body.lastIndexOf(QLatin1Char(':'));
    if (colon <= 0 || colon >= body.size() - 1) {
        return {};
    }
    const QString left = body.left(colon);
    const int port = body.mid(colon + 1).toInt();
    const int at = left.lastIndexOf(QLatin1Char('@'));
    if (at <= 0 || at >= left.size() - 1 || port <= 0) {
        return {};
    }
    return {
        {QStringLiteral("tokenId"), left.left(at)},
        {QStringLiteral("host"), left.mid(at + 1)},
        {QStringLiteral("port"), port},
    };
}

QVariantList ProxmoxController::parseKeyEntries(const QStringList &keys) const {
    QVariantMap discoveredByKey;
    QStringList discoveredOrder;
    QVariantMap discoveredFingerprintToKey;
    for (const QString &key : keys) {
        const QVariantMap parsed = parseKeyEntry(key);
        if (parsed.isEmpty()) continue;
        const QString host = parsed.value(QStringLiteral("host")).toString();
        const int port = parsed.value(QStringLiteral("port")).toInt();
        const QString tokenId = parsed.value(QStringLiteral("tokenId")).toString();
        const QString dedupeKey = keyFor(host, port, tokenId);
        const QString fingerprint = QStringLiteral("%1|%2|%3").arg(normalizedTokenId(tokenId), QString::number(port), resolvedHostFingerprint(host));
        if (discoveredByKey.contains(dedupeKey)) continue;
        if (!resolvedHostFingerprint(host).isEmpty() && discoveredFingerprintToKey.contains(fingerprint)) {
            const QString existingKey = discoveredFingerprintToKey.value(fingerprint).toString();
            const bool preferHostName = !QHostAddress().setAddress(normalizedHost(host));
            if (preferHostName) {
                discoveredByKey.remove(existingKey);
                discoveredOrder.removeAll(existingKey);
                discoveredByKey.insert(dedupeKey, parsed);
                discoveredOrder.push_back(dedupeKey);
                discoveredFingerprintToKey.insert(fingerprint, dedupeKey);
            }
            continue;
        }
        discoveredByKey.insert(dedupeKey, parsed);
        discoveredOrder.push_back(dedupeKey);
        if (!resolvedHostFingerprint(host).isEmpty()) {
            discoveredFingerprintToKey.insert(fingerprint, dedupeKey);
        }
    }

    QVariantList entries;
    QStringList used;
    const QVariantList existing = parseMultiHosts();
    for (const QVariant &entryValue : existing) {
        QVariantMap entry = entryValue.toMap();
        const QString host = entry.value(QStringLiteral("host")).toString().trimmed();
        const QString tokenId = entry.value(QStringLiteral("tokenId")).toString().trimmed();
        if (host.isEmpty() || tokenId.isEmpty()) continue;
        int port = entry.value(QStringLiteral("port"), ProxmoxConst::Defaults::PvePort).toInt();
        if (port <= 0) port = ProxmoxConst::Defaults::PvePort;
        const QString dedupeKey = keyFor(host, port, tokenId);
        QVariantMap parsed = discoveredByKey.value(dedupeKey).toMap();
        if (parsed.isEmpty()) {
            const QString fingerprint = QStringLiteral("%1|%2|%3").arg(normalizedTokenId(tokenId), QString::number(port), resolvedHostFingerprint(host));
            for (auto it = discoveredByKey.constBegin(); it != discoveredByKey.constEnd(); ++it) {
                const QVariantMap candidate = it.value().toMap();
                if (candidate.value(QStringLiteral("tokenId")).toString() != tokenId) continue;
                if (candidate.value(QStringLiteral("port")).toInt() != port) continue;
                if (resolvedHostFingerprint(candidate.value(QStringLiteral("host")).toString()) == fingerprint.section('|', 2, 2) && !fingerprint.section('|', 2, 2).isEmpty()) {
                    parsed = candidate;
                    break;
                }
            }
        }
        if (parsed.isEmpty()) continue;
        entry.insert(QStringLiteral("host"), parsed.value(QStringLiteral("host")));
        entry.insert(QStringLiteral("port"), parsed.value(QStringLiteral("port")));
        entry.insert(QStringLiteral("tokenId"), parsed.value(QStringLiteral("tokenId")));
        if (!entry.contains(QStringLiteral("enabled"))) {
            entry.insert(QStringLiteral("enabled"), true);
        }
        entries.push_back(entry);
        used.push_back(dedupeKey);
    }

    for (const QString &dedupeKey : discoveredOrder) {
        if (used.contains(dedupeKey)) continue;
        QVariantMap entry = discoveredByKey.value(dedupeKey).toMap();
        entry.insert(QStringLiteral("name"), entry.value(QStringLiteral("host")).toString());
        entry.insert(QStringLiteral("enabled"), true);
        entries.push_back(entry);
    }
    return entries;
}
