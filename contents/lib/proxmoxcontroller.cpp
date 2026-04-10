#include "proxmoxcontroller.h"

#include "proxmoxclient.h"
#include "secretstore.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QVariantList>
#include <QtGlobal>

ProxmoxController::ProxmoxController(QObject *parent)
    : QObject(parent)
    , m_api(new ProxmoxClient(this))
    , m_singleSecretStore(new SecretStore(this))
    , m_multiSecretStore(new SecretStore(this)) {
    m_singleSecretStore->setService(QStringLiteral("ProxMon"));
    m_multiSecretStore->setService(QStringLiteral("ProxMon"));

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

    connect(m_singleSecretStore, &SecretStore::secretReady, this, [this](const QString &secret) {
        if (!secret.isEmpty()) {
            m_api->setHost(m_host);
            m_api->setPort(m_port);
            m_api->setTokenId(m_tokenId);
            m_api->setTokenSecret(secret);
            m_api->setIgnoreSslErrors(m_ignoreSsl);
            setSecretState(QStringLiteral("ready"));
            setRefreshResolvingSecrets(false);
            return;
        }

        if ((m_secretKeyCandidateIndex + 1) < m_secretKeyCandidates.size()) {
            m_secretKeyCandidateIndex += 1;
            m_singleSecretStore->setKey(m_secretKeyCandidates.at(m_secretKeyCandidateIndex).toString());
            m_singleSecretStore->readSecret();
            return;
        }

        setRefreshResolvingSecrets(false);
        setSecretState(QStringLiteral("missing"));
    });

    connect(m_singleSecretStore, &SecretStore::error, this, [this](const QString &) {
        setRefreshResolvingSecrets(false);
        setSecretState(QStringLiteral("error"));
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

    connect(m_multiSecretStore, &SecretStore::secretReady, this, [this](const QString &secret) {
        if (m_activeMultiSecretRequest.isEmpty()) {
            return;
        }

        const QVariantMap item = m_activeMultiSecretRequest.value(QStringLiteral("item")).toMap();
        const QString sessionKey = m_activeMultiSecretRequest.value(QStringLiteral("sessionKey")).toString();

        if (!secret.isEmpty()) {
            QVariantMap endpoint;
            endpoint.insert(QStringLiteral("sessionKey"), sessionKey);
            endpoint.insert(QStringLiteral("label"), item.value(QStringLiteral("label")));
            endpoint.insert(QStringLiteral("host"), item.value(QStringLiteral("host")));
            endpoint.insert(QStringLiteral("port"), item.value(QStringLiteral("port")));
            endpoint.insert(QStringLiteral("tokenId"), item.value(QStringLiteral("tokenId")));
            endpoint.insert(QStringLiteral("ignoreSsl"), m_ignoreSsl);
            m_tempEndpoints.push_back(endpoint);
        }

        setSecretsResolved(m_secretsResolved + 1);
        m_secretQueueIndex += 1;
        m_activeMultiSecretRequest.clear();
        readNextMultiSecret();
    });

    connect(m_multiSecretStore, &SecretStore::error, this, [this](const QString &) {
        if (m_activeMultiSecretRequest.isEmpty()) {
            return;
        }
        setMultiSecretHadError(true);
        setSecretsResolved(m_secretsResolved + 1);
        m_secretQueueIndex += 1;
        m_activeMultiSecretRequest.clear();
        readNextMultiSecret();
    });

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

void ProxmoxController::setApiTokenSecret(const QString &value) {
    if (m_apiTokenSecret == value) return;
    m_apiTokenSecret = value;
    emit apiTokenSecretChanged();
}

void ProxmoxController::setMultiHostsJson(const QString &value) {
    if (m_multiHostsJson == value) return;
    m_multiHostsJson = value;
    emit multiHostsJsonChanged();
}

void ProxmoxController::setIgnoreSsl(bool value) {
    if (m_ignoreSsl == value) return;
    m_ignoreSsl = value;
    emit ignoreSslChanged();
}

void ProxmoxController::resolveSecretsIfNeeded() {
    const bool hasCoreConfig = (m_connectionMode == QStringLiteral("multiHost"))
        ? !parseMultiHosts().isEmpty()
        : (!m_host.isEmpty() && !m_tokenId.isEmpty());
    qDebug() << "[ProxmoxController] resolveSecretsIfNeeded mode=" << m_connectionMode
             << "hasCoreConfig=" << hasCoreConfig
             << "host=" << m_host
             << "tokenIdEmpty=" << m_tokenId.isEmpty();

    if (!hasCoreConfig) {
        setEndpoints({});
        m_api->setTokenSecret(QString());
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
    m_api->setTokenSecret(QString());
    startSecretReadCandidates();
}

void ProxmoxController::listStoredKeys() {
    m_singleSecretStore->listKWalletKeys();
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
    qDebug() << "[ProxmoxController] fetchData mode=" << m_connectionMode
             << "hasCoreConfig=" << hasCoreConfig
             << "secretState=" << m_secretState
             << "endpoints=" << m_endpoints.size();
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
                {QStringLiteral("kind"), QStringLiteral("nodes")},
                {QStringLiteral("sessionKey"), endpoint.value(QStringLiteral("sessionKey")).toString()},
            });
        }
        return;
    }

    readSingleSecretFor({
        {QStringLiteral("kind"), QStringLiteral("fetch")},
    });
}

void ProxmoxController::cancelRefresh() {
    m_api->cancelAll();
}

bool ProxmoxController::runAction(const QString &sessionKey,
                                  const QString &kind,
                                  const QString &node,
                                  int vmid,
                                  const QString &action) {
    if (sessionKey.isEmpty()) {
        readSingleSecretFor({
            {QStringLiteral("kind"), QStringLiteral("action")},
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
        {QStringLiteral("kind"), QStringLiteral("action")},
        {QStringLiteral("sessionKey"), sessionKey},
        {QStringLiteral("actionKind"), kind},
        {QStringLiteral("node"), node},
        {QStringLiteral("vmid"), vmid},
        {QStringLiteral("action"), action},
    });
    return true;
}

void ProxmoxController::setSecretState(const QString &value) {
    if (m_secretState == value) return;
    qDebug() << "[ProxmoxController] secretState" << m_secretState << "->" << value;
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
    Q_UNUSED(reason)
}

int ProxmoxController::runningVMs() const {
    int count = 0;
    for (const QVariant &item : m_displayedVmData) {
        if (item.toMap().value(QStringLiteral("status")).toString() == QStringLiteral("running")) count++;
    }
    return count;
}

int ProxmoxController::runningLXC() const {
    int count = 0;
    for (const QVariant &item : m_displayedLxcData) {
        if (item.toMap().value(QStringLiteral("status")).toString() == QStringLiteral("running")) count++;
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

void ProxmoxController::startSecretReadCandidates() {
    QVariantList candidates;
    candidates.push_back(keyFor(m_host, m_port, m_tokenId));
    candidates.push_back(QStringLiteral("apiTokenSecret:%1@%2:%3").arg(m_tokenId, m_host).arg(m_port));
    candidates.push_back(QStringLiteral("apiTokenSecret:%1@%2:%3").arg(normalizedTokenId(m_tokenId), m_host).arg(m_port));
    candidates.push_back(QStringLiteral("apiTokenSecret:%1@%2:%3").arg(m_tokenId, normalizedHost(m_host)).arg(m_port));

    QVariantList uniq;
    for (const QVariant &candidate : candidates) {
        if (!uniq.contains(candidate) && !candidate.toString().isEmpty()) {
            uniq.push_back(candidate);
        }
    }

    m_secretKeyCandidates = uniq;
    m_secretKeyCandidateIndex = 0;
    if (m_secretKeyCandidates.isEmpty()) {
        setRefreshResolvingSecrets(false);
        setSecretState(QStringLiteral("missing"));
        return;
    }

    setRefreshResolvingSecrets(true);
    m_singleSecretStore->setKey(m_secretKeyCandidates.first().toString());
    m_singleSecretStore->readSecret();
}

void ProxmoxController::startMultiSecretResolution() {
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
    m_multiSecretStore->setKey(item.value(QStringLiteral("sessionKey")).toString());
    m_multiSecretStore->readSecret();
}

void ProxmoxController::resetTransientStateForModeChange() {
    m_secretQueue.clear();
    m_secretQueueIndex = 0;
    m_activeMultiSecretRequest.clear();
    m_tempEndpoints.clear();
    m_secretKeyCandidates.clear();
    m_secretKeyCandidateIndex = 0;
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
    m_api->setTokenSecret(QString());
    setDisplayedEndpoints({});
    setDisplayedNodeList({});
    setDisplayedVmData({});
    setDisplayedLxcData({});
    setDisplayedProxmoxData(QVariant());
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

    m_api->requestNodesFor(QString(),
                           m_host,
                           m_port,
                           m_tokenId,
                           secret,
                           m_ignoreSsl,
                           m_refreshSeq);
}

void ProxmoxController::readSingleSecretFor(const QVariantMap &request) {
    m_singleSecretStore->setKey(keyFor(m_host, m_port, m_tokenId));
    connect(m_singleSecretStore, &SecretStore::secretReady, this, [this, request](const QString &secret) {
        const QString kind = request.value(QStringLiteral("kind")).toString();
        if (kind == QStringLiteral("fetch")) {
            dispatchSingleFetchWithSecret(secret);
            return;
        }

        if (kind == QStringLiteral("action")) {
            dispatchSingleActionWithSecret(request.value(QStringLiteral("actionKind")).toString(),
                                           request.value(QStringLiteral("node")).toString(),
                                           request.value(QStringLiteral("vmid")).toInt(),
                                           request.value(QStringLiteral("action")).toString(),
                                           secret);
        }
    }, Qt::SingleShotConnection);
    connect(m_singleSecretStore, &SecretStore::error, this, [this, request](const QString &) {
        const QString kind = request.value(QStringLiteral("kind")).toString();
        if (kind == QStringLiteral("fetch")) {
            dispatchSingleFetchWithSecret(QString());
            return;
        }

        if (kind == QStringLiteral("action")) {
            emit actionError(QString(),
                             request.value(QStringLiteral("actionKind")).toString(),
                             request.value(QStringLiteral("node")).toString(),
                             request.value(QStringLiteral("vmid")).toInt(),
                             request.value(QStringLiteral("action")).toString(),
                             QStringLiteral("credentials unavailable"));
        }
    }, Qt::SingleShotConnection);
    m_singleSecretStore->readSecret();
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

    m_api->requestActionFor(QString(),
                            m_host,
                            m_port,
                            m_tokenId,
                            secret,
                            m_ignoreSsl,
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

    m_multiSecretStore->setKey(sessionKey);
    connect(m_multiSecretStore, &SecretStore::secretReady, this, [this, request](const QString &secret) {
        const QString kind = request.value(QStringLiteral("kind")).toString();
        const QString sessionKey = request.value(QStringLiteral("sessionKey")).toString();
        const QVariantMap endpoint = endpointBySession(sessionKey);

        if (kind == QStringLiteral("nodes")) {
            dispatchMultiNodesWithSecret(sessionKey, endpoint, secret);
            return;
        }

        if (kind == QStringLiteral("children")) {
            qDebug() << "[ProxmoxController] multi child secret ready session=" << sessionKey
                     << "nodes=" << request.value(QStringLiteral("nodeNames")).toList().size()
                     << "secretEmpty=" << secret.isEmpty();
            dispatchMultiNodeChildrenWithSecret(sessionKey,
                                               endpoint,
                                               request.value(QStringLiteral("nodeNames")).toList(),
                                               secret);
            return;
        }

        if (kind == QStringLiteral("action")) {
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
        }
    }, Qt::SingleShotConnection);
    connect(m_multiSecretStore, &SecretStore::error, this, [this, request](const QString &) {
        const QString kind = request.value(QStringLiteral("kind")).toString();
        const QString sessionKey = request.value(QStringLiteral("sessionKey")).toString();

        if (kind == QStringLiteral("nodes")) {
            dispatchMultiNodesWithSecret(sessionKey, endpointBySession(sessionKey), QString());
            return;
        }

        if (kind == QStringLiteral("children")) {
            qDebug() << "[ProxmoxController] multi child secret error session=" << sessionKey
                     << "nodes=" << request.value(QStringLiteral("nodeNames")).toList().size();
            dispatchMultiNodeChildrenWithSecret(sessionKey,
                                               endpointBySession(sessionKey),
                                               request.value(QStringLiteral("nodeNames")).toList(),
                                               QString());
            return;
        }

        if (kind == QStringLiteral("action")) {
            emit actionError(sessionKey,
                             request.value(QStringLiteral("actionKind")).toString(),
                             request.value(QStringLiteral("node")).toString(),
                             request.value(QStringLiteral("vmid")).toInt(),
                             request.value(QStringLiteral("action")).toString(),
                             QStringLiteral("endpoint credentials unavailable"));
        }
    }, Qt::SingleShotConnection);
    m_multiSecretStore->readSecret();
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
                           endpoint.value(QStringLiteral("port"), 8006).toInt(),
                           endpoint.value(QStringLiteral("tokenId")).toString(),
                           secret,
                           endpoint.value(QStringLiteral("ignoreSsl")).toBool(),
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
                              endpoint.value(QStringLiteral("port"), 8006).toInt(),
                              endpoint.value(QStringLiteral("tokenId")).toString(),
                              secret,
                              endpoint.value(QStringLiteral("ignoreSsl")).toBool(),
                              nodeName,
                              m_refreshSeq);
        m_api->requestLxcFor(sessionKey,
                             endpoint.value(QStringLiteral("host")).toString(),
                             endpoint.value(QStringLiteral("port"), 8006).toInt(),
                             endpoint.value(QStringLiteral("tokenId")).toString(),
                             secret,
                             endpoint.value(QStringLiteral("ignoreSsl")).toBool(),
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

    m_api->requestActionFor(sessionKey,
                            endpoint.value(QStringLiteral("host")).toString(),
                            endpoint.value(QStringLiteral("port"), 8006).toInt(),
                            endpoint.value(QStringLiteral("tokenId")).toString(),
                            secret,
                            endpoint.value(QStringLiteral("ignoreSsl")).toBool(),
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
        {QStringLiteral("port"), endpoint.value(QStringLiteral("port"), 8006)},
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
    QVariantList arr;
    for (const QVariant &endpointValue : m_endpoints) {
        const QVariantMap endpoint = endpointValue.toMap();
        const QString sessionKey = endpoint.value(QStringLiteral("sessionKey")).toString();
        const QVariantMap bucket = map.value(sessionKey).toMap();
        QVariantMap row = endpoint;
        row.insert(QStringLiteral("error"), bucket.value(QStringLiteral("error")).toString());
        row.insert(QStringLiteral("offline"), bucket.value(QStringLiteral("offline")).toBool());
        row.insert(QStringLiteral("nodes"), bucket.value(QStringLiteral("nodes")).toList());
        row.insert(QStringLiteral("vms"), bucket.value(QStringLiteral("vms")).toList());
        row.insert(QStringLiteral("lxcs"), bucket.value(QStringLiteral("lxcs")).toList());
        arr.push_back(row);
    }
    std::sort(arr.begin(), arr.end(), [](const QVariant &a, const QVariant &b) {
        const QVariantMap am = a.toMap();
        const QVariantMap bm = b.toMap();
        const QString la = am.value(QStringLiteral("label")).toString().isEmpty() ? am.value(QStringLiteral("host")).toString() : am.value(QStringLiteral("label")).toString();
        const QString lb = bm.value(QStringLiteral("label")).toString().isEmpty() ? bm.value(QStringLiteral("host")).toString() : bm.value(QStringLiteral("label")).toString();
        return la.localeAwareCompare(lb) < 0;
    });
    return arr;
}

void ProxmoxController::handleSingleReply(int seq, const QString &kind, const QString &node, const QVariant &data) {
    if (seq != m_refreshSeq || m_connectionMode != QStringLiteral("single")) return;

    if (kind == QStringLiteral("nodes")) {
        QVariantMap payload = data.toMap();
        QVariantList nodes = payload.value(QStringLiteral("data")).toList();
        qDebug() << "[ProxmoxController] single nodes reply count=" << nodes.size();
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
            for (const QVariant &nodeValue : m_nodeList) {
                const QString nodeName = nodeValue.toString();
                m_api->requestQemu(nodeName, m_refreshSeq);
                m_api->requestLxc(nodeName, m_refreshSeq);
            }
        } else {
            setDisplayedProxmoxData(m_proxmoxData);
            setDisplayedNodeList({});
            setDisplayedVmData({});
            setDisplayedLxcData({});
            setIsRefreshing(false);
            setLoading(false);
        }
        return;
    }

    if (kind == QStringLiteral("qemu")) {
        for (const QVariant &itemValue : data.toMap().value(QStringLiteral("data")).toList()) {
            QVariantMap item = itemValue.toMap();
            item.insert(QStringLiteral("node"), node);
            m_tempVmData.push_back(item);
        }
        m_pendingNodeRequests -= 1;
        checkRequestsComplete();
        return;
    }

    if (kind == QStringLiteral("lxc")) {
        for (const QVariant &itemValue : data.toMap().value(QStringLiteral("data")).toList()) {
            QVariantMap item = itemValue.toMap();
            item.insert(QStringLiteral("node"), node);
            m_tempLxcData.push_back(item);
        }
        m_pendingNodeRequests -= 1;
        checkRequestsComplete();
    }
}

void ProxmoxController::handleSingleError(int seq, const QString &kind, const QString &node, const QString &message) {
    if (seq != m_refreshSeq || m_connectionMode != QStringLiteral("single")) return;
    Q_UNUSED(node)

    if (kind == QStringLiteral("nodes")) {
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
    qDebug() << "[ProxmoxController] checkRequestsComplete nodes=" << m_nodeList.size() << "vms=" << m_tempVmData.size() << "lxcs=" << m_tempLxcData.size();
    setDisplayedProxmoxData(m_proxmoxData);
    setDisplayedNodeList(m_nodeList);
    setDisplayedVmData(m_tempVmData);
    setDisplayedLxcData(m_tempLxcData);
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

    if (kind == QStringLiteral("nodes")) {
        QVariantMap bucket = ensureEndpointBucket(sessionKey);
        QVariantList nodes = data.toMap().value(QStringLiteral("data")).toList();
        qDebug() << "[ProxmoxController] multi nodes reply session=" << sessionKey << "count=" << nodes.size();
        for (QVariant &nodeValue : nodes) {
            QVariantMap item = nodeValue.toMap();
            item.insert(QStringLiteral("sessionKey"), sessionKey);
            nodeValue = item;
        }
        bucket.insert(QStringLiteral("offline"), false);
        bucket.insert(QStringLiteral("error"), QString());
        bucket.insert(QStringLiteral("nodes"), nodes);
        m_tempEndpointsData.insert(sessionKey, bucket);

        QVariantList nodeNames;
        for (const QVariant &nodeValue : nodes) {
            nodeNames.push_back(nodeValue.toMap().value(QStringLiteral("node")).toString());
        }
        m_pendingNodeRequests += nodeNames.size() * 2;
        readMultiSecretFor({
            {QStringLiteral("kind"), QStringLiteral("children")},
            {QStringLiteral("sessionKey"), sessionKey},
            {QStringLiteral("nodeNames"), nodeNames},
        });
        m_pendingNodeRequests -= 1;
        checkMultiRequestsComplete();
        return;
    }

    if (kind == QStringLiteral("qemu") || kind == QStringLiteral("lxc")) {
        qDebug() << "[ProxmoxController] multi" << kind << "reply session=" << sessionKey << "node=" << node << "count=" << data.toMap().value(QStringLiteral("data")).toList().size();
        QVariantMap bucket = ensureEndpointBucket(sessionKey);
        QVariantList items = (kind == QStringLiteral("qemu")) ? bucket.value(QStringLiteral("vms")).toList() : bucket.value(QStringLiteral("lxcs")).toList();
        for (const QVariant &itemValue : data.toMap().value(QStringLiteral("data")).toList()) {
            QVariantMap item = itemValue.toMap();
            item.insert(QStringLiteral("node"), node);
            item.insert(QStringLiteral("sessionKey"), sessionKey);
            items.push_back(item);
        }
        bucket.insert(kind == QStringLiteral("qemu") ? QStringLiteral("vms") : QStringLiteral("lxcs"), items);
        m_tempEndpointsData.insert(sessionKey, bucket);
        m_pendingNodeRequests -= 1;
        checkMultiRequestsComplete();
    }
}

void ProxmoxController::handleMultiError(int seq, const QString &sessionKey, const QString &kind, const QString &node, const QString &message) {
    if (seq != m_refreshSeq || m_connectionMode != QStringLiteral("multiHost")) return;
    Q_UNUSED(node)
    setErrorMessage(message.isEmpty() ? QStringLiteral("Connection failed") : message);

    QVariantMap bucket = ensureEndpointBucket(sessionKey);
    if (kind == QStringLiteral("nodes")) {
        bucket.insert(QStringLiteral("error"), m_errorMessage);
        const bool offline = m_errorMessage.contains(QStringLiteral("timed out"), Qt::CaseInsensitive) || m_errorMessage.contains(QStringLiteral("timeout"), Qt::CaseInsensitive);
        bucket.insert(QStringLiteral("offline"), offline);
        if (offline) {
            bucket.insert(QStringLiteral("nodes"), QVariantList());
            bucket.insert(QStringLiteral("vms"), QVariantList());
            bucket.insert(QStringLiteral("lxcs"), QVariantList());
        }
        m_tempEndpointsData.insert(sessionKey, bucket);
    }

    m_pendingNodeRequests -= 1;
    if (m_pendingNodeRequests < 0) m_pendingNodeRequests = 0;
    checkMultiRequestsComplete();
}

void ProxmoxController::checkMultiRequestsComplete() {
    if (m_pendingNodeRequests > 0) return;
    setDisplayedEndpoints(bucketsToArray(m_tempEndpointsData));
    qDebug() << "[ProxmoxController] checkMultiRequestsComplete endpoints=" << m_displayedEndpoints.size();

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

    qDebug() << "[ProxmoxController] multi aggregate nodes=" << aggNodes.size() << "vms=" << aggVms.size() << "lxcs=" << aggLxcs.size();
    setDisplayedNodeList(aggNodes);
    setDisplayedVmData(aggVms);
    setDisplayedLxcData(aggLxcs);
    setDisplayedProxmoxData(QVariant());
    if (!m_displayedEndpoints.isEmpty()) {
        setErrorMessage(QString());
    }
    setLastUpdate(QDateTime::currentDateTime().toString(QStringLiteral("hh:mm:ss")));
    resetRetryState();
    setIsRefreshing(false);
    setLoading(false);
}

QVariantList ProxmoxController::parseMultiHosts() const {
    const QJsonDocument doc = QJsonDocument::fromJson(m_multiHostsJson.toUtf8());
    if (!doc.isArray()) {
        return {};
    }

    QVariantList list = doc.array().toVariantList();
    if (list.size() > 5) {
        list = list.mid(0, 5);
    }
    for (QVariant &entry : list) {
        QVariantMap map = entry.toMap();
        if (!map.contains(QStringLiteral("enabled"))) {
            map.insert(QStringLiteral("enabled"), true);
        }
        entry = map;
    }
    return list;
}

QVariantList ProxmoxController::buildSecretQueue() const {
    const QVariantList raw = parseMultiHosts();
    QVariantList queue;
    for (const QVariant &entryValue : raw) {
        const QVariantMap entry = entryValue.toMap();
        if (entry.value(QStringLiteral("enabled"), true).toBool() == false) continue;
        const QString host = entry.value(QStringLiteral("host")).toString().trimmed();
        const QString tokenId = entry.value(QStringLiteral("tokenId")).toString().trimmed();
        if (host.isEmpty() || tokenId.isEmpty()) continue;
        int port = entry.value(QStringLiteral("port"), 8006).toInt();
        if (port <= 0) port = 8006;
        QVariantMap item;
        item.insert(QStringLiteral("sessionKey"), keyFor(host, port, tokenId));
        item.insert(QStringLiteral("label"), entry.value(QStringLiteral("name")).toString().trimmed());
        item.insert(QStringLiteral("host"), host);
        item.insert(QStringLiteral("port"), port);
        item.insert(QStringLiteral("tokenId"), tokenId);
        queue.push_back(item);
    }
    return queue;
}

QString ProxmoxController::normalizedHost(const QString &host) const {
    return host.trimmed().toLower();
}

QString ProxmoxController::normalizedTokenId(const QString &tokenId) const {
    return tokenId.trimmed();
}

QString ProxmoxController::keyFor(const QString &host, int port, const QString &tokenId) const {
    return QStringLiteral("apiTokenSecret:%1@%2:%3").arg(normalizedTokenId(tokenId), normalizedHost(host)).arg(port);
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
    for (const QString &key : keys) {
        const QVariantMap parsed = parseKeyEntry(key);
        if (parsed.isEmpty()) continue;
        const QString dedupeKey = keyFor(parsed.value(QStringLiteral("host")).toString(),
                                         parsed.value(QStringLiteral("port")).toInt(),
                                         parsed.value(QStringLiteral("tokenId")).toString());
        if (discoveredByKey.contains(dedupeKey)) continue;
        discoveredByKey.insert(dedupeKey, parsed);
        discoveredOrder.push_back(dedupeKey);
    }

    QVariantList entries;
    QStringList used;
    const QVariantList existing = parseMultiHosts();
    for (const QVariant &entryValue : existing) {
        QVariantMap entry = entryValue.toMap();
        const QString host = entry.value(QStringLiteral("host")).toString().trimmed();
        const QString tokenId = entry.value(QStringLiteral("tokenId")).toString().trimmed();
        if (host.isEmpty() || tokenId.isEmpty()) continue;
        int port = entry.value(QStringLiteral("port"), 8006).toInt();
        if (port <= 0) port = 8006;
        const QString dedupeKey = keyFor(host, port, tokenId);
        if (!discoveredByKey.contains(dedupeKey)) continue;
        const QVariantMap parsed = discoveredByKey.value(dedupeKey).toMap();
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
