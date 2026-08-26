#include "proxmoxclient.h"
#include "proxmoxconsts.h"
#include "proxmoxdatautils.h"
#include "proxmoxtaskutils.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QSharedPointer>
#include <QSslCertificate>
#include <QSslConfiguration>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>

#include <utility>

ProxmoxClient::ProxmoxClient(QObject *parent)
    : QObject(parent) {}

ProxmoxClient::~ProxmoxClient() {
    cancelAll();
}

void ProxmoxClient::cancelAll() {
    // Abort any outstanding requests to avoid late reply storms and wasted work.
    //
    // QNetworkReply::abort() emits finished() (Qt docs), so snapshot first to avoid
    // iterating while callbacks remove from the tracking sets.
    const auto pbsReplies = m_pbsInFlight.values();
    m_pbsInFlight.clear();
    const auto refreshReplies = m_refreshInFlight.values();
    m_refreshInFlight.clear();
    const auto interactiveReplies = m_interactiveInFlight.values();
    m_interactiveInFlight.clear();
    const auto taskReplies = m_taskInFlight.values();
    m_taskInFlight.clear();
    const auto taskPollTimers = m_taskPollTimers.values();
    m_taskPollTimers.clear();

    for (QNetworkReply *r : refreshReplies) {
        if (r) r->abort();
    }
    for (QNetworkReply *r : interactiveReplies) {
        if (r) r->abort();
    }
    for (QNetworkReply *r : pbsReplies) {
        if (r) r->abort();
    }
    for (QNetworkReply *r : taskReplies) {
        if (r) r->abort();
    }
    for (QTimer *timer : taskPollTimers) {
        delete timer;
    }
}

void ProxmoxClient::cancelRefreshRequests() {
    const auto replies = m_refreshInFlight.values();
    m_refreshInFlight.clear();
    for (QNetworkReply *r : replies) {
        if (r) r->abort();
    }
}

void ProxmoxClient::cancelPBS() {
    const auto pbsReplies = m_pbsInFlight.values();
    m_nam.clearConnectionCache();
    m_pbsInFlight.clear();
    for (QNetworkReply *r : pbsReplies) {
        if (r) r->abort();
    }
}

void ProxmoxClient::setDebugEnabled(bool value) {
    if (m_debugEnabled == value) return;
    m_debugEnabled = value;
}

void ProxmoxClient::setLowLatency(bool v) {
    if (m_lowLatency == v) return;
    m_lowLatency = v;
}

void ProxmoxClient::requestNodesFor(const QString &sessionKey,
                                    const QString &host,
                                    int port,
                                    const QString &tokenId,
                                    const QString &tokenSecret,
                                    bool ignoreSslErrors,
                                    const QByteArray &trustedCertPem,
                                    const QString &trustedCertPath,
                                    int seq) {
    requestFor(sessionKey, host, port, tokenId, tokenSecret, ignoreSslErrors,
               trustedCertPem, trustedCertPath,
               QStringLiteral("/nodes"), seq, ProxmoxConst::Kind::Nodes, QString());
}

void ProxmoxClient::requestQemuFor(const QString &sessionKey,
                                   const QString &host,
                                   int port,
                                   const QString &tokenId,
                                   const QString &tokenSecret,
                                   bool ignoreSslErrors,
                                   const QByteArray &trustedCertPem,
                                   const QString &trustedCertPath,
                                   const QString &node,
                                   int seq) {
    requestFor(sessionKey, host, port, tokenId, tokenSecret, ignoreSslErrors,
               trustedCertPem, trustedCertPath,
               QStringLiteral("/nodes/%1/qemu").arg(node), seq, ProxmoxConst::Kind::Qemu, node);
}

void ProxmoxClient::requestLxcFor(const QString &sessionKey,
                                  const QString &host,
                                  int port,
                                  const QString &tokenId,
                                  const QString &tokenSecret,
                                  bool ignoreSslErrors,
                                  const QByteArray &trustedCertPem,
                                  const QString &trustedCertPath,
                                  const QString &node,
                                  int seq) {
    requestFor(sessionKey, host, port, tokenId, tokenSecret, ignoreSslErrors,
               trustedCertPem, trustedCertPath,
               QStringLiteral("/nodes/%1/lxc").arg(node), seq, ProxmoxConst::Kind::Lxc, node);
}

void ProxmoxClient::requestActionFor(const QString &sessionKey,
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
                                     int seq) {
    if (kind != ProxmoxConst::Kind::Qemu && kind != ProxmoxConst::Kind::Lxc) {
        emit actionErrorFor(seq, sessionKey, kind, node, vmid, action, QStringLiteral("Invalid kind"));
        return;
    }
    if (action != ProxmoxConst::VmAction::Start
        && action != ProxmoxConst::VmAction::Shutdown
        && action != ProxmoxConst::VmAction::Reboot) {
        emit actionErrorFor(seq, sessionKey, kind, node, vmid, action, QStringLiteral("Invalid action"));
        return;
    }

    postFor(sessionKey,
            host,
            port,
            tokenId,
            tokenSecret,
            ignoreSslErrors,
            trustedCertPem,
            trustedCertPath,
            QStringLiteral("/nodes/%1/%2/%3/status/%4").arg(node).arg(kind).arg(vmid).arg(action),
            seq,
            kind,
            node,
            vmid,
            action);
}

namespace {

// PBS caps namespace nesting at 7 levels, so one listing at this depth
// returns the whole tree for a datastore.
constexpr int PbsMaxNamespaceDepth = 7;

QNetworkRequest buildRequest(const QString &host,
                             int port,
                             const QString &path,
                             const QString &tokenId,
                             const QString &tokenSecret,
                             const QByteArray &trustedCertPem,
                             const QString &trustedCertPath,
                             int transferTimeoutMs = ProxmoxConst::Defaults::RequestTimeoutMs,
                             const QUrlQuery &query = QUrlQuery()) {
    QUrl url(QStringLiteral("https://%1:%2/api2/json%3").arg(host).arg(port).arg(path));
    if (!query.isEmpty()) {
        url.setQuery(query);
    }

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("ProxMon"));
    req.setRawHeader("Accept", "application/json");

    const QList<QSslCertificate> trustedCertificates =
        ProxmoxDataUtils::trustedCertificatesFromConfig(trustedCertPem, trustedCertPath);
    if (!trustedCertificates.isEmpty()) {
        QSslConfiguration sslConfig = QSslConfiguration::defaultConfiguration();
        QList<QSslCertificate> caCertificates = sslConfig.caCertificates();
        caCertificates.append(trustedCertificates);
        sslConfig.setCaCertificates(caCertificates);
        req.setSslConfiguration(sslConfig);
    }

    // Proxmox expects the token pair as "tokenid=secret" (e.g. root@pam!mytoken=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
    // Header format: Authorization: PVEAPIToken=USER@REALM!TOKENID=UUID
    QByteArray auth = QByteArray("PVEAPIToken=") + tokenId.toUtf8() + "=" + tokenSecret.toUtf8();
    req.setRawHeader("Authorization", auth);
    req.setTransferTimeout(transferTimeoutMs);
    auth.fill(0);
    auth.clear();
    return req;
}

// Helper: extract a short message from a JSON error payload if possible (bounded length).
QString extractJsonMessage(const QByteArray &body) {
    QJsonParseError pe;
    const QJsonDocument doc = QJsonDocument::fromJson(body, &pe);
    if (pe.error != QJsonParseError::NoError || doc.isNull() || !doc.isObject()) {
        return {};
    }
    const QJsonObject obj = doc.object();

    // Proxmox sometimes uses "errors" or "message" in responses; best-effort only.
    QString msg;
    if (obj.contains(QStringLiteral("message")) && obj.value(QStringLiteral("message")).isString()) {
        msg = obj.value(QStringLiteral("message")).toString();
    } else if (obj.contains(QStringLiteral("errors")) && obj.value(QStringLiteral("errors")).isString()) {
        msg = obj.value(QStringLiteral("errors")).toString();
    }

    msg = msg.trimmed();
    if (msg.size() > 160) msg = msg.left(160) + QStringLiteral("…");
    return msg;
}

template <typename EmitErr, typename EmitOk>
void handleFinishedReply(QNetworkReply *r,
                         int seq,
                         const QString &kind,
                         const QString &node,
                         const QString &sessionKey,
                         EmitErr emitErr,
                         EmitOk emitOk) {
    const QVariant httpAttr = r->attribute(QNetworkRequest::HttpStatusCodeAttribute);
    const int httpStatus = httpAttr.isValid() ? httpAttr.toInt() : 0;
    const QByteArray body = r->readAll();

    // Qt network error (DNS, TLS, connection refused, etc)
    if (r->error() != QNetworkReply::NoError) {
        // Silent cancels (expected when refresh restarts or watchdog fires)
        if (r->error() == QNetworkReply::OperationCanceledError) {
            r->deleteLater();
            return;
        }

        QString msg = r->errorString();
        const QString jsonMsg = extractJsonMessage(body);
        if (!jsonMsg.isEmpty()) {
            msg += QStringLiteral(" - ") + jsonMsg;
        }
        emitErr(QStringLiteral("%1 (HTTP %2)").arg(msg).arg(httpStatus));
        r->deleteLater();
        return;
    }

    // Some HTTP failures do not set QNetworkReply::error().
    if (httpStatus == 401 || httpStatus == 403) {
        QString msg = QStringLiteral("Authentication failed");
        const QString jsonMsg = extractJsonMessage(body);
        if (!jsonMsg.isEmpty()) {
            msg += QStringLiteral(" - ") + jsonMsg;
        }
        emitErr(QStringLiteral("%1 (HTTP %2)").arg(msg).arg(httpStatus));
        r->deleteLater();
        return;
    }
    if (httpStatus >= 400) {
        QString msg = QStringLiteral("HTTP error");
        const QString jsonMsg = extractJsonMessage(body);
        if (!jsonMsg.isEmpty()) {
            msg += QStringLiteral(" - ") + jsonMsg;
        }
        emitErr(QStringLiteral("%1 (HTTP %2)").arg(msg).arg(httpStatus));
        r->deleteLater();
        return;
    }

    QJsonParseError pe;
    const QJsonDocument doc = QJsonDocument::fromJson(body, &pe);
    if (pe.error != QJsonParseError::NoError || doc.isNull()) {
        emitErr(QStringLiteral("JSON parse error: %1").arg(pe.errorString()));
        r->deleteLater();
        return;
    }

    emitOk(doc.toVariant());
    r->deleteLater();
}

// Best-effort IP extraction. For qemu, parses the QEMU guest agent's
// network-get-interfaces payload (requires the agent installed+running in
// the guest). For lxc, parses the /interfaces endpoint (PVE 7+; container
// must be running). Returns the first non-loopback IPv4 address found, or
// an empty string if none is available.
QString extractIpAddress(const QVariantMap &responseMap, const QString &statsKind) {
    const QVariant dataVariant = responseMap.value(QStringLiteral("data"));
    if (statsKind == ProxmoxConst::Kind::Qemu) {
        const QVariantList interfaces = dataVariant.toMap().value(QStringLiteral("result")).toList();
        for (const QVariant &ifaceVariant : interfaces) {
            const QVariantMap iface = ifaceVariant.toMap();
            if (iface.value(QStringLiteral("name")).toString() == QStringLiteral("lo")) continue;
            const QVariantList addrs = iface.value(QStringLiteral("ip-addresses")).toList();
            for (const QVariant &addrVariant : addrs) {
                const QVariantMap addr = addrVariant.toMap();
                if (addr.value(QStringLiteral("ip-address-type")).toString() != QStringLiteral("ipv4")) continue;
                const QString ip = addr.value(QStringLiteral("ip-address")).toString();
                if (!ip.isEmpty() && !ip.startsWith(QStringLiteral("127."))) {
                    return ip;
                }
            }
        }
        return {};
    }

    // LXC: /nodes/{node}/lxc/{vmid}/interfaces returns a flat list of
    // interfaces, each with an "inet" field like "192.168.1.60/24".
    const QVariantList interfaces = dataVariant.toList();
    for (const QVariant &ifaceVariant : interfaces) {
        const QVariantMap iface = ifaceVariant.toMap();
        if (iface.value(QStringLiteral("name")).toString() == QStringLiteral("lo")) continue;
        const QString inet = iface.value(QStringLiteral("inet")).toString();
        if (!inet.isEmpty()) {
            return inet.section(QLatin1Char('/'), 0, 0);
        }
    }
    return {};
}

} // namespace

void ProxmoxClient::requestFor(const QString &sessionKey,
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
                               const QString &node) {
    if (host.isEmpty() || tokenId.isEmpty() || tokenSecret.isEmpty()) {
        if (sessionKey.isEmpty()) {
            emit error(seq, kind, node, QStringLiteral("Not configured"));
        } else {
            emit errorFor(seq, sessionKey, kind, node, QStringLiteral("Not configured"));
        }
        return;
    }

    QNetworkRequest req = buildRequest(host, port, path, tokenId, tokenSecret,
                                       trustedCertPem, trustedCertPath,
                                       m_lowLatency ? ProxmoxConst::Defaults::LowLatencyTimeoutMs
                                                    : ProxmoxConst::Defaults::RequestTimeoutMs);
    QNetworkReply *r = m_nam.get(req);

    m_refreshInFlight.insert(r);

    if (ignoreSslErrors) {
        QObject::connect(r, &QNetworkReply::sslErrors, r, [r](const QList<QSslError> &) {
            r->ignoreSslErrors();
        });
    }

    QObject::connect(r, &QNetworkReply::finished, this, [this, r, seq, sessionKey, kind, node]() {
        // Remove early so cancelAll() never sees a finished reply.
        m_refreshInFlight.remove(r);

        auto emitErr = [&](const QString &msg) {
            if (sessionKey.isEmpty()) {
                emit error(seq, kind, node, msg);
            } else {
                emit errorFor(seq, sessionKey, kind, node, msg);
            }
        };
        auto emitOk = [&](const QVariant &data) {
            if (sessionKey.isEmpty()) {
                emit reply(seq, kind, node, data);
            } else {
                emit replyFor(seq, sessionKey, kind, node, data);
            }
        };

        handleFinishedReply(r, seq, kind, node, sessionKey, emitErr, emitOk);
    });
}

void ProxmoxClient::postFor(const QString &sessionKey,
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
                            const QString &action) {
    if (host.isEmpty() || tokenId.isEmpty() || tokenSecret.isEmpty()) {
        if (sessionKey.isEmpty()) {
            emit actionError(seq, actionKind, node, vmid, action, QStringLiteral("Not configured"));
        } else {
            emit actionErrorFor(seq, sessionKey, actionKind, node, vmid, action, QStringLiteral("Not configured"));
        }
        return;
    }

    QNetworkRequest req = buildRequest(host, port, path, tokenId, tokenSecret,
                                       trustedCertPem, trustedCertPath,
                                       m_lowLatency ? ProxmoxConst::Defaults::LowLatencyTimeoutMs
                                                    : ProxmoxConst::Defaults::RequestTimeoutMs);

    QNetworkReply *r = m_nam.post(req, QByteArray());
    m_interactiveInFlight.insert(r);

    if (ignoreSslErrors) {
        QObject::connect(r, &QNetworkReply::sslErrors, r, [r](const QList<QSslError> &) {
            r->ignoreSslErrors();
        });
    }

    QObject::connect(r, &QNetworkReply::finished, this, [this, r, seq, sessionKey, host, port, tokenId, tokenSecret, ignoreSslErrors, trustedCertPem, trustedCertPath, actionKind, node, vmid, action]() {
        m_interactiveInFlight.remove(r);

        const QVariant httpAttr = r->attribute(QNetworkRequest::HttpStatusCodeAttribute);
        const int httpStatus = httpAttr.isValid() ? httpAttr.toInt() : 0;
        const QByteArray body = r->readAll();

        auto fail = [&](const QString &msg) {
            const QString full = QStringLiteral("%1 (HTTP %2)").arg(msg).arg(httpStatus);
            if (sessionKey.isEmpty()) {
                emit actionError(seq, actionKind, node, vmid, action, full);
            } else {
                emit actionErrorFor(seq, sessionKey, actionKind, node, vmid, action, full);
            }
            r->deleteLater();
        };

        if (r->error() != QNetworkReply::NoError) {
            if (r->error() == QNetworkReply::OperationCanceledError) {
                r->deleteLater();
                return;
            }
            QString msg = r->errorString();
            const QString jsonMsg = extractJsonMessage(body);
            if (!jsonMsg.isEmpty()) {
                msg += QStringLiteral(" - ") + jsonMsg;
            }
            fail(msg);
            return;
        }

        if (httpStatus == 401 || httpStatus == 403) {
            QString msg = QStringLiteral("Authentication failed");
            const QString jsonMsg = extractJsonMessage(body);
            if (!jsonMsg.isEmpty()) {
                msg += QStringLiteral(" - ") + jsonMsg;
            }
            fail(msg);
            return;
        }
        if (httpStatus >= 400) {
            QString msg = QStringLiteral("HTTP error");
            const QString jsonMsg = extractJsonMessage(body);
            if (!jsonMsg.isEmpty()) {
                msg += QStringLiteral(" - ") + jsonMsg;
            }
            fail(msg);
            return;
        }

        QJsonParseError pe;
        const QJsonDocument doc = QJsonDocument::fromJson(body, &pe);
        if (pe.error != QJsonParseError::NoError || doc.isNull()) {
            fail(QStringLiteral("JSON parse error: %1").arg(pe.errorString()));
            return;
        }

        const QVariant data = doc.toVariant();
        const QString upid = ProxmoxTaskUtils::extractUpid(data);
        if (upid.isEmpty()) {
            if (sessionKey.isEmpty()) {
                emit actionReply(seq, actionKind, node, vmid, action, data);
            } else {
                emit actionReplyFor(seq, sessionKey, actionKind, node, vmid, action, data);
            }
            r->deleteLater();
            return;
        }

        r->deleteLater();
        pollTaskStatus(sessionKey,
                       host,
                       port,
                       tokenId,
                       tokenSecret,
                       ignoreSslErrors,
                       trustedCertPem,
                       trustedCertPath,
                       upid,
                       seq,
                       actionKind,
                       node,
                       vmid,
                       action);
    });
}

void ProxmoxClient::fetchPBSDatastores(const QString &requesterKey,
                                      const QString &pbsHost,
                                      int port,
                                      const QString &tokenId,
                                      const QString &tokenSecret,
                                      bool ignoreSslErrors,
                                      const QByteArray &trustedCertPem,
                                      const QString &trustedCertPath) {
    if (m_debugEnabled) {
        qDebug().noquote()
            << QStringLiteral("[ProxmoxClient] fetchPBSDatastores host=%1 port=%2 tokenIdEmpty=%3 secretEmpty=%4 ignoreSsl=%5")
               .arg(pbsHost,
                    QString::number(port),
                    tokenId.isEmpty()     ? QStringLiteral("true") : QStringLiteral("false"),
                    tokenSecret.isEmpty() ? QStringLiteral("true") : QStringLiteral("false"),
                    ignoreSslErrors       ? QStringLiteral("true") : QStringLiteral("false"));
    }
    if (pbsHost.isEmpty() || tokenId.isEmpty() || tokenSecret.isEmpty()) {
        emit pbsDatastoresError(pbsHost, QStringLiteral("Not configured"));
        return;
    }

    // Resolve the cert once here; all per-datastore snapshot requests reuse
    // the same bytes so loadTrustedCertificates doesn't re-read the file for
    // each datastore.
    const QByteArray resolvedCertPem = trustedCertPem.isEmpty() && !trustedCertPath.trimmed().isEmpty()
        ? [&]() -> QByteArray {
              QFile f(trustedCertPath.trimmed());
              return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
        }()
        : trustedCertPem;
    QByteArray pbsSecret = tokenSecret.toUtf8();

    QNetworkRequest req = buildRequest(pbsHost, port, QStringLiteral("/admin/datastore"),
                                       tokenId, QString(), resolvedCertPem, QString(),
                                       m_lowLatency ? ProxmoxConst::Defaults::LowLatencyTimeoutMs
                                                    : ProxmoxConst::Defaults::RequestTimeoutMs);
    QByteArray authorization = QByteArray("PBSAPIToken=") + tokenId.toUtf8() + ":" + pbsSecret;
    req.setRawHeader("Authorization", authorization);
    authorization.fill(0);
    authorization.clear();

    QNetworkReply *r = m_nam.get(req);
    m_pbsInFlight.insert(r);

    if (ignoreSslErrors) {
        QObject::connect(r, &QNetworkReply::sslErrors, r, [r](const QList<QSslError> &) {
            r->ignoreSslErrors();
        });
    }

    QObject::connect(r, &QNetworkReply::finished, this,
                     [this, r, requesterKey, pbsHost, port, tokenId, pbsSecret = std::move(pbsSecret),
                      ignoreSslErrors, resolvedCertPem]() mutable {
        auto clearSecret = [&pbsSecret]() {
            pbsSecret.fill(0);
            pbsSecret.clear();
        };
        if (!m_pbsInFlight.remove(r)) {
            clearSecret();
            r->deleteLater();
            return;
        }

        auto emitErr = [&](const QString &msg) {
            if (m_debugEnabled) qDebug().noquote() << QStringLiteral("[ProxmoxClient] fetchPBSDatastores error host=%1 message=%2").arg(pbsHost, msg);
            emit pbsDatastoresError(pbsHost, msg);
        };
        auto emitOk = [&](const QVariant &data) {
            if (m_debugEnabled) qDebug().noquote() << QStringLiteral("[ProxmoxClient] fetchPBSDatastores ok host=%1").arg(pbsHost);
            QStringList datastores;
            const QVariantList rows = data.toMap().value(QStringLiteral("data")).toList();
            for (const QVariant &rowValue : rows) {
                const QVariantMap row = rowValue.toMap();
                const QString store = row.value(QStringLiteral("store")).toString().trimmed();
                if (!store.isEmpty()) {
                    datastores.push_back(store);
                }
            }
            emit pbsDatastoresReceived(pbsHost, datastores);
            for (const QString &datastore : datastores) {
                const QString encodedStore = QString::fromUtf8(QUrl::toPercentEncoding(datastore));

                // The snapshots endpoint has no max-depth of its own, so the
                // namespace tree is enumerated here and fanned out into one
                // snapshots request per namespace.
                QUrlQuery nsQuery;
                nsQuery.addQueryItem(QStringLiteral("max-depth"), QString::number(PbsMaxNamespaceDepth));
                QNetworkRequest nsReq = buildRequest(pbsHost,
                                                     port,
                                                     QStringLiteral("/admin/datastore/%1/namespace").arg(encodedStore),
                                                     tokenId,
                                                     QString(),
                                                     resolvedCertPem,
                                                     QString(),
                                                     m_lowLatency ? ProxmoxConst::Defaults::LowLatencyTimeoutMs : ProxmoxConst::Defaults::RequestTimeoutMs,
                                                     nsQuery);
                QByteArray nsAuthorization = QByteArray("PBSAPIToken=") + tokenId.toUtf8() + ":" + pbsSecret;
                nsReq.setRawHeader("Authorization", nsAuthorization);
                nsAuthorization.fill(0);
                nsAuthorization.clear();

                QNetworkReply *nsReply = m_nam.get(nsReq);
                m_pbsInFlight.insert(nsReply);
                if (ignoreSslErrors) {
                    QObject::connect(nsReply, &QNetworkReply::sslErrors, nsReply, [nsReply](const QList<QSslError> &) {
                        nsReply->ignoreSslErrors();
                    });
                }

                // Snapshot requests are issued from this callback, which runs
                // after the enclosing datastore callback has zeroed its own
                // copy, so this tier needs a copy it zeroes itself.
                QByteArray secretForNs = pbsSecret;
                QObject::connect(nsReply, &QNetworkReply::finished, this,
                                 [this, nsReply, requesterKey, pbsHost, port, tokenId, datastore, encodedStore,
                                  nsSecret = std::move(secretForNs), ignoreSslErrors, resolvedCertPem]() mutable {
                    auto clearNsSecret = [&nsSecret]() {
                        nsSecret.fill(0);
                        nsSecret.clear();
                    };
                    if (!m_pbsInFlight.remove(nsReply)) {
                        clearNsSecret();
                        nsReply->deleteLater();
                        return;
                    }

                    auto requestSnapshots = [&](const QList<QString> &namespaces) {
                        // Emitted before the requests exist so a listener can
                        // count them in the same slot; the pending total must
                        // never hit zero while work is still to be issued.
                        emit pbsNamespacesReceived(pbsHost, datastore, namespaces);
                        for (const QString &backupNs : namespaces) {
                            QUrlQuery snapshotQuery;
                            if (!backupNs.isEmpty()) {
                                snapshotQuery.addQueryItem(QStringLiteral("ns"), backupNs);
                            }
                            QNetworkRequest snapshotReq = buildRequest(pbsHost,
                                                                       port,
                                                                       QStringLiteral("/admin/datastore/%1/snapshots").arg(encodedStore),
                                                                       tokenId,
                                                                       QString(),
                                                                       resolvedCertPem,
                                                                       QString(),
                                                                       m_lowLatency ? ProxmoxConst::Defaults::LowLatencyTimeoutMs : ProxmoxConst::Defaults::RequestTimeoutMs,
                                                                       snapshotQuery);
                            QByteArray snapshotAuthorization = QByteArray("PBSAPIToken=") + tokenId.toUtf8() + ":" + nsSecret;
                            snapshotReq.setRawHeader("Authorization", snapshotAuthorization);
                            snapshotAuthorization.fill(0);
                            snapshotAuthorization.clear();

                            QNetworkReply *snapshotReply = m_nam.get(snapshotReq);
                            m_pbsInFlight.insert(snapshotReply);
                            if (ignoreSslErrors) {
                                QObject::connect(snapshotReply, &QNetworkReply::sslErrors, snapshotReply, [snapshotReply](const QList<QSslError> &) {
                                    snapshotReply->ignoreSslErrors();
                                });
                            }

                            QObject::connect(snapshotReply, &QNetworkReply::finished, this, [this, snapshotReply, requesterKey, pbsHost, datastore, backupNs]() {
                                if (!m_pbsInFlight.remove(snapshotReply)) {
                                    snapshotReply->deleteLater();
                                    return;
                                }
                                auto emitSnapErr = [&](const QString &msg) {
                                    if (m_debugEnabled) qDebug().noquote() << QStringLiteral("[ProxmoxClient] fetchPBSSnapshots error host=%1 datastore=%2 ns=%3 message=%4").arg(pbsHost, datastore, backupNs, msg);
                                    emit pbsSnapshotsError(pbsHost, datastore, msg);
                                };
                                auto emitSnapOk = [&](const QVariant &snapData) {
                                    if (m_debugEnabled) qDebug().noquote() << QStringLiteral("[ProxmoxClient] fetchPBSSnapshots ok host=%1 datastore=%2 ns=%3").arg(pbsHost, datastore, backupNs);
                                    QList<PBSSnapshot> snapshots;
                                    const QVariantList rows = snapData.toMap().value(QStringLiteral("data")).toList();
                                    for (const QVariant &rowValue : rows) {
                                        const QVariantMap row = rowValue.toMap();
                                        bool vmidOk = false;
                                        const int vmid = row.value(QStringLiteral("backup-id")).toString().toInt(&vmidOk);
                                        if (!vmidOk) {
                                            continue;
                                        }
                                        PBSSnapshot snapshot;
                                        snapshot.vmid = vmid;
                                        snapshot.backupType = row.value(QStringLiteral("backup-type")).toString();
                                        snapshot.backupTime = row.value(QStringLiteral("backup-time")).toLongLong();
                                        snapshot.size = row.value(QStringLiteral("size")).toLongLong();
                                        snapshot.verifyState = row.value(QStringLiteral("verification")).toMap().value(QStringLiteral("state")).toString();
                                        snapshot.datastoreName = datastore;
                                        snapshot.backupNamespace = backupNs;
                                        snapshot.pbsHost = pbsHost;
                                        snapshots.push_back(snapshot);
                                    }
                                    emit pbsSnapshotsReceived(requesterKey, pbsHost, datastore, snapshots);
                                };
                                handleFinishedReply(snapshotReply, 0, QStringLiteral("pbs-snapshots"), datastore, QString(), emitSnapErr, emitSnapOk);
                            });
                        }
                    };

                    auto emitNsErr = [&](const QString &msg) {
                        if (m_debugEnabled) qDebug().noquote() << QStringLiteral("[ProxmoxClient] fetchPBSNamespaces error host=%1 datastore=%2 message=%3 falling back to root").arg(pbsHost, datastore, msg);
                        // A token without namespace-listing privilege, or a PBS
                        // predating the endpoint, must still yield root-namespace
                        // data rather than an empty backup panel.
                        requestSnapshots({QString()});
                    };
                    auto emitNsOk = [&](const QVariant &nsData) {
                        const QList<QString> namespaces = ProxmoxDataUtils::parsePbsNamespaces(nsData);
                        if (m_debugEnabled) qDebug().noquote() << QStringLiteral("[ProxmoxClient] fetchPBSNamespaces ok host=%1 datastore=%2 count=%3").arg(pbsHost, datastore).arg(namespaces.size());
                        requestSnapshots(namespaces);
                    };
                    handleFinishedReply(nsReply, 0, QStringLiteral("pbs-namespaces"), datastore, QString(), emitNsErr, emitNsOk);
                    clearNsSecret();
                });
            }
        };

        handleFinishedReply(r, 0, QStringLiteral("pbs-datastores"), QString(), QString(), emitErr, emitOk);
        clearSecret();
    });
}

void ProxmoxClient::pollTaskStatus(const QString &sessionKey,
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
                                   const QString &action) {
    if (upid.isEmpty()) {
        if (sessionKey.isEmpty()) {
            emit actionError(seq, actionKind, node, vmid, action, QStringLiteral("Missing task id"));
        } else {
            emit actionErrorFor(seq, sessionKey, actionKind, node, vmid, action, QStringLiteral("Missing task id"));
        }
        return;
    }

    const QString path = QStringLiteral("/nodes/%1/tasks/%2/status").arg(node, upid);
    QNetworkRequest req = buildRequest(host, port, path, tokenId, tokenSecret,
                                       trustedCertPem, trustedCertPath,
                                       m_lowLatency ? ProxmoxConst::Defaults::LowLatencyTimeoutMs
                                                    : ProxmoxConst::Defaults::RequestTimeoutMs);
    QNetworkReply *r = m_nam.get(req);
    m_taskInFlight.insert(r);

    if (ignoreSslErrors) {
        QObject::connect(r, &QNetworkReply::sslErrors, r, [r](const QList<QSslError> &) {
            r->ignoreSslErrors();
        });
    }

    QObject::connect(r, &QNetworkReply::finished, this, [this, r, sessionKey, host, port, tokenId, tokenSecret, ignoreSslErrors, trustedCertPem, trustedCertPath, upid, seq, actionKind, node, vmid, action]() {
        m_taskInFlight.remove(r);

        auto emitTaskError = [&](const QString &msg) {
            if (sessionKey.isEmpty()) {
                emit actionError(seq, actionKind, node, vmid, action, msg);
            } else {
                emit actionErrorFor(seq, sessionKey, actionKind, node, vmid, action, msg);
            }
        };
        auto emitTaskReply = [&](const QVariant &data) {
            if (sessionKey.isEmpty()) {
                emit actionReply(seq, actionKind, node, vmid, action, data);
            } else {
                emit actionReplyFor(seq, sessionKey, actionKind, node, vmid, action, data);
            }
        };

        handleFinishedReply(r,
                            seq,
                            QStringLiteral("task-status"),
                            node,
                            sessionKey,
                            emitTaskError,
                            [&, this](const QVariant &data) {
                                if (ProxmoxTaskUtils::isRunning(data)) {
                                    auto *timer = new QTimer(this);
                                    timer->setSingleShot(true);
                                    timer->setInterval(ProxmoxConst::Defaults::TaskPollIntervalMs);
                                    m_taskPollTimers.insert(timer);
                                    QObject::connect(timer,
                                                     &QTimer::timeout,
                                                     this,
                                                     [this, timer, sessionKey, host, port, tokenId,
                                                      tokenSecret, ignoreSslErrors, trustedCertPem,
                                                      trustedCertPath, upid, seq, actionKind, node,
                                                      vmid, action]() {
                                        m_taskPollTimers.remove(timer);
                                        timer->deleteLater();
                                        pollTaskStatus(sessionKey,
                                                       host,
                                                       port,
                                                       tokenId,
                                                       tokenSecret,
                                                       ignoreSslErrors,
                                                       trustedCertPem,
                                                       trustedCertPath,
                                                       upid,
                                                       seq,
                                                       actionKind,
                                                       node,
                                                       vmid,
                                                       action);
                                    });
                                    timer->start();
                                    return;
                                }

                                const QString exitMessage = ProxmoxTaskUtils::exitMessage(data);
                                if (!exitMessage.isEmpty()) {
                                    emitTaskError(exitMessage);
                                    return;
                                }

                                emitTaskReply(data);
                            });
    });
}

void ProxmoxClient::requestStatsFor(const QString &sessionKey,
                                    const QString &host,
                                    int port,
                                    const QString &tokenId,
                                    const QString &tokenSecret,
                                    bool ignoreSslErrors,
                                    const QByteArray &trustedCertPem,
                                    const QString &trustedCertPath,
                                    const QString &statsKind,
                                    const QString &node,
                                    int vmid,
                                    int seq) {
    Q_UNUSED(seq)
    if (host.isEmpty() || tokenId.isEmpty() || tokenSecret.isEmpty()) {
        emit statsError(sessionKey, node, vmid, QStringLiteral("credentials unavailable"));
        return;
    }

    // Two independent requests feed one combined result: RRD history for the
    // graph, and a best-effort IP lookup. Either leg can fail on its own
    // (e.g. no guest agent installed) without failing the whole call - only
    // report an error if *both* legs come back empty.
    auto result = QSharedPointer<QVariantMap>::create();
    auto pending = QSharedPointer<int>::create(2);
    auto anyOk = QSharedPointer<bool>::create(false);

    auto finishOne = [this, result, pending, anyOk, sessionKey, statsKind, node, vmid]() {
        if (--(*pending) > 0) return;
        if (!*anyOk) {
            emit statsError(sessionKey, node, vmid, QStringLiteral("failed to fetch stats"));
            return;
        }
        emit statsReady(sessionKey, statsKind, node, vmid, QVariant(*result));
    };

    // Leg 1: RRD history (last hour, averaged samples) for the sparkline.
    {
        const QString path = QStringLiteral("/nodes/%1/%2/%3/rrddata?timeframe=hour&cf=AVERAGE")
                                  .arg(node).arg(statsKind).arg(vmid);
        QNetworkRequest req = buildRequest(host, port, path, tokenId, tokenSecret, trustedCertPem, trustedCertPath);
        QNetworkReply *reply = m_nam.get(req);
        m_interactiveInFlight.insert(reply);
        if (ignoreSslErrors) {
            connect(reply, &QNetworkReply::sslErrors, reply, [reply](const QList<QSslError> &) {
                reply->ignoreSslErrors();
            });
        }
        QObject::connect(reply, &QNetworkReply::finished, this,
            [this, reply, result, anyOk, finishOne]() {
                m_interactiveInFlight.remove(reply);
                if (reply->error() == QNetworkReply::NoError) {
                    const QByteArray body = reply->readAll();
                    QJsonParseError pe;
                    const QJsonDocument doc = QJsonDocument::fromJson(body, &pe);
                    if (pe.error == QJsonParseError::NoError) {
                        (*result)[QStringLiteral("rrd")] =
                            doc.toVariant().toMap().value(QStringLiteral("data")).toList();
                        *anyOk = true;
                    }
                }
                reply->deleteLater();
                finishOne();
            });
    }

    // Leg 2: best-effort IP address lookup. 404s/timeouts here are expected
    // (agent not installed, container stopped) and are not treated as a
    // hard failure - the RRD leg can still carry the overall result.
    {
        const QString path = statsKind == ProxmoxConst::Kind::Qemu
            ? QStringLiteral("/nodes/%1/qemu/%2/agent/network-get-interfaces").arg(node).arg(vmid)
            : QStringLiteral("/nodes/%1/lxc/%2/interfaces").arg(node).arg(vmid);
        QNetworkRequest req = buildRequest(host, port, path, tokenId, tokenSecret, trustedCertPem, trustedCertPath);
        QNetworkReply *reply = m_nam.get(req);
        m_interactiveInFlight.insert(reply);
        if (ignoreSslErrors) {
            connect(reply, &QNetworkReply::sslErrors, reply, [reply](const QList<QSslError> &) {
                reply->ignoreSslErrors();
            });
        }
        QObject::connect(reply, &QNetworkReply::finished, this,
            [this, reply, result, anyOk, finishOne, statsKind]() {
                m_interactiveInFlight.remove(reply);
                if (reply->error() == QNetworkReply::NoError) {
                    const QByteArray body = reply->readAll();
                    QJsonParseError pe;
                    const QJsonDocument doc = QJsonDocument::fromJson(body, &pe);
                    if (pe.error == QJsonParseError::NoError) {
                        const QString ip = extractIpAddress(doc.toVariant().toMap(), statsKind);
                        if (!ip.isEmpty()) {
                            (*result)[QStringLiteral("ip")] = ip;
                            *anyOk = true;
                        }
                    }
                }
                reply->deleteLater();
                finishOne();
            });
    }
}

void ProxmoxClient::requestVncProxy(const QString &sessionKey,
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
                                     int vmid)
{
    if (host.isEmpty() || tokenId.isEmpty() || tokenSecret.isEmpty()) {
        emit vncProxyError(sessionKey, requestId, node, kind, vmid, QStringLiteral("Not configured"));
        return;
    }

    const QString path = QStringLiteral("/nodes/%1/%2/%3/vncproxy").arg(node).arg(kind).arg(vmid);

    QNetworkRequest req = buildRequest(host, port, path, tokenId, tokenSecret,trustedCertPem, trustedCertPath);

    QByteArray body;
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/x-www-form-urlencoded");

    QNetworkReply *r = m_nam.post(req, body);
    m_interactiveInFlight.insert(r);

    if (ignoreSslErrors) {
        QObject::connect(r, &QNetworkReply::sslErrors, r, [r](const QList<QSslError> &) {
            r->ignoreSslErrors();
        });
    }

    // Build auth header now while tokenId/secret are in scope; the
    // vncwebsocket WebSocket upgrade needs it (same pattern as ttyProxy).
    const QByteArray authHeader = QByteArray("PVEAPIToken=") + tokenId.toUtf8()
                                  + "=" + tokenSecret.toUtf8();

    QObject::connect(r, &QNetworkReply::finished, this,
        [this, r, sessionKey, requestId, host, port, node, kind, vmid, authHeader, ignoreSslErrors]() {
            m_interactiveInFlight.remove(r);

            const QVariant httpAttr = r->attribute(QNetworkRequest::HttpStatusCodeAttribute);
            const int httpStatus = httpAttr.isValid() ? httpAttr.toInt() : 0;
            const QByteArray body = r->readAll();

            auto fail = [&](const QString &msg) {
                emit vncProxyError(sessionKey, requestId, node, kind, vmid,
                                   QStringLiteral("%1 (HTTP %2)").arg(msg).arg(httpStatus));
                r->deleteLater();
            };

            if (r->error() != QNetworkReply::NoError) {
                if (r->error() == QNetworkReply::OperationCanceledError) {
                    r->deleteLater();
                    return;
                }
                fail(r->errorString());
                return;
            }

            if (httpStatus >= 400) {
                fail(QStringLiteral("HTTP error"));
                return;
            }

            QJsonParseError pe;
            const QJsonDocument doc = QJsonDocument::fromJson(body, &pe);
            if (pe.error != QJsonParseError::NoError || doc.isNull()) {
                fail(QStringLiteral("JSON parse error: %1").arg(pe.errorString()));
                return;
            }

            const QVariantMap data = doc.toVariant().toMap()
                                         .value(QStringLiteral("data")).toMap();
            const int vncPort   = data.value(QStringLiteral("port")).toInt();
            const QString ticket = data.value(QStringLiteral("ticket")).toString();

            if (ticket.isEmpty() || vncPort == 0) {
                fail(QStringLiteral("Invalid vncproxy response"));
                return;
            }

            emit vncProxyReady(sessionKey, requestId, host, node, kind, vmid, vncPort, ticket,
                               port, authHeader, ignoreSslErrors);
            r->deleteLater();
        });
}

void ProxmoxClient::requestTtyProxy(const QString &sessionKey,
                                    const QString &requestId,
                                    const QString &host,
                                    int port,
                                    const QString &tokenId,
                                    const QString &tokenSecret,
                                    bool ignoreSslErrors,
                                    const QByteArray &trustedCertPem,
                                    const QString &trustedCertPath,
                                    const QString &node,
                                    int vmid)
{
    if (host.isEmpty() || tokenId.isEmpty() || tokenSecret.isEmpty()) {
        emit ttyProxyError(sessionKey, requestId, node, vmid, QStringLiteral("Not configured"));
        return;
    }

    // Proxmox endpoint is /termproxy (not /tty). Returns:
    //   { port, ticket, user, upid }
    // We need user + ticket for the websocket auth handshake.
    const QString path = QStringLiteral("/nodes/%1/lxc/%2/termproxy")
                             .arg(node).arg(vmid);

    QNetworkRequest req = buildRequest(host, port, path, tokenId, tokenSecret,
                                       trustedCertPem, trustedCertPath);

    QByteArray body;
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/x-www-form-urlencoded");

    QNetworkReply *r = m_nam.post(req, body);
    m_interactiveInFlight.insert(r);

    if (ignoreSslErrors) {
        QObject::connect(r, &QNetworkReply::sslErrors, r, [r](const QList<QSslError> &) {
            r->ignoreSslErrors();
        });
    }

    // Pre-build the auth header now while we still have tokenId+secret in
    // scope; the vncwebsocket upgrade needs the same one.
    const QByteArray authHeader = QByteArray("PVEAPIToken=") + tokenId.toUtf8()
                                  + "=" + tokenSecret.toUtf8();

    QObject::connect(r, &QNetworkReply::finished, this,
        [this, r, sessionKey, requestId, host, node, vmid, authHeader]() {
            m_interactiveInFlight.remove(r);

            const QVariant httpAttr = r->attribute(QNetworkRequest::HttpStatusCodeAttribute);
            const int httpStatus = httpAttr.isValid() ? httpAttr.toInt() : 0;
            const QByteArray body = r->readAll();

            auto fail = [&](const QString &msg) {
                emit ttyProxyError(sessionKey, requestId, node, vmid,
                                   QStringLiteral("%1 (HTTP %2)").arg(msg).arg(httpStatus));
                r->deleteLater();
            };

            if (r->error() != QNetworkReply::NoError) {
                if (r->error() == QNetworkReply::OperationCanceledError) {
                    r->deleteLater();
                    return;
                }
                fail(r->errorString());
                return;
            }

            if (httpStatus >= 400) {
                fail(QStringLiteral("HTTP error"));
                return;
            }

            QJsonParseError pe;
            const QJsonDocument doc = QJsonDocument::fromJson(body, &pe);
            if (pe.error != QJsonParseError::NoError || doc.isNull()) {
                fail(QStringLiteral("JSON parse error: %1").arg(pe.errorString()));
                return;
            }

            const QVariantMap data = doc.toVariant().toMap()
                                         .value(QStringLiteral("data")).toMap();
            const int ttyPort   = data.value(QStringLiteral("port")).toInt();
            const QString ticket = data.value(QStringLiteral("ticket")).toString();
            const QString user  = data.value(QStringLiteral("user")).toString();

            if (ticket.isEmpty() || ttyPort == 0) {
                fail(QStringLiteral("Invalid termproxy response"));
                return;
            }

            emit ttyProxyReady(sessionKey, requestId, host, node, vmid, ttyPort, ticket, user, authHeader);
            r->deleteLater();
        });
}

void ProxmoxClient::requestNodeTermProxy(const QString &sessionKey,
                                         const QString &requestId,
                                         const QString &host,
                                         int port,
                                         const QString &tokenId,
                                         const QString &tokenSecret,
                                         bool ignoreSslErrors,
                                         const QByteArray &trustedCertPem,
                                         const QString &trustedCertPath,
                                         const QString &node)
{
    if (host.isEmpty() || tokenId.isEmpty() || tokenSecret.isEmpty()) {
        emit nodeTermProxyError(sessionKey, requestId, node, QStringLiteral("Not configured"));
        return;
    }

    const QString path = QStringLiteral("/nodes/%1/termproxy").arg(node);

    QNetworkRequest req = buildRequest(host, port, path, tokenId, tokenSecret,
                                       trustedCertPem, trustedCertPath);

    QByteArray body;
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/x-www-form-urlencoded");

    QNetworkReply *r = m_nam.post(req, body);
    m_interactiveInFlight.insert(r);

    if (ignoreSslErrors) {
        QObject::connect(r, &QNetworkReply::sslErrors, r, [r](const QList<QSslError> &) {
            r->ignoreSslErrors();
        });
    }

    const QByteArray authHeader = QByteArray("PVEAPIToken=") + tokenId.toUtf8()
                                  + "=" + tokenSecret.toUtf8();

    QObject::connect(r, &QNetworkReply::finished, this,
        [this, r, sessionKey, requestId, host, node, authHeader]() {
            m_interactiveInFlight.remove(r);

            const QVariant httpAttr = r->attribute(QNetworkRequest::HttpStatusCodeAttribute);
            const int httpStatus = httpAttr.isValid() ? httpAttr.toInt() : 0;
            const QByteArray body = r->readAll();

            auto fail = [&](const QString &msg) {
                emit nodeTermProxyError(sessionKey, requestId, node,
                                        QStringLiteral("%1 (HTTP %2)").arg(msg).arg(httpStatus));
                r->deleteLater();
            };

            if (r->error() != QNetworkReply::NoError) {
                if (r->error() == QNetworkReply::OperationCanceledError) {
                    r->deleteLater();
                    return;
                }
                fail(r->errorString());
                return;
            }

            if (httpStatus >= 400) {
                fail(QStringLiteral("HTTP error"));
                return;
            }

            QJsonParseError pe;
            const QJsonDocument doc = QJsonDocument::fromJson(body, &pe);
            if (pe.error != QJsonParseError::NoError || doc.isNull()) {
                fail(QStringLiteral("JSON parse error: %1").arg(pe.errorString()));
                return;
            }

            const QVariantMap data = doc.toVariant().toMap()
                                         .value(QStringLiteral("data")).toMap();
            const int ttyPort    = data.value(QStringLiteral("port")).toInt();
            const QString ticket = data.value(QStringLiteral("ticket")).toString();
            const QString user   = data.value(QStringLiteral("user")).toString();

            if (ticket.isEmpty() || ttyPort == 0) {
                fail(QStringLiteral("Invalid termproxy response"));
                return;
            }

            emit nodeTermProxyReady(sessionKey, requestId, host, node, ttyPort, ticket, user, authHeader);
            r->deleteLater();
        });
}
