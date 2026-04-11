#pragma once

#include <QObject>
#include <QVariant>

class ProxmoxClient;
class SecretStore;

class ProxmoxController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString connectionMode READ connectionMode WRITE setConnectionMode NOTIFY connectionModeChanged)
    Q_PROPERTY(QString host READ host WRITE setHost NOTIFY hostChanged)
    Q_PROPERTY(int port READ port WRITE setPort NOTIFY portChanged)
    Q_PROPERTY(QString tokenId READ tokenId WRITE setTokenId NOTIFY tokenIdChanged)
    Q_PROPERTY(QString apiTokenSecret READ apiTokenSecret WRITE setApiTokenSecret NOTIFY apiTokenSecretChanged)
    Q_PROPERTY(QString multiHostsJson READ multiHostsJson WRITE setMultiHostsJson NOTIFY multiHostsJsonChanged)
    Q_PROPERTY(bool debugEnabled READ debugEnabled WRITE setDebugEnabled NOTIFY debugEnabledChanged)
    Q_PROPERTY(bool ignoreSsl READ ignoreSsl WRITE setIgnoreSsl NOTIFY ignoreSslChanged)
    Q_PROPERTY(QString secretState READ secretState NOTIFY secretStateChanged)
    Q_PROPERTY(bool refreshResolvingSecrets READ refreshResolvingSecrets NOTIFY refreshResolvingSecretsChanged)
    Q_PROPERTY(QVariantList endpoints READ endpoints NOTIFY endpointsChanged)
    Q_PROPERTY(int secretsResolved READ secretsResolved NOTIFY secretsResolvedChanged)
    Q_PROPERTY(int secretsTotal READ secretsTotal NOTIFY secretsTotalChanged)
    Q_PROPERTY(bool multiSecretHadError READ multiSecretHadError NOTIFY multiSecretHadErrorChanged)
    Q_PROPERTY(bool autoRetry READ autoRetry WRITE setAutoRetry NOTIFY autoRetryChanged)
    Q_PROPERTY(int retryStartMs READ retryStartMs WRITE setRetryStartMs NOTIFY retryStartMsChanged)
    Q_PROPERTY(int retryMaxMs READ retryMaxMs WRITE setRetryMaxMs NOTIFY retryMaxMsChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(bool isRefreshing READ isRefreshing NOTIFY isRefreshingChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(QString lastUpdate READ lastUpdate NOTIFY lastUpdateChanged)
    Q_PROPERTY(bool partialFailure READ partialFailure NOTIFY partialFailureChanged)
    Q_PROPERTY(int retryAttempt READ retryAttempt NOTIFY retryAttemptChanged)
    Q_PROPERTY(int retryNextDelayMs READ retryNextDelayMs NOTIFY retryNextDelayMsChanged)
    Q_PROPERTY(QString retryStatusText READ retryStatusText NOTIFY retryStatusTextChanged)
    Q_PROPERTY(QVariant displayedProxmoxData READ displayedProxmoxData NOTIFY displayedProxmoxDataChanged)
    Q_PROPERTY(QVariantList displayedVmData READ displayedVmData NOTIFY displayedVmDataChanged)
    Q_PROPERTY(QVariantList displayedLxcData READ displayedLxcData NOTIFY displayedLxcDataChanged)
    Q_PROPERTY(QVariantList displayedEndpoints READ displayedEndpoints NOTIFY displayedEndpointsChanged)
    Q_PROPERTY(QVariantList displayedNodeList READ displayedNodeList NOTIFY displayedNodeListChanged)
    Q_PROPERTY(int runningVMs READ runningVMs NOTIFY runningVMsChanged)
    Q_PROPERTY(int runningLXC READ runningLXC NOTIFY runningLXCChanged)

public:
    explicit ProxmoxController(QObject *parent = nullptr);

    QString connectionMode() const { return m_connectionMode; }
    void setConnectionMode(const QString &value);

    QString host() const { return m_host; }
    void setHost(const QString &value);

    int port() const { return m_port; }
    void setPort(int value);

    QString tokenId() const { return m_tokenId; }
    void setTokenId(const QString &value);

    QString apiTokenSecret() const { return m_apiTokenSecret; }
    void setApiTokenSecret(const QString &value);

    QString multiHostsJson() const { return m_multiHostsJson; }
    void setMultiHostsJson(const QString &value);

    bool debugEnabled() const { return m_debugEnabled; }
    void setDebugEnabled(bool value);

    bool ignoreSsl() const { return m_ignoreSsl; }
    void setIgnoreSsl(bool value);

    QString secretState() const { return m_secretState; }
    bool refreshResolvingSecrets() const { return m_refreshResolvingSecrets; }
    QVariantList endpoints() const { return m_endpoints; }
    int secretsResolved() const { return m_secretsResolved; }
    int secretsTotal() const { return m_secretsTotal; }
    bool multiSecretHadError() const { return m_multiSecretHadError; }
    bool autoRetry() const { return m_autoRetry; }
    void setAutoRetry(bool value);
    int retryStartMs() const { return m_retryStartMs; }
    void setRetryStartMs(int value);
    int retryMaxMs() const { return m_retryMaxMs; }
    void setRetryMaxMs(int value);
    bool loading() const { return m_loading; }
    bool isRefreshing() const { return m_isRefreshing; }
    QString errorMessage() const { return m_errorMessage; }
    QString lastUpdate() const { return m_lastUpdate; }
    bool partialFailure() const { return m_partialFailure; }
    int retryAttempt() const { return m_retryAttempt; }
    int retryNextDelayMs() const { return m_retryNextDelayMs; }
    QString retryStatusText() const { return m_retryStatusText; }
    QVariant displayedProxmoxData() const { return m_displayedProxmoxData; }
    QVariantList displayedVmData() const { return m_displayedVmData; }
    QVariantList displayedLxcData() const { return m_displayedLxcData; }
    QVariantList displayedEndpoints() const { return m_displayedEndpoints; }
    QVariantList displayedNodeList() const { return m_displayedNodeList; }
    int runningVMs() const;
    int runningLXC() const;

    Q_INVOKABLE void resolveSecretsIfNeeded();
    Q_INVOKABLE void listStoredKeys();
    Q_INVOKABLE void fetchData();
    Q_INVOKABLE void cancelRefresh();
    Q_INVOKABLE bool runAction(const QString &sessionKey,
                               const QString &kind,
                               const QString &node,
                               int vmid,
                               const QString &action);

signals:
    void connectionModeChanged();
    void hostChanged();
    void portChanged();
    void tokenIdChanged();
    void apiTokenSecretChanged();
    void multiHostsJsonChanged();
    void debugEnabledChanged();
    void ignoreSslChanged();
    void secretStateChanged();
    void refreshResolvingSecretsChanged();
    void endpointsChanged();
    void secretsResolvedChanged();
    void secretsTotalChanged();
    void multiSecretHadErrorChanged();
    void autoRetryChanged();
    void retryStartMsChanged();
    void retryMaxMsChanged();
    void loadingChanged();
    void isRefreshingChanged();
    void errorMessageChanged();
    void lastUpdateChanged();
    void partialFailureChanged();
    void retryAttemptChanged();
    void retryNextDelayMsChanged();
    void retryStatusTextChanged();
    void displayedProxmoxDataChanged();
    void displayedVmDataChanged();
    void displayedLxcDataChanged();
    void displayedEndpointsChanged();
    void displayedNodeListChanged();
    void runningVMsChanged();
    void runningLXCChanged();
    void restoreSingleConfigRequested(const QString &host, int port, const QString &tokenId);
    void restoreMultiHostConfigRequested(const QString &multiHostsJson);
    void keyListError(const QString &message);
    void actionReply(const QString &sessionKey,
                     const QString &actionKind,
                     const QString &node,
                     int vmid,
                     const QString &action,
                     const QVariant &data);
    void actionError(const QString &sessionKey,
                     const QString &actionKind,
                     const QString &node,
                     int vmid,
                     const QString &action,
                     const QString &message);

private:
    void setSecretState(const QString &value);
    void setRefreshResolvingSecrets(bool value);
    void setEndpoints(const QVariantList &value);
    void setSecretsResolved(int value);
    void setSecretsTotal(int value);
    void setMultiSecretHadError(bool value);
    void startSecretReadCandidates();
    void startMultiSecretResolution();
    void readNextMultiSecret();
    QVariantList parseMultiHosts() const;
    QVariantList buildSecretQueue() const;
    void setLoading(bool value);
    void setIsRefreshing(bool value);
    void setErrorMessage(const QString &value);
    void setLastUpdate(const QString &value);
    void setPartialFailure(bool value);
    void setRetryAttempt(int value);
    void setRetryNextDelayMs(int value);
    void setRetryStatusText(const QString &value);
    void setDisplayedProxmoxData(const QVariant &value);
    void setDisplayedVmData(const QVariantList &value);
    void setDisplayedLxcData(const QVariantList &value);
    void setDisplayedEndpoints(const QVariantList &value);
    void setDisplayedNodeList(const QVariantList &value);
    void resetRetryState();
    void scheduleRetry(const QString &reason);
    void resetTransientStateForModeChange();
    void resetMultiTempData();
    void dispatchSingleFetchWithSecret(const QString &secret);
    bool dispatchSingleActionWithSecret(const QString &kind,
                                        const QString &node,
                                        int vmid,
                                        const QString &action,
                                        const QString &secret);
    void dispatchMultiNodesWithSecret(const QString &sessionKey,
                                      const QVariantMap &endpoint,
                                      const QString &secret);
    void dispatchMultiNodeChildrenWithSecret(const QString &sessionKey,
                                             const QVariantMap &endpoint,
                                             const QVariantList &nodeNames,
                                             const QString &secret);
    bool dispatchMultiActionWithSecret(const QString &sessionKey,
                                       const QVariantMap &endpoint,
                                       const QString &kind,
                                       const QString &node,
                                       int vmid,
                                       const QString &action,
                                       const QString &secret);
    void readSingleSecretFor(const QVariantMap &request);
    void readMultiSecretFor(const QVariantMap &request);
    QVariantMap ensureEndpointBucket(const QString &sessionKey);
    QVariantList bucketsToArray(const QVariantMap &map) const;
    void handleSingleReply(int seq, const QString &kind, const QString &node, const QVariant &data);
    void handleSingleError(int seq, const QString &kind, const QString &node, const QString &message);
    void handleMultiReply(int seq, const QString &sessionKey, const QString &kind, const QString &node, const QVariant &data);
    void handleMultiError(int seq, const QString &sessionKey, const QString &kind, const QString &node, const QString &message);
    void checkRequestsComplete();
    void checkMultiRequestsComplete();
    QVariantMap endpointBySession(const QString &sessionKey) const;
    QString normalizedHost(const QString &host) const;
    QString normalizedTokenId(const QString &tokenId) const;
    QString keyFor(const QString &host, int port, const QString &tokenId) const;
    QVariantMap parseKeyEntry(const QString &key) const;
    QVariantList parseKeyEntries(const QStringList &keys) const;

    QString m_connectionMode = QStringLiteral("single");
    QString m_host;
    int m_port = 8006;
    QString m_tokenId;
    QString m_apiTokenSecret;
    QString m_multiHostsJson = QStringLiteral("[]");
    bool m_debugEnabled = false;
    bool m_ignoreSsl = true;
    QString m_secretState = QStringLiteral("idle");
    bool m_refreshResolvingSecrets = false;
    QVariantList m_endpoints;
    int m_secretsResolved = 0;
    int m_secretsTotal = 0;
    bool m_multiSecretHadError = false;
    QVariantList m_secretQueue;
    int m_secretQueueIndex = 0;
    QVariantMap m_activeMultiSecretRequest;
    QVariantList m_tempEndpoints;
    QVariantList m_secretKeyCandidates;
    int m_secretKeyCandidateIndex = 0;
    bool m_autoRetry = true;
    int m_retryStartMs = 5000;
    int m_retryMaxMs = 300000;
    bool m_loading = false;
    bool m_isRefreshing = false;
    QString m_errorMessage;
    QString m_lastUpdate;
    bool m_partialFailure = false;
    int m_retryAttempt = 0;
    int m_retryNextDelayMs = 0;
    QString m_retryStatusText;
    QVariant m_proxmoxData;
    QVariantList m_vmData;
    QVariantList m_lxcData;
    QVariant m_displayedProxmoxData;
    QVariantList m_displayedVmData;
    QVariantList m_displayedLxcData;
    QVariantList m_displayedEndpoints;
    QVariantList m_displayedNodeList;
    QVariantList m_nodeList;
    int m_pendingNodeRequests = 0;
    QVariantList m_tempVmData;
    QVariantList m_tempLxcData;
    int m_refreshSeq = 0;
    QVariantMap m_tempEndpointsData;
    ProxmoxClient *m_api;
    SecretStore *m_singleSecretStore;
    SecretStore *m_multiSecretStore;
};
