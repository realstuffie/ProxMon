#pragma once

#include <QObject>
#include <QTcpServer>
#include <QTcpSocket>
#include <QWebSocket>
#include <QUrl>

// VncWsProxy bridges a raw-TCP libvncclient connection to the Proxmox
// vncwebsocket WebSocket endpoint.
//
// Usage from QML:
//   1. Set host/apiPort/node/kind/vmid/vncPort/ticket/authHeader/ignoreSsl
//   2. Call start() — emits ready(localPort) once the local TCP server is up
//   3. In onReady: vncClient.connectToVnc("127.0.0.1", localPort, ticket)
//   4. libvncclient connects → proxy opens WS to Proxmox → bytes flow both ways
//   5. Call stop() when the VNC session ends (or on error)
//
// The proxy handles exactly one client connection (one VNC session per instance).

class VncWsProxy : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString host        READ host        WRITE setHost        NOTIFY hostChanged)
    Q_PROPERTY(int     apiPort     READ apiPort     WRITE setApiPort     NOTIFY apiPortChanged)
    Q_PROPERTY(QString node        READ node        WRITE setNode        NOTIFY nodeChanged)
    Q_PROPERTY(QString kind        READ kind        WRITE setKind        NOTIFY kindChanged)
    Q_PROPERTY(int     vmid        READ vmid        WRITE setVmid        NOTIFY vmidChanged)
    Q_PROPERTY(int     vncPort     READ vncPort     WRITE setVncPort     NOTIFY vncPortChanged)
    Q_PROPERTY(QString ticket      READ ticket      WRITE setTicket      NOTIFY ticketChanged)
    Q_PROPERTY(QString authHeader  READ authHeader  WRITE setAuthHeader  NOTIFY authHeaderChanged)
    Q_PROPERTY(bool    ignoreSsl   READ ignoreSsl   WRITE setIgnoreSsl   NOTIFY ignoreSslChanged)

public:
    explicit VncWsProxy(QObject *parent = nullptr);
    ~VncWsProxy() override;

    QString host()       const { return m_host; }
    int     apiPort()    const { return m_apiPort; }
    QString node()       const { return m_node; }
    QString kind()       const { return m_kind; }
    int     vmid()       const { return m_vmid; }
    int     vncPort()    const { return m_vncPort; }
    QString ticket()     const { return m_ticket; }
    QString authHeader() const { return QString::fromUtf8(m_authHeader); }
    bool    ignoreSsl()  const { return m_ignoreSsl; }

    void setHost(const QString &v)       { if (m_host == v) return;       m_host = v;       emit hostChanged(); }
    void setApiPort(int v)               { if (m_apiPort == v) return;    m_apiPort = v;    emit apiPortChanged(); }
    void setNode(const QString &v)       { if (m_node == v) return;       m_node = v;       emit nodeChanged(); }
    void setKind(const QString &v)       { if (m_kind == v) return;       m_kind = v;       emit kindChanged(); }
    void setVmid(int v)                  { if (m_vmid == v) return;       m_vmid = v;       emit vmidChanged(); }
    void setVncPort(int v)               { if (m_vncPort == v) return;    m_vncPort = v;    emit vncPortChanged(); }
    void setTicket(const QString &v)     { if (m_ticket == v) return;     m_ticket = v;     emit ticketChanged(); }
    void setAuthHeader(const QString &v) { QByteArray ba = v.toUtf8(); if (m_authHeader == ba) return; m_authHeader = ba; emit authHeaderChanged(); }
    void setIgnoreSsl(bool v)            { if (m_ignoreSsl == v) return;  m_ignoreSsl = v;  emit ignoreSslChanged(); }

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void setAuthHeaderSecure(const QByteArray &header);

signals:
    void ready(int localPort);
    void errorOccurred(const QString &message);

    void hostChanged();
    void apiPortChanged();
    void nodeChanged();
    void kindChanged();
    void vmidChanged();
    void vncPortChanged();
    void ticketChanged();
    void authHeaderChanged();
    void ignoreSslChanged();

private slots:
    void onNewConnection();
    void onWsConnected();
    void onWsBinaryMessage(const QByteArray &data);
    void onWsError(QAbstractSocket::SocketError error);
    void onWsSslErrors(const QList<QSslError> &errors);
    void onTcpReadyRead();
    void onTcpDisconnected();
    void onWsDisconnected();

private:
    void cleanup();
    QUrl buildWsUrl() const;

    QString m_host;
    int     m_apiPort   = 8006;
    QString m_node;
    QString m_kind;
    int     m_vmid      = 0;
    int     m_vncPort   = 0;
    QString m_ticket;
    QByteArray m_authHeader;
    bool    m_ignoreSsl = false;

    QTcpServer  *m_server    = nullptr;
    QTcpSocket  *m_tcp       = nullptr;
    QWebSocket  *m_ws        = nullptr;
};
