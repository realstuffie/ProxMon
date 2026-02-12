#include "proxmoxclient.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QUrl>

ProxmoxClient::ProxmoxClient(QObject *parent)
    : QObject(parent) {}

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

void ProxmoxClient::requestNodes(int seq) {
    request(QStringLiteral("/nodes"), seq, QStringLiteral("nodes"), QString());
}

void ProxmoxClient::requestQemu(const QString &node, int seq) {
    request(QStringLiteral("/nodes/%1/qemu").arg(node), seq, QStringLiteral("qemu"), node);
}

void ProxmoxClient::requestLxc(const QString &node, int seq) {
    request(QStringLiteral("/nodes/%1/lxc").arg(node), seq, QStringLiteral("lxc"), node);
}

void ProxmoxClient::requestNodesFor(const QString &sessionKey,
                                    const QString &host,
                                    int port,
                                    const QString &tokenId,
                                    const QString &tokenSecret,
                                    bool ignoreSslErrors,
                                    int seq) {
    requestFor(sessionKey, host, port, tokenId, tokenSecret, ignoreSslErrors, QStringLiteral("/nodes"), seq, QStringLiteral("nodes"), QString());
}

void ProxmoxClient::requestQemuFor(const QString &sessionKey,
                                   const QString &host,
                                   int port,
                                   const QString &tokenId,
                                   const QString &tokenSecret,
                                   bool ignoreSslErrors,
                                   const QString &node,
                                   int seq) {
    requestFor(sessionKey, host, port, tokenId, tokenSecret, ignoreSslErrors, QStringLiteral("/nodes/%1/qemu").arg(node), seq, QStringLiteral("qemu"), node);
}

void ProxmoxClient::requestLxcFor(const QString &sessionKey,
                                  const QString &host,
                                  int port,
                                  const QString &tokenId,
                                  const QString &tokenSecret,
                                  bool ignoreSslErrors,
                                  const QString &node,
                                  int seq) {
    requestFor(sessionKey, host, port, tokenId, tokenSecret, ignoreSslErrors, QStringLiteral("/nodes/%1/lxc").arg(node), seq, QStringLiteral("lxc"), node);
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

namespace {

QNetworkRequest buildRequest(const QString &host, int port, const QString &path, const QString &tokenId, const QString &tokenSecret) {
    const QUrl url(QStringLiteral("https://%1:%2/api2/json%3").arg(host).arg(port).arg(path));

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("ProxMon"));
    req.setRawHeader("Accept", "application/json");

    // Proxmox expects the token pair as "tokenid=secret" (e.g. root@pam!mytoken=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
    // Header format: Authorization: PVEAPIToken=USER@REALM!TOKENID=UUID
    //
    // Harden against malformed headers / header injection: do not allow CR/LF in header values.
    if (tokenId.contains(QLatin1Char('\r')) || tokenId.contains(QLatin1Char('\n')) ||
        tokenSecret.contains(QLatin1Char('\r')) || tokenSecret.contains(QLatin1Char('\n'))) {
        return req;
    }

    const QByteArray auth = QByteArray("PVEAPIToken=") + tokenId.toUtf8() + "=" + tokenSecret.toUtf8();
    req.setRawHeader("Authorization", auth);

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
            return;
        }

        QString msg = r->errorString();
        const QString jsonMsg = extractJsonMessage(body);
        if (!jsonMsg.isEmpty()) {
            msg += QStringLiteral(" - ") + jsonMsg;
        }
        emitErr(QStringLiteral("%1 (HTTP %2)").arg(msg).arg(httpStatus));
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
        return;
    }
    if (httpStatus >= 400) {
        QString msg = QStringLiteral("HTTP error");
        const QString jsonMsg = extractJsonMessage(body);
        if (!jsonMsg.isEmpty()) {
            msg += QStringLiteral(" - ") + jsonMsg;
        }
        emitErr(QStringLiteral("%1 (HTTP %2)").arg(msg).arg(httpStatus));
        return;
    }

    QJsonParseError pe;
    const QJsonDocument doc = QJsonDocument::fromJson(body, &pe);
    if (pe.error != QJsonParseError::NoError || doc.isNull()) {
        emitErr(QStringLiteral("JSON parse error: %1").arg(pe.errorString()));
        return;
    }

    emitOk(doc.toVariant());
}

} // namespace

void ProxmoxClient::request(const QString &path, int seq, const QString &kind, const QString &node) {
    requestFor(QString(),
               m_host,
               m_port,
               m_tokenId,
               m_tokenSecret,
               m_ignoreSslErrors,
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

    QNetworkRequest req = buildRequest(host, port, path, tokenId, tokenSecret);
    QNetworkReply *r = m_nam.get(req);

    m_inFlight.insert(r);
    QObject::connect(r, &QObject::destroyed, this, [this, r]() {
        m_inFlight.remove(r);
    });

    // Ensure reply is cleaned up even if ProxmoxClient is destroyed before finished() is handled.
    QObject::connect(r, &QNetworkReply::finished, r, &QObject::deleteLater);

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
    if (m_host.isEmpty() || m_tokenId.isEmpty() || m_tokenSecret.isEmpty()) {
        emit actionError(seq, actionKind, node, vmid, action, QStringLiteral("Not configured"));
        return;
    }

    QNetworkRequest req = buildRequest(m_host, m_port, path, m_tokenId, m_tokenSecret);

    // Proxmox accepts an empty body for these actions.
    QNetworkReply *r = m_nam.post(req, QByteArray());

    m_inFlight.insert(r);
    QObject::connect(r, &QObject::destroyed, this, [this, r]() {
        m_inFlight.remove(r);
    });

    // Ensure reply is cleaned up even if ProxmoxClient is destroyed before finished() is handled.
    QObject::connect(r, &QNetworkReply::finished, r, &QObject::deleteLater);

    if (m_ignoreSslErrors) {
        QObject::connect(r, &QNetworkReply::sslErrors, r, [r](const QList<QSslError> &) {
            r->ignoreSslErrors();
        });
    }

    QObject::connect(r, &QNetworkReply::finished, this, [this, r, seq, actionKind, node, vmid, action]() {
        // Remove early so cancelAll() never sees a finished reply.
        m_inFlight.remove(r);

        const QVariant httpAttr = r->attribute(QNetworkRequest::HttpStatusCodeAttribute);
        const int httpStatus = httpAttr.isValid() ? httpAttr.toInt() : 0;
        const QByteArray body = r->readAll();

        auto fail = [&](const QString &msg) {
            emit actionError(seq, actionKind, node, vmid, action, QStringLiteral("%1 (HTTP %2)").arg(msg).arg(httpStatus));
        };

        // Qt network error (DNS, TLS, connection refused, etc)
        if (r->error() != QNetworkReply::NoError) {
            // Silent cancels (expected when refresh restarts or watchdog fires)
            if (r->error() == QNetworkReply::OperationCanceledError) {
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

        // Actions can return {"data":"<UPID>"} (task id) or {"data":null}.
        // Keep old behavior: if JSON parse fails but HTTP is OK, emit actionReply with empty QVariant.
        QJsonParseError pe;
        const QJsonDocument doc = QJsonDocument::fromJson(body, &pe);
        if (pe.error == QJsonParseError::NoError && !doc.isNull()) {
            emit actionReply(seq, actionKind, node, vmid, action, doc.toVariant());
        } else {
            emit actionReply(seq, actionKind, node, vmid, action, QVariant());
        }
    });
}
