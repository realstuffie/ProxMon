#include "vncwsproxy.h"

#include <QNetworkRequest>
#include <QSslConfiguration>
#include <QUrlQuery>
#include <QDebug>

VncWsProxy::VncWsProxy(QObject *parent)
    : QObject(parent)
    , m_server(new QTcpServer(this))
{
    connect(m_server, &QTcpServer::newConnection, this, &VncWsProxy::onNewConnection);
}

VncWsProxy::~VncWsProxy()
{
    cleanup();
}

// Public API
void VncWsProxy::start()
{
    // Clean up any prior session before re-starting.
    cleanup();

    if (!m_server->listen(QHostAddress::LocalHost, 0)) {
        emit errorOccurred(QStringLiteral("VncWsProxy: failed to bind local TCP server: %1")
                               .arg(m_server->errorString()));
        return;
    }

    emit ready(m_server->serverPort());
}

void VncWsProxy::stop()
{
    cleanup();
}

// Private helpers

QUrl VncWsProxy::buildWsUrl() const
{
    // wss://host:apiPort/api2/json/nodes/{node}/{kind}/{vmid}/vncwebsocket
    //   ?port={vncPort}&vncticket={urlEncoded(ticket)}
    QUrl url;
    url.setScheme(m_ignoreSsl ? QStringLiteral("ws") : QStringLiteral("wss"));
    url.setHost(m_host);
    url.setPort(m_apiPort);
    url.setPath(QStringLiteral("/api2/json/nodes/%1/%2/%3/vncwebsocket")
                    .arg(m_node, m_kind).arg(m_vmid));

    QUrlQuery q;
    q.addQueryItem(QStringLiteral("port"),       QString::number(m_vncPort));
    // Percent-encode the ticket so that base64 '+' characters aren't
    // misread as spaces by Proxmox's form-URL decoder (same fix as LxcTerminal).
    q.addQueryItem(QStringLiteral("vncticket"),
                   QString::fromUtf8(QUrl::toPercentEncoding(m_ticket)));
    url.setQuery(q);
    return url;
}

void VncWsProxy::cleanup()
{
    if (m_tcp) {
        m_tcp->disconnect(this);
        m_tcp->abort();
        m_tcp->deleteLater();
        m_tcp = nullptr;
    }
    if (m_ws) {
        m_ws->disconnect(this);
        m_ws->abort();
        m_ws->deleteLater();
        m_ws = nullptr;
    }
    if (m_server->isListening()) {
        m_server->close();
    }
}

// Slots — incoming TCP connection from libvncclient

void VncWsProxy::onNewConnection()
{
    // Accept exactly one connection; stop listening immediately.
    m_tcp = m_server->nextPendingConnection();
    m_server->close();

    connect(m_tcp, &QTcpSocket::readyRead,    this, &VncWsProxy::onTcpReadyRead);
    connect(m_tcp, &QTcpSocket::disconnected, this, &VncWsProxy::onTcpDisconnected);

    m_ws = new QWebSocket(QString(), QWebSocketProtocol::VersionLatest, this);

    if (m_ignoreSsl) {
        // Mirror LxcTerminal's approach: modify the existing socket config.
        QSslConfiguration cfg = m_ws->sslConfiguration();
        cfg.setPeerVerifyMode(QSslSocket::VerifyNone);
        m_ws->setSslConfiguration(cfg);
        connect(m_ws, &QWebSocket::sslErrors, this, &VncWsProxy::onWsSslErrors);
    }

    connect(m_ws, &QWebSocket::connected,             this, &VncWsProxy::onWsConnected);
    connect(m_ws, &QWebSocket::binaryMessageReceived, this, &VncWsProxy::onWsBinaryMessage);
    connect(m_ws, &QWebSocket::disconnected,          this, &VncWsProxy::onWsDisconnected);
    connect(m_ws, &QWebSocket::errorOccurred,         this, &VncWsProxy::onWsError);

    // Build the upgrade request with the auth header.
    // Do NOT set Sec-WebSocket-Protocol: Proxmox doesn't advertise "binary"
    // in its 101 response, which causes Qt to reject the handshake.
    QNetworkRequest req(buildWsUrl());
    qDebug() << "[VncWsProxy] opening WS" << req.url().toString()
             << "| auth header set:" << !m_authHeader.isEmpty();
    if (!m_authHeader.isEmpty()) {
        req.setRawHeader("Authorization", m_authHeader.toUtf8());
    }
    m_ws->open(req);
}


// Slots — WebSocket events
void VncWsProxy::onWsConnected()
{
    qDebug() << "[VncWsProxy] WebSocket connected";
    // HTTP upgrade complete — auth header and ticket were sent in the
    // handshake request and are no longer needed. Clear and release them.
    m_authHeader.clear();
    m_authHeader.squeeze();
    m_ticket.clear();
    m_ticket.squeeze();
    // Flush any bytes libvncclient already wrote while WS was connecting.
    if (m_tcp && m_tcp->bytesAvailable() > 0) {
        onTcpReadyRead();
    }
}

void VncWsProxy::onWsBinaryMessage(const QByteArray &data)
{
    // WS → TCP: forward raw RFB bytes to libvncclient.
    if (m_tcp && m_tcp->isOpen()) {
        m_tcp->write(data);
    }
}

void VncWsProxy::onWsError(QAbstractSocket::SocketError /*error*/)
{
    const QString msg = m_ws ? m_ws->errorString() : QStringLiteral("unknown WS error");
    qWarning() << "[VncWsProxy] WebSocket error:" << msg;
    emit errorOccurred(QStringLiteral("WebSocket error: %1").arg(msg));
    cleanup();
}

void VncWsProxy::onWsSslErrors(const QList<QSslError> &errors)
{
    // ignoreSsl is set — suppress all SSL errors.
    Q_UNUSED(errors)
    if (m_ws) m_ws->ignoreSslErrors();
}

void VncWsProxy::onWsDisconnected()
{
    qDebug() << "[VncWsProxy] WebSocket disconnected";
    // Close the TCP side so libvncclient sees EOF.
    if (m_tcp) m_tcp->disconnectFromHost();
}

// Slots — TCP (libvncclient) events
void VncWsProxy::onTcpReadyRead()
{
    // TCP → WS: forward raw RFB bytes from libvncclient as binary WS frames.
    if (!m_ws || m_ws->state() != QAbstractSocket::ConnectedState) return;
    const QByteArray data = m_tcp->readAll();
    if (!data.isEmpty()) {
        m_ws->sendBinaryMessage(data);
    }
}

void VncWsProxy::onTcpDisconnected()
{
    qDebug() << "[VncWsProxy] TCP client disconnected";
    if (m_ws) m_ws->close();
}
