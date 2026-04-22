#pragma once

#include <QObject>
#include <QHash>
#include <QTimer>
#include <QVariant>

#include "pbstypes.h"

class ProxmoxClient;
class SecretStore;

class ProxmoxController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString connectionMode READ connectionMode WRITE setConnectionMode NOTIFY connectionModeChanged)
    Q_PROPERTY(QString host READ host WRITE setHost NOTIFY hostChanged)
    Q_PROPERTY(int port READ port WRITE setPort NOTIFY portChanged)
    Q_PROPERTY(QString tokenId READ tokenId WRITE setTokenId NOTIFY tokenIdChanged)
    Q_PROPERTY(QString trustedCertPem READ trustedCertPem WRITE setTrustedCertPem NOTIFY trustedCertPemChanged)
    Q_PROPERTY(QString trustedCertPath READ trustedCertPath WRITE setTrustedCertPath NOTIFY trustedCertPathChanged)
    Q_PROPERTY(QString multiHostsJson READ multiHostsJson WRITE setMultiHostsJson NOTIFY multiHostsJsonChanged)
    Q_PROPERTY(bool pbsEnabled READ pbsEnabled WRITE setPbsEnabled NOTIFY pbsEnabledChanged)
    Q_PROPERTY(QString pbsHost READ pbsHost WRITE setPbsHost NOTIFY pbsHostChanged)
    Q_PROPERTY(int pbsPort READ pbsPort WRITE setPbsPort NOTIFY pbsPortChanged)
    Q_PROPERTY(QString pbsTokenId READ pbsTokenId WRITE setPbsTokenId NOTIFY pbsTokenIdChanged)
    Q_PROPERTY(bool pbsIgnoreSsl READ pbsIgnoreSsl WRITE setPbsIgnoreSsl NOTIFY pbsIgnoreSslChanged)
    Q_PROPERTY(int pbsBackupWarningDays READ pbsBackupWarningDays WRITE setPbsBackupWarningDays NOTIFY pbsBackupWarningDaysChanged)
    Q_PROPERTY(int pbsBackupStaleDays READ pbsBackupStaleDays WRITE setPbsBackupStaleDays NOTIFY pbsBackupStaleDaysChanged)
    Q_PROPERTY(int pbsRefreshInterval READ pbsRefreshInterval WRITE setPbsRefreshInterval NOTIFY pbsRefreshIntervalChanged)
    Q_PROPERTY(bool debugEnabled READ debugEnabled WRITE setDebugEnabled NOTIFY debugEnabledChanged)
    Q_PROPERTY(bool ignoreSsl READ ignoreSsl WRITE setIgnoreSsl NOTIFY ignoreSslChanged)
    Q_PROPERTY(QVariantList debugLog READ debugLog NOTIFY debugLogChanged)
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
    Q_PROPERTY(QString pbsLastError READ pbsLastError NOTIFY pbsLastErrorChanged)
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

    bool debugEnabled() const { return m_debugEnabled; }
    void setDebugEnabled(bool value);

    QString trustedCertPem() const { return m_trustedCertPem; }
    void setTrustedCertPem(const QString &value);

    QString trustedCertPath() const { return m_trustedCertPath; }
    void setTrustedCertPath(const QString &value);

    QString multiHostsJson() const { return m_multiHostsJson; }
    void setMultiHostsJson(const QString &value);

    bool pbsEnabled() const { return m_pbsEnabled; }
    void setPbsEnabled(bool value);

    QString pbsHost() const { return m_pbsHost; }
    void setPbsHost(const QString &value);

    int pbsPort() const { return m_pbsPort; }
    void setPbsPort(int value);

    QString pbsTokenId() const { return m_pbsTokenId; }
    void setPbsTokenId(const QString &value);

    bool pbsIgnoreSsl() const { return m_pbsIgnoreSsl; }
    void setPbsIgnoreSsl(bool value);

    int pbsBackupWarningDays() const { return m_pbsBackupWarningDays; }
    void setPbsBackupWarningDays(int value);

    int pbsBackupStaleDays() const { return m_pbsBackupStaleDays; }
    void setPbsBackupStaleDays(int value);

    int pbsRefreshInterval() const { return m_pbsRefreshInterval; }
    void setPbsRefreshInterval(int value);

    bool ignoreSsl() const { return m_ignoreSsl; }
    void setIgnoreSsl(bool value);

    QVariantList debugLog() const { return m_debugLog; }
    QString sanitizeDebugString(const QString &value) const;
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
    QString pbsLastError() const { return m_pbsRefreshError; }
    QVariant displayedProxmoxData() const { return m_displayedProxmoxData; }
    QVariantList displayedVmData() const { return m_displayedVmData; }
    QVariantList displayedLxcData() const { return m_displayedLxcData; }
    QVariantList displayedEndpoints() const { return m_displayedEndpoints; }
    QVariantList displayedNodeList() const { return m_displayedNodeList; }
    int runningVMs() const;
    int runningLXC() const;

    Q_INVOKABLE void resolveSecretsIfNeeded();
    Q_INVOKABLE void listStoredKeys();
    Q_INVOKABLE void storeSingleSecret(const QString &secret);
    Q_INVOKABLE void storeSinglePBSSecret(const QString &host, const QString &secret);
    Q_INVOKABLE void storeMultiHostSecret(const QString &host, int port, const QString &tokenId, const QString &secret);
    Q_INVOKABLE void storeMultiHostPBSSecret(const QString &host, const QString &secret);
    Q_INVOKABLE void fetchData();
    Q_INVOKABLE void testPBSConnection(const QString &host,
                                       int port,
                                       const QString &tokenId,
                                       bool ignoreSslErrors);
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
    void trustedCertPemChanged();
    void trustedCertPathChanged();
    void multiHostsJsonChanged();
    void pbsEnabledChanged();
    void pbsHostChanged();
    void pbsPortChanged();
    void pbsTokenIdChanged();
    void pbsIgnoreSslChanged();
    void pbsBackupWarningDaysChanged();
    void pbsBackupStaleDaysChanged();
    void pbsRefreshIntervalChanged();
    void debugEnabledChanged();
    void ignoreSslChanged();
    void debugLogChanged();
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
    void pbsLastErrorChanged();
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
    void pbsTestSucceeded(const QString &pbsHost);
    void pbsTestFailed(const QString &pbsHost, const QString &message);

private:
    void setSecretState(const QString &value);
    void setRefreshResolvingSecrets(bool value);
    void setEndpoints(const QVariantList &value);
    void appendDebugLog(const QString &message);
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
    void refreshPBS();
    void applyBackupState(QVariantList &items, const QVariantMap &endpointMap, bool isLxc, bool &anyChanged);
    BackupStatus evaluateBackupStatus(qint64 lastBackupTime, int warningDays, int staleDays) const;
    QString lastBackupDisplay(qint64 backupTime) const;
    void correlateBackups();
    QString pbsKeyForHost(const QString &host) const;
    QString normalizedHost(const QString &host) const;
    QString resolvedHostFingerprint(const QString &host) const;
    QString normalizedTokenId(const QString &tokenId) const;
    QString keyFor(const QString &host, int port, const QString &tokenId) const;
    QVariantMap parseKeyEntry(const QString &key) const;
    QVariantList parseKeyEntries(const QStringList &keys) const;

    QString m_connectionMode = QStringLiteral("single");
    QString m_host;
    int m_port = 8006;
    QString m_tokenId;
    QString m_trustedCertPem;
    QString m_trustedCertPath;
    QString m_multiHostsJson = QStringLiteral("[]");
    bool m_pbsEnabled = false;
    QString m_pbsHost;
    int m_pbsPort = 8007;
    QString m_pbsTokenId;
    bool m_pbsIgnoreSsl = false;
    int m_pbsBackupWarningDays = 7;
    int m_pbsBackupStaleDays = 14;
    int m_pbsRefreshInterval = 3600;
    QString m_activeSingleSecretKey;
    bool m_debugEnabled = false;
    bool m_ignoreSsl = false;
    QVariantList m_debugLog;
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
    QString m_pbsRefreshError;
    bool m_pbsTestInProgress = false;
    int m_pendingPbsEndpoints = 0;
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
    QHash<QString, PBSSnapshot> m_latestBackups;
    QTimer *m_pbsTimer = nullptr;
    int m_pendingPbsSnapshotRequests = 0;
    ProxmoxClient *m_api;
    SecretStore *m_singleSecretStore;
    SecretStore *m_multiSecretStore;
};
