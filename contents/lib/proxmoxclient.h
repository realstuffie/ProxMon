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

public:
    explicit ProxmoxClient(QObject *parent = nullptr);
    ~ProxmoxClient() override;

    void setDebugEnabled(bool value);
    void setLowLatency(bool v);

    // Per-call connection info keeps credentials scoped to one operation.
    // sessionKey is returned in reply/error so QML can merge results.
    void requestNodesFor(const QString &sessionKey,
                                     const QString &host,
                                     int port,
                                     const QString &tokenId,
                                     const QString &tokenSecret,
                                     bool ignoreSslErrors,
                                     const QByteArray &trustedCertPem,
                                     const QString &trustedCertPath,
                                     int seq);
    void requestQemuFor(const QString &sessionKey,
                                    const QString &host,
                                    int port,
                                    const QString &tokenId,
                                    const QString &tokenSecret,
                                    bool ignoreSslErrors,
                                    const QByteArray &trustedCertPem,
                                    const QString &trustedCertPath,
                                    const QString &node,
                                    int seq);
    void requestLxcFor(const QString &sessionKey,
                                   const QString &host,
                                   int port,
                                   const QString &tokenId,
                                   const QString &tokenSecret,
                                   bool ignoreSslErrors,
                                   const QByteArray &trustedCertPem,
                                   const QString &trustedCertPath,
                                   const QString &node,
                                   int seq);

    // VM/CT actions: kind: "qemu" | "lxc"; action: "start" | "shutdown" | "reboot"
    void requestActionFor(const QString &sessionKey,
                                      const QString &host,
                                      int port,
                                      const QString &tokenId,
                                      const QString &tokenSecret,
                                      bool ignoreSslErrors,
                                      const QByteArray &trustedCertPem,
                                      const QString &trustedCertPath,
                                      const QString &kind,
                                      const QString &node,
                                      int vmid,
                                      const QString &action,
                                      int seq);

    void requestVncProxy(const QString &sessionKey,
                                  const QString &requestId,
                                  const QString &host,
                                  int port,
                                  const QString &tokenId,
                                  const QString &tokenSecret,
                                  bool ignoreSslErrors,
                                  const QByteArray &trustedCertPem,
                                  const QString &trustedCertPath,
                                  const QString &node,
                                  const QString &kind,
                                  int vmid);

    void requestTtyProxy(const QString &sessionKey,
                                 const QString &requestId,
                                 const QString &host,
                                 int port,
                                 const QString &tokenId,
                                 const QString &tokenSecret,
                                 bool ignoreSslErrors,
                                 const QByteArray &trustedCertPem,
                                 const QString &trustedCertPath,
                                 const QString &node,
                                 int vmid);

    void requestNodeTermProxy(const QString &sessionKey,
                                 const QString &requestId,
                                 const QString &host,
                                 int port,
                                 const QString &tokenId,
                                 const QString &tokenSecret,
                                 bool ignoreSslErrors,
                                 const QByteArray &trustedCertPem,
                                 const QString &trustedCertPath,
                                 const QString &node);

    // Abort any in-flight network requests (useful when refreshing or timing out).
    void cancelAll();
    void cancelPVE();
    void cancelPBS();
    void fetchPBSDatastores(const QString &pbsHost,
                                        int port,
                                        const QString &tokenId,
                                        const QString &tokenSecret,
                                        bool ignoreSslErrors,
                                        const QByteArray &trustedCertPem,
                                        const QString &trustedCertPath);

signals:
    // user is the auth user returned by termproxy; sent over the
    // websocket as "user:ticket\n" before bidirectional traffic begins.
    // authHeader is the full "PVEAPIToken=USER@REALM!TOKENID=SECRET" string
    // we used to obtain the termproxy ticket — Proxmox requires the same
    // header on the subsequent vncwebsocket upgrade or it 401s.
    void ttyProxyReady(const QString &sessionKey, const QString &requestId, const QString &host, const QString &node, int vmid, int port, const QString &ticket, const QString &user, const QByteArray &authHeader);
    void ttyProxyError(const QString &sessionKey, const QString &requestId, const QString &node, int vmid, const QString &error);
    void nodeTermProxyReady(const QString &sessionKey, const QString &requestId, const QString &host, const QString &node, int port, const QString &ticket, const QString &user, const QByteArray &authHeader);
    void nodeTermProxyError(const QString &sessionKey, const QString &requestId, const QString &node, const QString &error);
    void vncProxyReady(const QString &sessionKey,
                   const QString &requestId,
                   const QString &host,
                   const QString &node,
                   const QString &kind,
                   int vmid,
                   int vncPort,
                   const QString &ticket,
                   int apiPort,
                   const QByteArray &authHeader,
                   bool ignoreSsl);
    void vncProxyError(const QString &sessionKey,
                   const QString &requestId,
                   const QString &node,
                   const QString &kind,
                   int vmid,
                   const QString &message);

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

private:
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
    bool m_debugEnabled = false;
    bool m_lowLatency = false;
    QSet<QNetworkReply *> m_inFlight;
    QSet<QNetworkReply *> m_pbsInFlight;
    QSet<QNetworkReply *> m_taskInFlight;
};
