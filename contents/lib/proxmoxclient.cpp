#include "proxmoxclient.h"

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
    const auto replies = m_inFlight.values();
    m_inFlight.clear();

    for (QNetworkReply *r : replies) {
        if (r) {
            r->abort();
        }
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
    request(QStringLiteral("/nodes"), seq, QStringLiteral("nodes"), QString());
}

void ProxmoxClient::requestQemu(const QString &node, int seq) {
    request(QStringLiteral("/nodes/%1/qemu").arg(node), seq, QStringLiteral("qemu"), node);
}

void ProxmoxClient::requestLxc(const QString &node, int seq) {
    request(QStringLiteral("/nodes/%1/lxc").arg(node), seq, QStringLiteral("lxc"), node);
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
                                    int seq) {
    requestFor(sessionKey, host, port, tokenId, tokenSecret, ignoreSslErrors, m_trustedCertPem.toUtf8(), m_trustedCertPath, QStringLiteral("/nodes"), seq, QStringLiteral("nodes"), QString());
}

void ProxmoxClient::requestQemuFor(const QString &sessionKey,
                                   const QString &host,
                                   int port,
                                   const QString &tokenId,
                                   const QString &tokenSecret,
                                   bool ignoreSslErrors,
                                   const QString &node,
                                   int seq) {
    requestFor(sessionKey, host, port, tokenId, tokenSecret, ignoreSslErrors, m_trustedCertPem.toUtf8(), m_trustedCertPath, QStringLiteral("/nodes/%1/qemu").arg(node), seq, QStringLiteral("qemu"), node);
}

void ProxmoxClient::requestLxcFor(const QString &sessionKey,
                                  const QString &host,
                                  int port,
                                  const QString &tokenId,
                                  const QString &tokenSecret,
                                  bool ignoreSslErrors,
                                  const QString &node,
                                  int seq) {
    requestFor(sessionKey, host, port, tokenId, tokenSecret, ignoreSslErrors, m_trustedCertPem.toUtf8(), m_trustedCertPath, QStringLiteral("/nodes/%1/lxc").arg(node), seq, QStringLiteral("lxc"), node);
}

void ProxmoxClient::requestAction(const QString &kind, const QString &node, int vmid, const QString &action, int seq) {
    if (kind != QStringLiteral("qemu") && kind != QStringLiteral("lxc")) {
        emit actionError(seq, kind, node, vmid, action, QStringLiteral("Invalid kind"));
        return;
    }
    if (action != QStringLiteral("start") && action != QStringLiteral("shutdown") && action != QStringLiteral("reboot")) {
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
                                     const QString &kind,
                                     const QString &node,
                                     int vmid,
                                     const QString &action,
                                     int seq) {
    if (kind != QStringLiteral("qemu") && kind != QStringLiteral("lxc")) {
        emit actionErrorFor(seq, sessionKey, kind, node, vmid, action, QStringLiteral("Invalid kind"));
        return;
    }
    if (action != QStringLiteral("start") && action != QStringLiteral("shutdown") && action != QStringLiteral("reboot")) {
        emit actionErrorFor(seq, sessionKey, kind, node, vmid, action, QStringLiteral("Invalid action"));
        return;
    }

    postFor(sessionKey,
            host,
            port,
            tokenId,
            tokenSecret,
            ignoreSslErrors,
            m_trustedCertPem.toUtf8(),
            m_trustedCertPath,
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
                             int transferTimeoutMs = 10000) {
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
    if (status.compare(QStringLiteral("stopped"), Qt::CaseInsensitive) == 0) {
        return QStringLiteral("Task stopped without success");
    }
    return {};
}

bool taskStillRunning(const QVariant &data) {
    const QVariantMap root = data.toMap();
    const QVariantMap payload = root.value(QStringLiteral("data")).toMap();
    const QString status = payload.value(QStringLiteral("status")).toString().trimmed();
    return status.compare(QStringLiteral("running"), Qt::CaseInsensitive) == 0;
}

} // namespace

namespace {

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

    QNetworkRequest req = buildRequest(host, port, path, tokenId, tokenSecret, trustedCertPem, trustedCertPath, m_lowLatency ? 5000 : 10000);
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

    QNetworkRequest req = buildRequest(host, port, path, tokenId, tokenSecret, trustedCertPem, trustedCertPath, m_lowLatency ? 5000 : 10000);

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
    qDebug().noquote() << QStringLiteral("[ProxmoxClient] fetchPBSDatastores host=%1 port=%2 tokenIdEmpty=%3 secretEmpty=%4 ignoreSsl=%5")
        .arg(pbsHost, QString::number(port), tokenId.isEmpty() ? QStringLiteral("true") : QStringLiteral("false"), tokenSecret.isEmpty() ? QStringLiteral("true") : QStringLiteral("false"), ignoreSslErrors ? QStringLiteral("true") : QStringLiteral("false"));
    if (pbsHost.isEmpty() || tokenId.isEmpty() || tokenSecret.isEmpty()) {
        emit pbsError(pbsHost, QStringLiteral("Not configured"));
        return;
    }

    QNetworkRequest req = buildRequest(pbsHost, port, QStringLiteral("/admin/datastore"), tokenId, tokenSecret, trustedCertPem, trustedCertPath, m_lowLatency ? 5000 : 10000);
    req.setRawHeader("Authorization", QByteArray("PBSAPIToken=") + tokenId.toUtf8() + ":" + tokenSecret.toUtf8());

    QNetworkReply *r = m_nam.get(req);
    m_inFlight.insert(r);

    if (ignoreSslErrors) {
        QObject::connect(r, &QNetworkReply::sslErrors, r, [r](const QList<QSslError> &) {
            r->ignoreSslErrors();
        });
    }

    QObject::connect(r, &QNetworkReply::finished, this, [this, r, pbsHost, port, tokenId, tokenSecret, ignoreSslErrors, trustedCertPem, trustedCertPath]() {
        m_inFlight.remove(r);

        auto emitErr = [&](const QString &msg) {
            qDebug().noquote() << QStringLiteral("[ProxmoxClient] fetchPBSDatastores error host=%1 message=%2").arg(pbsHost, msg);
            emit pbsError(pbsHost, msg);
        };
        auto emitOk = [&](const QVariant &data) {
            qDebug().noquote() << QStringLiteral("[ProxmoxClient] fetchPBSDatastores ok host=%1").arg(pbsHost);
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
                                                           trustedCertPem,
                                                           trustedCertPath,
                                                           m_lowLatency ? 5000 : 10000);
                snapshotReq.setRawHeader("Authorization", QByteArray("PBSAPIToken=") + tokenId.toUtf8() + ":" + tokenSecret.toUtf8());

                QNetworkReply *snapshotReply = m_nam.get(snapshotReq);
                m_inFlight.insert(snapshotReply);
                if (ignoreSslErrors) {
                    QObject::connect(snapshotReply, &QNetworkReply::sslErrors, snapshotReply, [snapshotReply](const QList<QSslError> &) {
                        snapshotReply->ignoreSslErrors();
                    });
                }

                QObject::connect(snapshotReply, &QNetworkReply::finished, this, [this, snapshotReply, pbsHost, datastore]() {
                    m_inFlight.remove(snapshotReply);
                    auto emitSnapErr = [&](const QString &msg) {
                        qDebug().noquote() << QStringLiteral("[ProxmoxClient] fetchPBSSnapshots error host=%1 datastore=%2 message=%3").arg(pbsHost, datastore, msg);
                        emit pbsError(pbsHost, msg);
                    };
                    auto emitSnapOk = [&](const QVariant &snapData) {
                        qDebug().noquote() << QStringLiteral("[ProxmoxClient] fetchPBSSnapshots ok host=%1 datastore=%2").arg(pbsHost, datastore);
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

void ProxmoxClient::testPBSConnection(const QString &pbsHost,
                                      int port,
                                      const QString &tokenId,
                                      const QString &tokenSecret,
                                      bool ignoreSslErrors,
                                      const QByteArray &trustedCertPem,
                                      const QString &trustedCertPath) {
    qDebug().noquote() << QStringLiteral("[ProxmoxClient] testPBSConnection host=%1 port=%2 tokenIdEmpty=%3 secretEmpty=%4 ignoreSsl=%5")
        .arg(pbsHost, QString::number(port), tokenId.isEmpty() ? QStringLiteral("true") : QStringLiteral("false"), tokenSecret.isEmpty() ? QStringLiteral("true") : QStringLiteral("false"), ignoreSslErrors ? QStringLiteral("true") : QStringLiteral("false"));
    if (pbsHost.isEmpty() || tokenId.isEmpty() || tokenSecret.isEmpty()) {
        emit pbsError(pbsHost, QStringLiteral("Not configured"));
        return;
    }

    QNetworkRequest req = buildRequest(pbsHost, port, QStringLiteral("/version"), tokenId, tokenSecret, trustedCertPem, trustedCertPath, m_lowLatency ? 5000 : 10000);
    req.setRawHeader("Authorization", QByteArray("PBSAPIToken=") + tokenId.toUtf8() + ":" + tokenSecret.toUtf8());

    QNetworkReply *r = m_nam.get(req);
    m_inFlight.insert(r);
    if (ignoreSslErrors) {
        QObject::connect(r, &QNetworkReply::sslErrors, r, [r](const QList<QSslError> &) {
            r->ignoreSslErrors();
        });
    }

    QObject::connect(r, &QNetworkReply::finished, this, [this, r, pbsHost]() {
        m_inFlight.remove(r);
        auto emitErr = [&](const QString &msg) {
            qDebug().noquote() << QStringLiteral("[ProxmoxClient] testPBSConnection error host=%1 message=%2").arg(pbsHost, msg);
            emit pbsError(pbsHost, msg);
        };
        auto emitOk = [&](const QVariant &) {
            qDebug().noquote() << QStringLiteral("[ProxmoxClient] testPBSConnection ok host=%1").arg(pbsHost);
            emit pbsConnectionOk(pbsHost);
        };
        handleFinishedReply(r, 0, QStringLiteral("pbs-version"), QString(), QString(), emitErr, emitOk);
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
    QNetworkRequest req = buildRequest(host, port, path, tokenId, tokenSecret, trustedCertPem, trustedCertPath, m_lowLatency ? 5000 : 10000);
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
