#include "proxmoxclient.h"
#include "proxmoxconsts.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QSslCertificate>
#include <QSslConfiguration>
#include <QUrl>

ProxmoxClient::ProxmoxClient(QObject *parent)
    : QObject(parent) {}

ProxmoxClient::~ProxmoxClient() {
    cancelAll();
}

void ProxmoxClient::cancelAll() {
    // Abort any outstanding requests to avoid late reply storms and wasted work.
    //
    // QNetworkReply::abort() emits finished() (Qt docs), so snapshot first to avoid
    // iterating while callbacks remove from m_inFlight.
    const auto pbsReplies = m_pbsInFlight.values();
    m_pbsInFlight.clear();
    const auto replies = m_inFlight.values();
    m_inFlight.clear();

    for (QNetworkReply *r : replies) {
        if (r) {
            r->abort();
        }
    }
}

void ProxmoxClient::cancelPVE() {
    const auto replies = m_inFlight.values();
    m_inFlight.clear();
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

void ProxmoxClient::setHost(const QString &v) {
    if (m_host == v) return;
    m_host = v;
    emit hostChanged();
}

void ProxmoxClient::setPort(int v) {
    if (m_port == v) return;
    m_port = v;
    emit portChanged();
}

void ProxmoxClient::setTokenId(const QString &v) {
    if (m_tokenId == v) return;
    m_tokenId = v;
    emit tokenIdChanged();
}

void ProxmoxClient::setTokenSecret(const QString &v) {
    if (m_tokenSecret == v) return;
    m_tokenSecret = v;
    emit tokenSecretChanged();
}

void ProxmoxClient::setIgnoreSslErrors(bool v) {
    if (m_ignoreSslErrors == v) return;
    m_ignoreSslErrors = v;
    emit ignoreSslErrorsChanged();
}

void ProxmoxClient::setDebugEnabled(bool value) {
    if (m_debugEnabled == value) return;
    m_debugEnabled = value;
    emit debugEnabledChanged();
}

void ProxmoxClient::setTrustedCertPem(const QString &v) {
    if (m_trustedCertPem == v) return;
    m_trustedCertPem = v;
    emit trustedCertPemChanged();
}

void ProxmoxClient::setTrustedCertPath(const QString &v) {
    if (m_trustedCertPath == v) return;
    m_trustedCertPath = v;
    emit trustedCertPathChanged();
}

void ProxmoxClient::requestNodes(int seq) {
    request(QStringLiteral("/nodes"), seq, ProxmoxConst::Kind::Nodes, QString());
}

void ProxmoxClient::requestQemu(const QString &node, int seq) {
    request(QStringLiteral("/nodes/%1/qemu").arg(node), seq, ProxmoxConst::Kind::Qemu, node);
}

void ProxmoxClient::requestLxc(const QString &node, int seq) {
    request(QStringLiteral("/nodes/%1/lxc").arg(node), seq, ProxmoxConst::Kind::Lxc, node);
}

void ProxmoxClient::setLowLatency(bool v) {
    if (m_lowLatency == v) return;
    m_lowLatency = v;
    emit lowLatencyChanged();
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

void ProxmoxClient::requestAction(const QString &kind, const QString &node, int vmid, const QString &action, int seq) {
    if (kind != ProxmoxConst::Kind::Qemu && kind != ProxmoxConst::Kind::Lxc) {
        emit actionError(seq, kind, node, vmid, action, QStringLiteral("Invalid kind"));
        return;
    }
    if (action != ProxmoxConst::VmAction::Start
        && action != ProxmoxConst::VmAction::Shutdown
        && action != ProxmoxConst::VmAction::Reboot) {
        emit actionError(seq, kind, node, vmid, action, QStringLiteral("Invalid action"));
        return;
    }

    post(QStringLiteral("/nodes/%1/%2/%3/status/%4").arg(node).arg(kind).arg(vmid).arg(action),
         seq,
         kind,
         node,
         vmid,
         action);
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

QList<QSslCertificate> loadTrustedCertificates(const QByteArray &trustedCertPem, const QString &trustedCertPath) {
    QByteArray source = trustedCertPem;
    if (source.isEmpty() && !trustedCertPath.trimmed().isEmpty()) {
        QFile file(trustedCertPath.trimmed());
        if (file.open(QIODevice::ReadOnly)) {
            source = file.readAll();
        }
    }
    if (source.isEmpty()) {
        return {};
    }
    return QSslCertificate::fromData(source, QSsl::Pem);
}

QNetworkRequest buildRequest(const QString &host,
                             int port,
                             const QString &path,
                             const QString &tokenId,
                             const QString &tokenSecret,
                             const QByteArray &trustedCertPem,
                             const QString &trustedCertPath,
                             int transferTimeoutMs = ProxmoxConst::Defaults::RequestTimeoutMs) {
    const QUrl url(QStringLiteral("https://%1:%2/api2/json%3").arg(host).arg(port).arg(path));

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("ProxMon"));
    req.setRawHeader("Accept", "application/json");

    const QList<QSslCertificate> trustedCertificates = loadTrustedCertificates(trustedCertPem, trustedCertPath);
    if (!trustedCertificates.isEmpty()) {
        QSslConfiguration sslConfig = QSslConfiguration::defaultConfiguration();
        QList<QSslCertificate> caCertificates = sslConfig.caCertificates();
        caCertificates.append(trustedCertificates);
        sslConfig.setCaCertificates(caCertificates);
        req.setSslConfiguration(sslConfig);
    }

    // Proxmox expects the token pair as "tokenid=secret" (e.g. root@pam!mytoken=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
    // Header format: Authorization: PVEAPIToken=USER@REALM!TOKENID=UUID
    const QByteArray auth = QByteArray("PVEAPIToken=") + tokenId.toUtf8() + "=" + tokenSecret.toUtf8();
    req.setRawHeader("Authorization", auth);
    req.setTransferTimeout(transferTimeoutMs);
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

QString extractTaskUpid(const QVariant &data) {
    const QVariantMap map = data.toMap();
    const QVariant value = map.value(QStringLiteral("data"));
    if (value.metaType().id() == QMetaType::QString) {
        return value.toString().trimmed();
    }
    return {};
}

QString extractTaskExitMessage(const QVariant &data) {
    const QVariantMap root = data.toMap();
    const QVariantMap payload = root.value(QStringLiteral("data")).toMap();
    QString exitStatus = payload.value(QStringLiteral("exitstatus")).toString().trimmed();
    QString status = payload.value(QStringLiteral("status")).toString().trimmed();

    if (exitStatus.compare(QStringLiteral("OK"), Qt::CaseInsensitive) == 0
        || exitStatus.compare(QStringLiteral("TASK OK"), Qt::CaseInsensitive) == 0) {
        return {};
    }
    if (!exitStatus.isEmpty()) {
        return exitStatus;
    }
    if (status.compare(ProxmoxConst::Status::Stopped, Qt::CaseInsensitive) == 0) {
        return QStringLiteral("Task stopped without success");
    }
    return {};
}

bool taskStillRunning(const QVariant &data) {
    const QVariantMap root = data.toMap();
    const QVariantMap payload = root.value(QStringLiteral("data")).toMap();
    const QString status = payload.value(QStringLiteral("status")).toString().trimmed();
    return status.compare(ProxmoxConst::Status::Running, Qt::CaseInsensitive) == 0;
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

} // namespace

void ProxmoxClient::request(const QString &path, int seq, const QString &kind, const QString &node) {
    requestFor(QString(),
               m_host,
               m_port,
               m_tokenId,
               m_tokenSecret,
               m_ignoreSslErrors,
               m_trustedCertPem.toUtf8(),
               m_trustedCertPath,
               path,
               seq,
               kind,
               node);
}

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

    m_inFlight.insert(r);

    if (ignoreSslErrors) {
        QObject::connect(r, &QNetworkReply::sslErrors, r, [r](const QList<QSslError> &) {
            r->ignoreSslErrors();
        });
    }

    QObject::connect(r, &QNetworkReply::finished, this, [this, r, seq, sessionKey, kind, node]() {
        // Remove early so cancelAll() never sees a finished reply.
        m_inFlight.remove(r);

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

void ProxmoxClient::post(const QString &path, int seq, const QString &actionKind, const QString &node, int vmid, const QString &action) {
    postFor(QString(),
            m_host,
            m_port,
            m_tokenId,
            m_tokenSecret,
            m_ignoreSslErrors,
            m_trustedCertPem.toUtf8(),
            m_trustedCertPath,
            path,
            seq,
            actionKind,
            node,
            vmid,
            action);
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
    m_inFlight.insert(r);

    if (ignoreSslErrors) {
        QObject::connect(r, &QNetworkReply::sslErrors, r, [r](const QList<QSslError> &) {
            r->ignoreSslErrors();
        });
    }

    QObject::connect(r, &QNetworkReply::finished, this, [this, r, seq, sessionKey, host, port, tokenId, tokenSecret, ignoreSslErrors, trustedCertPem, trustedCertPath, actionKind, node, vmid, action]() {
        m_inFlight.remove(r);

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
        const QString upid = extractTaskUpid(data);
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

void ProxmoxClient::fetchPBSDatastores(const QString &pbsHost,
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
        emit pbsError(pbsHost, QStringLiteral("Not configured"));
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

    QNetworkRequest req = buildRequest(pbsHost, port, QStringLiteral("/admin/datastore"),
                                       tokenId, tokenSecret, resolvedCertPem, QString(),
                                       m_lowLatency ? ProxmoxConst::Defaults::LowLatencyTimeoutMs
                                                    : ProxmoxConst::Defaults::RequestTimeoutMs);
    req.setRawHeader("Authorization", QByteArray("PBSAPIToken=") + tokenId.toUtf8() + ":" + tokenSecret.toUtf8());

    QNetworkReply *r = m_nam.get(req);
    m_pbsInFlight.insert(r);

    if (ignoreSslErrors) {
        QObject::connect(r, &QNetworkReply::sslErrors, r, [r](const QList<QSslError> &) {
            r->ignoreSslErrors();
        });
    }

    QObject::connect(r, &QNetworkReply::finished, this, [this, r, pbsHost, port, tokenId, tokenSecret, ignoreSslErrors, resolvedCertPem]() {
        m_pbsInFlight.remove(r);

        auto emitErr = [&](const QString &msg) {
            if (m_debugEnabled) qDebug().noquote() << QStringLiteral("[ProxmoxClient] fetchPBSDatastores error host=%1 message=%2").arg(pbsHost, msg);
            emit pbsError(pbsHost, msg);
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
                QNetworkRequest snapshotReq = buildRequest(pbsHost,
                                                           port,
                                                           QStringLiteral("/admin/datastore/%1/snapshots").arg(QString::fromUtf8(QUrl::toPercentEncoding(datastore))),
                                                           tokenId,
                                                           tokenSecret,
                                                           resolvedCertPem,
                                                           QString(),
                                                           m_lowLatency ? ProxmoxConst::Defaults::LowLatencyTimeoutMs : ProxmoxConst::Defaults::RequestTimeoutMs);
                snapshotReq.setRawHeader("Authorization", QByteArray("PBSAPIToken=") + tokenId.toUtf8() + ":" + tokenSecret.toUtf8());

                QNetworkReply *snapshotReply = m_nam.get(snapshotReq);
                m_pbsInFlight.insert(snapshotReply);
                if (ignoreSslErrors) {
                    QObject::connect(snapshotReply, &QNetworkReply::sslErrors, snapshotReply, [snapshotReply](const QList<QSslError> &) {
                        snapshotReply->ignoreSslErrors();
                    });
                }

                QObject::connect(snapshotReply, &QNetworkReply::finished, this, [this, snapshotReply, pbsHost, datastore]() {
                    m_pbsInFlight.remove(snapshotReply);
                    auto emitSnapErr = [&](const QString &msg) {
                        if (m_debugEnabled) qDebug().noquote() << QStringLiteral("[ProxmoxClient] fetchPBSSnapshots error host=%1 datastore=%2 message=%3").arg(pbsHost, datastore, msg);
                        emit pbsError(pbsHost, msg);
                    };
                    auto emitSnapOk = [&](const QVariant &snapData) {
                        if (m_debugEnabled) qDebug().noquote() << QStringLiteral("[ProxmoxClient] fetchPBSSnapshots ok host=%1 datastore=%2").arg(pbsHost, datastore);
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
                            snapshot.pbsHost = pbsHost;
                            snapshots.push_back(snapshot);
                        }
                        emit pbsSnapshotsReceived(pbsHost, datastore, snapshots);
                    };
                    handleFinishedReply(snapshotReply, 0, QStringLiteral("pbs-snapshots"), datastore, QString(), emitSnapErr, emitSnapOk);
                });
            }
        };

        handleFinishedReply(r, 0, QStringLiteral("pbs-datastores"), QString(), QString(), emitErr, emitOk);
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
    m_inFlight.insert(r);

    if (ignoreSslErrors) {
        QObject::connect(r, &QNetworkReply::sslErrors, r, [r](const QList<QSslError> &) {
            r->ignoreSslErrors();
        });
    }

    QObject::connect(r, &QNetworkReply::finished, this, [this, r, sessionKey, host, port, tokenId, tokenSecret, ignoreSslErrors, trustedCertPem, trustedCertPath, upid, seq, actionKind, node, vmid, action]() {
        m_inFlight.remove(r);

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
                                if (taskStillRunning(data)) {
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
                                    return;
                                }

                                const QString exitMessage = extractTaskExitMessage(data);
                                if (!exitMessage.isEmpty()) {
                                    emitTaskError(exitMessage);
                                    return;
                                }

                                emitTaskReply(data);
                            });
    });
}

void ProxmoxClient::requestVncProxy(const QString &sessionKey,
                                     const QString &host,
                                     int port,
                                     const QString &tokenId,
                                     const QString &tokenSecret,
                                     bool ignoreSslErrors,
                                     const QString &node,
                                     const QString &kind,
                                     int vmid)
{
    if (host.isEmpty() || tokenId.isEmpty() || tokenSecret.isEmpty()) {
        emit vncProxyError(sessionKey, node, kind, vmid, QStringLiteral("Not configured"));
        return;
    }

    const QString path = QStringLiteral("/nodes/%1/%2/%3/vncproxy")
                             .arg(node).arg(kind).arg(vmid);

    QNetworkRequest req = buildRequest(host, port, path, tokenId, tokenSecret,
                                       m_trustedCertPem.toUtf8(), m_trustedCertPath);

    QByteArray body;
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/x-www-form-urlencoded");

    QNetworkReply *r = m_nam.post(req, body);
    m_inFlight.insert(r);

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
        [this, r, sessionKey, host, port, node, kind, vmid, authHeader, ignoreSslErrors]() {
            m_inFlight.remove(r);

            const QVariant httpAttr = r->attribute(QNetworkRequest::HttpStatusCodeAttribute);
            const int httpStatus = httpAttr.isValid() ? httpAttr.toInt() : 0;
            const QByteArray body = r->readAll();

            auto fail = [&](const QString &msg) {
                emit vncProxyError(sessionKey, node, kind, vmid,
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

            emit vncProxyReady(sessionKey, host, node, kind, vmid, vncPort, ticket,
                               port, authHeader, ignoreSslErrors);
            r->deleteLater();
        });
}

void ProxmoxClient::requestTtyProxy(const QString &sessionKey,
                                    const QString &host,
                                    int port,
                                    const QString &tokenId,
                                    const QString &tokenSecret,
                                    bool ignoreSslErrors,
                                    const QString &node,
                                    int vmid)
{
    if (host.isEmpty() || tokenId.isEmpty() || tokenSecret.isEmpty()) {
        emit ttyProxyError(sessionKey, node, vmid, QStringLiteral("Not configured"));
        return;
    }

    // Proxmox endpoint is /termproxy (not /tty). Returns:
    //   { port, ticket, user, upid }
    // We need user + ticket for the websocket auth handshake.
    const QString path = QStringLiteral("/nodes/%1/lxc/%2/termproxy")
                             .arg(node).arg(vmid);

    QNetworkRequest req = buildRequest(host, port, path, tokenId, tokenSecret,
                                       m_trustedCertPem.toUtf8(), m_trustedCertPath);

    QByteArray body;
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/x-www-form-urlencoded");

    QNetworkReply *r = m_nam.post(req, body);
    m_inFlight.insert(r);

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
        [this, r, sessionKey, host, node, vmid, authHeader]() {
            m_inFlight.remove(r);

            const QVariant httpAttr = r->attribute(QNetworkRequest::HttpStatusCodeAttribute);
            const int httpStatus = httpAttr.isValid() ? httpAttr.toInt() : 0;
            const QByteArray body = r->readAll();

            auto fail = [&](const QString &msg) {
                emit ttyProxyError(sessionKey, node, vmid,
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

            emit ttyProxyReady(sessionKey, host, node, vmid, ttyPort, ticket, user, authHeader);
            r->deleteLater();
        });
}
