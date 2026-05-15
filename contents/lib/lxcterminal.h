#pragma once

#include <QObject>
#include <QByteArray>
#include <QPointer>
#include <QString>

class QWebSocket;
class QMainWindow;
class QTermWidget;

// Protocol layer + window manager for Proxmox LXC console sessions.
// Owns a QMainWindow+QTermWidget (QWidget can't embed in QML).
// Credentials delivered via setAuthHeaderSecure / setTicketSecure.
// See docs/ARCHITECTURE.md for protocol and design rationale.
class LxcTerminal : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString state READ state NOTIFY stateChanged)

public:
    explicit LxcTerminal(QObject *parent = nullptr);
    ~LxcTerminal() override;

    QString state() const { return m_state; }

    // Show the window and start the connection. Safe to call again to
    // reconnect with fresh termproxy params on the same window instance.
    // The ticket must be delivered beforehand via setTicketSecure().
    Q_INVOKABLE void open(const QString &host,
                          int apiPort,
                          const QString &node,
                          int vmid,
                          const QString &vmName,
                          int proxyPort,
                          const QString &user,
                          bool ignoreSslErrors);

    // Re-handshake against an existing window — used when the QML reconnect
    // timer fires and termproxy returns a fresh port pair.
    // The ticket must be delivered beforehand via setTicketSecure().
    Q_INVOKABLE void connectWithTicket(int proxyPort,
                                       const QString &user,
                                       bool ignoreSslErrors);

    // Called by ProxmoxController.deliverConsoleAuth() — sets the auth header
    // directly from C++ without passing through the QML/JS heap.
    Q_INVOKABLE void setAuthHeaderSecure(const QByteArray &header);
    // Called by ProxmoxController.deliverConsoleTicket() — sets the ticket
    // directly from C++ without passing through the QML/JS heap.
    Q_INVOKABLE void setTicketSecure(const QByteArray &ticket);

    Q_INVOKABLE void raise();
    Q_INVOKABLE void disconnect();
    Q_INVOKABLE void closeWindow();

signals:
    void stateChanged();
    void errorOccurred(const QString &message);
    // Emitted when the user closes the QMainWindow. QML uses this to drop
    // the entry from its openConsoles dictionary.
    void closed();
    // Emitted after auto-reconnect threshold is reached so QML can call
    // controller.openConsole(...) to obtain a fresh termproxy ticket.
    void requestReconnect();

private:
    enum class Phase {
        Disconnected,
        Connecting,
        Authenticating,  // sent "user:ticket\n", waiting for "OK"
        Connected,
        Errored,
    };

    void setState(const QString &state);
    void ensureWindow(const QString &vmName, const QString &nodeName);
    void destroyWindow();
    void openSocket();
    void deliverToTerminal(const QByteArray &data);

    // WebSocket frame handlers
    void handleTextFrame(const QString &text);
    void handleBinaryFrame(const QByteArray &data);
    void handleAuthLine(const QByteArray &line);

    // QTermWidget signal handlers
    void onTerminalSendDataRaw(const char *s, int len);
    void sendCurrentResize();
protected:
    // Watches the QTermWidget for QResizeEvent so we can push a pty resize
    // frame to the remote side. QTermWidget6 doesn't expose a resize signal
    // in its public API, so an event filter is the least invasive hook.
    bool eventFilter(QObject *watched, QEvent *event) override;

    // Cached connect-time params (so reconnect/auto-reconnect can replay).
    QString m_host;
    int     m_apiPort = 8006;
    QString m_node;
    int     m_vmid = 0;
    QString m_vmName;
    int        m_proxyPort = 0;
    QByteArray m_ticket;
    QString    m_user;
    QByteArray m_authHeader;
    bool    m_ignoreSsl = false;

    QPointer<QMainWindow> m_window;
    QPointer<QTermWidget> m_term;
    // Pointer into QTermWidget's child tree; used to push received bytes
    // into the display without retriggering QTermWidget::sendData.
    // qtermwidget6 doesn't expose Session.h or Emulation through findChild,
    // so we keep a generic QObject* and invoke the receive slot via the
    // meta-object system.
    QPointer<QObject> m_session;
    QByteArray m_sessionRecvSlot;  // method signature we resolved on first use
    QWebSocket *m_ws = nullptr;
    // Bytes received post-auth before our wake-CR timer expires. Used to
    // decide whether to send a wake CR — boolean isn't enough because some
    // containers emit a 6-byte clear-screen sequence on attach and then go
    // silent, which would falsely suppress the wake. Threshold is heuristic:
    // a real prompt is usually >20 bytes (motd + path + dollar sign).
    int m_postAuthBytes = 0;
    Phase m_phase = Phase::Disconnected;
    QString m_state = QStringLiteral("disconnected");
    QByteArray m_authBuffer;
};
