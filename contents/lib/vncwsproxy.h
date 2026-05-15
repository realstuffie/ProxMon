#pragma once

#include <QObject>
#include <QTcpServer>
#include <QTcpSocket>
#include <QWebSocket>
#include <QUrl>

// Bridges a raw-TCP libvncclient connection to the Proxmox vncwebsocket endpoint.
// Credentials are delivered via setAuthHeaderSecure / setTicketSecure — never Q_PROPERTYs.
// Handles exactly one client connection per instance. See docs/ARCHITECTURE.md.

class VncWsProxy : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString host        READ host        WRITE setHost        NOTIFY hostChanged)
    Q_PROPERTY(int     apiPort     READ apiPort     WRITE setApiPort     NOTIFY apiPortChanged)
    Q_PROPERTY(QString node        READ node        WRITE setNode        NOTIFY nodeChanged)
    Q_PROPERTY(QString kind        READ kind        WRITE setKind        NOTIFY kindChanged)
    Q_PROPERTY(int     vmid        READ vmid        WRITE setVmid        NOTIFY vmidChanged)
    Q_PROPERTY(int     vncPort     READ vncPort     WRITE setVncPort     NOTIFY vncPortChanged)
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
    bool    ignoreSsl()  const { return m_ignoreSsl; }

    void setHost(const QString &v)       { if (m_host == v) return;       m_host = v;       emit hostChanged(); }
    void setApiPort(int v)               { if (m_apiPort == v) return;    m_apiPort = v;    emit apiPortChanged(); }
    void setNode(const QString &v)       { if (m_node == v) return;       m_node = v;       emit nodeChanged(); }
    void setKind(const QString &v)       { if (m_kind == v) return;       m_kind = v;       emit kindChanged(); }
    void setVmid(int v)                  { if (m_vmid == v) return;       m_vmid = v;       emit vmidChanged(); }
    void setVncPort(int v)               { if (m_vncPort == v) return;    m_vncPort = v;    emit vncPortChanged(); }
    void setIgnoreSsl(bool v)            { if (m_ignoreSsl == v) return;  m_ignoreSsl = v;  emit ignoreSslChanged(); }

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void setAuthHeaderSecure(const QByteArray &header);
    Q_INVOKABLE void setTicketSecure(const QByteArray &ticket);

signals:
    void ready(int localPort);
    void errorOccurred(const QString &message);

    void hostChanged();
    void apiPortChanged();
    void nodeChanged();
    void kindChanged();
    void vmidChanged();
    void vncPortChanged();
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
    int        m_vncPort   = 0;
    QByteArray m_ticket;
    QByteArray m_authHeader;
    bool    m_ignoreSsl = false;

    QTcpServer  *m_server    = nullptr;
    QTcpSocket  *m_tcp       = nullptr;
    QWebSocket  *m_ws        = nullptr;
};
