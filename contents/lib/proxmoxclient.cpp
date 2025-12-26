#include "proxmoxclient.h"

#include <QJsonDocument>
#include <QNetworkReply>
#include <QUrl>

ProxmoxClient::ProxmoxClient(QObject *parent)
    : QObject(parent) {}

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

void ProxmoxClient::request(const QString &path, int seq, const QString &kind, const QString &node) {
    if (m_host.isEmpty() || m_tokenId.isEmpty() || m_tokenSecret.isEmpty()) {
        emit error(seq, kind, node, QStringLiteral("Not configured"));
        return;
    }

    const QUrl url(QStringLiteral("https://%1:%2/api2/json%3")
                       .arg(m_host)
                       .arg(m_port)
                       .arg(path));

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("ProxMon"));
    req.setRawHeader("Accept", "application/json");

    const QByteArray auth = QByteArray("PVEAPIToken=")
                                + m_tokenId.toUtf8()
                                + "="
                                + m_tokenSecret.toUtf8();
    req.setRawHeader("Authorization", auth);

    QNetworkReply *r = m_nam.get(req);

    if (m_ignoreSslErrors) {
        QObject::connect(r, &QNetworkReply::sslErrors, r, [r](const QList<QSslError> &) {
            r->ignoreSslErrors();
        });
    }

    QObject::connect(r, &QNetworkReply::finished, this, [this, r, seq, kind, node]() {
        const int httpStatus = r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray body = r->readAll();

        if (r->error() != QNetworkReply::NoError) {
            emit error(seq, kind, node, QStringLiteral("%1 (HTTP %2)").arg(r->errorString()).arg(httpStatus));
            r->deleteLater();
            return;
        }

        QJsonParseError pe;
        const QJsonDocument doc = QJsonDocument::fromJson(body, &pe);
        if (pe.error != QJsonParseError::NoError || doc.isNull()) {
            emit error(seq, kind, node, QStringLiteral("JSON parse error: %1").arg(pe.errorString()));
            r->deleteLater();
            return;
        }

        emit reply(seq, kind, node, doc.toVariant());
        r->deleteLater();
    });
}
