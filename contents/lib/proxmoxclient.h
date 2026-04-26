#pragma once

#include <QObject>
#include <QByteArray>
#include <QList>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QSet>
#include <QVariant>

#include "pbstypes.h"

class ProxmoxClient : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString host READ host WRITE setHost NOTIFY hostChanged)
    Q_PROPERTY(int port READ port WRITE setPort NOTIFY portChanged)
    Q_PROPERTY(QString tokenId READ tokenId WRITE setTokenId NOTIFY tokenIdChanged)
    Q_PROPERTY(QString tokenSecret READ tokenSecret WRITE setTokenSecret NOTIFY tokenSecretChanged)
    Q_PROPERTY(bool ignoreSslErrors READ ignoreSslErrors WRITE setIgnoreSslErrors NOTIFY ignoreSslErrorsChanged)
    Q_PROPERTY(bool debugEnabled READ debugEnabled WRITE setDebugEnabled NOTIFY debugEnabledChanged)

public:
    explicit ProxmoxClient(QObject *parent = nullptr);
    ~ProxmoxClient() override;

    QString host() const { return m_host; }
    void setHost(const QString &v);

    int port() const { return m_port; }
    void setPort(int v);

    QString tokenId() const { return m_tokenId; }
    void setTokenId(const QString &v);

    QString tokenSecret() const { return m_tokenSecret; }
    void setTokenSecret(const QString &v);

    bool ignoreSslErrors() const { return m_ignoreSslErrors; }
    void setIgnoreSslErrors(bool v);

    bool debugEnabled() const { return m_debugEnabled; }
    void setDebugEnabled(bool value);

    //Low latency properties for quick updates, but require mutating object state and are not multi-session friendly.
    Q_PROPERTY(bool lowLatency READ lowLatency WRITE setLowLatency NOTIFY lowLatencyChanged)
    Q_PROPERTY(QString trustedCertPem READ trustedCertPem WRITE setTrustedCertPem NOTIFY trustedCertPemChanged)
    QString trustedCertPem() const { return m_trustedCertPem; }
    void setTrustedCertPem(const QString &v);

    Q_PROPERTY(QString trustedCertPath READ trustedCertPath WRITE setTrustedCertPath NOTIFY trustedCertPathChanged)
    QString trustedCertPath() const { return m_trustedCertPath; }
    void setTrustedCertPath(const QString &v);
    bool lowLatency() const { return m_lowLatency; }
    void setLowLatency(bool v);

    // Single-session (legacy)
    Q_INVOKABLE void requestNodes(int seq);
    Q_INVOKABLE void requestQemu(const QString &node, int seq);
    Q_INVOKABLE void requestLxc(const QString &node, int seq);

    // Multi-session: provide per-call connection info, without mutating object-wide properties.
    // sessionKey is returned in reply/error so QML can merge results.
    Q_INVOKABLE void requestNodesFor(const QString &sessionKey,
                                     const QString &host,
                                     int port,
                                     const QString &tokenId,
                                     const QString &tokenSecret,
                                     bool ignoreSslErrors,
                                     int seq);
    Q_INVOKABLE void requestQemuFor(const QString &sessionKey,
                                    const QString &host,
                                    int port,
                                    const QString &tokenId,
                                    const QString &tokenSecret,
                                    bool ignoreSslErrors,
                                    const QString &node,
                                    int seq);
    Q_INVOKABLE void requestLxcFor(const QString &sessionKey,
                                   const QString &host,
                                   int port,
                                   const QString &tokenId,
                                   const QString &tokenSecret,
                                   bool ignoreSslErrors,
                                   const QString &node,
                                   int seq);

    // VM/CT actions: kind: "qemu" | "lxc"; action: "start" | "shutdown" | "reboot"
    Q_INVOKABLE void requestAction(const QString &kind, const QString &node, int vmid, const QString &action, int seq);
    Q_INVOKABLE void requestActionFor(const QString &sessionKey,
                                      const QString &host,
                                      int port,
                                      const QString &tokenId,
                                      const QString &tokenSecret,
                                      bool ignoreSslErrors,
                                      const QString &kind,
                                      const QString &node,
                                      int vmid,
                                      const QString &action,
                                      int seq);

    // Abort any in-flight network requests (useful when refreshing or timing out).
    Q_INVOKABLE void cancelAll();
    Q_INVOKABLE void cancelPVE();
    Q_INVOKABLE void cancelPBS();
    Q_INVOKABLE void fetchPBSDatastores(const QString &pbsHost,
                                        int port,
                                        const QString &tokenId,
                                        const QString &tokenSecret,
                                        bool ignoreSslErrors,
                                        const QByteArray &trustedCertPem,
                                        const QString &trustedCertPath);
    Q_INVOKABLE void testPBSConnection(const QString &pbsHost,
                                       int port,
                                       const QString &tokenId,
                                       const QString &tokenSecret,
                                       bool ignoreSslErrors,
                                       const QByteArray &trustedCertPem,
                                       const QString &trustedCertPath);

signals:
    void hostChanged();
    void portChanged();
    void tokenIdChanged();
    void tokenSecretChanged();
    void ignoreSslErrorsChanged();
    void debugEnabledChanged();
    void trustedCertPemChanged();
    void trustedCertPathChanged();
    void lowLatencyChanged();

    // kind: "nodes" | "qemu" | "lxc"
    void reply(int seq, const QString &kind, const QString &node, const QVariant &data);
    void error(int seq, const QString &kind, const QString &node, const QString &message);

    // Multi-session variants include sessionKey
    void replyFor(int seq, const QString &sessionKey, const QString &kind, const QString &node, const QVariant &data);
    void errorFor(int seq, const QString &sessionKey, const QString &kind, const QString &node, const QString &message);

    // actionKind: "qemu" | "lxc", action: "start" | "shutdown" | "reboot"
    void actionReply(int seq,
                     const QString &actionKind,
                     const QString &node,
                     int vmid,
                     const QString &action,
                     const QVariant &data);
    void actionError(int seq,
                     const QString &actionKind,
                     const QString &node,
                     int vmid,
                     const QString &action,
                     const QString &message);
    void actionReplyFor(int seq,
                        const QString &sessionKey,
                        const QString &actionKind,
                        const QString &node,
                        int vmid,
                        const QString &action,
                        const QVariant &data);
    void actionErrorFor(int seq,
                        const QString &sessionKey,
                        const QString &actionKind,
                        const QString &node,
                        int vmid,
                        const QString &action,
                        const QString &message);
    void pbsDatastoresReceived(const QString &pbsHost,
                               const QList<QString> &datastores);
    void pbsSnapshotsReceived(const QString &pbsHost,
                              const QString &datastore,
                              const QList<PBSSnapshot> &snapshots);
    void pbsError(const QString &pbsHost, const QString &message);
    void pbsConnectionOk(const QString &pbsHost);

private:
    void request(const QString &path, int seq, const QString &kind, const QString &node);
    void requestFor(const QString &sessionKey,
                    const QString &host,
                    int port,
                    const QString &tokenId,
                    const QString &tokenSecret,
                    bool ignoreSslErrors,
                    const QByteArray &trustedCertPem,
                    const QString &trustedCertPath,
                    const QString &path,
                    int seq,
                    const QString &kind,
                    const QString &node);

    void post(const QString &path,
              int seq,
              const QString &actionKind,
              const QString &node,
              int vmid,
              const QString &action);
    void postFor(const QString &sessionKey,
                 const QString &host,
                 int port,
                 const QString &tokenId,
                 const QString &tokenSecret,
                 bool ignoreSslErrors,
                 const QByteArray &trustedCertPem,
                 const QString &trustedCertPath,
                 const QString &path,
                 int seq,
                 const QString &actionKind,
                 const QString &node,
                 int vmid,
                 const QString &action);
    void pollTaskStatus(const QString &sessionKey,
                        const QString &host,
                        int port,
                        const QString &tokenId,
                        const QString &tokenSecret,
                        bool ignoreSslErrors,
                        const QByteArray &trustedCertPem,
                        const QString &trustedCertPath,
                        const QString &upid,
                        int seq,
                        const QString &actionKind,
                        const QString &node,
                        int vmid,
                        const QString &action);

    QNetworkAccessManager m_nam;
    QString m_host;
    int m_port = 8006;
    QString m_tokenId;
    QString m_tokenSecret;
    bool m_ignoreSslErrors = false;
    bool m_debugEnabled = false;
    QString m_trustedCertPem;
    QString m_trustedCertPath;
    bool m_lowLatency = false;
    QSet<QNetworkReply *> m_inFlight;
    QSet<QNetworkReply *> m_pbsInFlight;
};
