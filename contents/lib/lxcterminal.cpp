#include "lxcterminal.h"

#include <QCloseEvent>
#include <QDebug>
#include <QEvent>
#include <QMainWindow>
#include <QNetworkRequest>
#include <QResizeEvent>
#include <QSslConfiguration>
#include <QSslSocket>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>
#include <QVBoxLayout>
#include <QWebSocket>
#include <QWidget>

#include <qtermwidget.h>
// Note: Session.h / Emulation.h aren't reachable through findChild on this
// distro's qtermwidget6 (Emulation is raw-owned by Session). We invoke
// Session's data-injection slot via QMetaObject by name instead.
#include <QMetaMethod>
#include <QMetaObject>

namespace {

// QMainWindow subclass that emits a Qt signal when closed, so LxcTerminal
// can clean up and notify QML. Using a small lambda-friendly QObject helper
// keeps the relationship loose (no inheritance from LxcTerminal needed).
class TerminalWindow : public QMainWindow {
    Q_OBJECT
public:
    using QMainWindow::QMainWindow;
signals:
    void windowClosed();
protected:
    void closeEvent(QCloseEvent *event) override {
        emit windowClosed();
        QMainWindow::closeEvent(event);
    }
};

} // namespace

LxcTerminal::LxcTerminal(QObject *parent)
    : QObject(parent)
{
}

LxcTerminal::~LxcTerminal()
{
    disconnect();
    destroyWindow();
}

void LxcTerminal::open(const QString &host,
                       int apiPort,
                       const QString &node,
                       int vmid,
                       const QString &vmName,
                       int proxyPort,
                       const QString &user,
                       bool ignoreSslErrors)
{
    m_host       = host;
    m_apiPort    = apiPort;
    m_node       = node;
    m_vmid       = vmid;
    m_vmName     = vmName;
    m_proxyPort  = proxyPort;
    m_user       = user;
    m_ignoreSsl  = ignoreSslErrors;
    // m_authHeader and m_ticket are set beforehand via setAuthHeaderSecure()
    // and setTicketSecure() respectively.

    ensureWindow(vmName, node);
    openSocket();
}

void LxcTerminal::connectWithTicket(int proxyPort,
                                    const QString &user,
                                    bool ignoreSslErrors)
{
    m_proxyPort  = proxyPort;
    m_user       = user;
    m_ignoreSsl  = ignoreSslErrors;
    // m_authHeader and m_ticket are set beforehand via setAuthHeaderSecure()
    // and setTicketSecure() respectively.

    if (!m_window) {
        ensureWindow(m_vmName, m_node);
    }
    openSocket();
}

void LxcTerminal::setAuthHeaderSecure(const QByteArray &header)
{
    m_authHeader = header;
}

void LxcTerminal::setTicketSecure(const QByteArray &ticket)
{
    m_ticket = ticket;
}

void LxcTerminal::raise()
{
    if (m_window) {
        m_window->raise();
        m_window->activateWindow();
    }
}

void LxcTerminal::disconnect()
{
    if (m_ws) {
        m_ws->disconnect(this);
        m_ws->close();
        m_ws->deleteLater();
        m_ws = nullptr;
    }
    m_phase = Phase::Disconnected;
    m_authBuffer.clear();
    if (m_state != QStringLiteral("disconnected")) {
        setState(QStringLiteral("disconnected"));
    }
}

void LxcTerminal::closeWindow()
{
    disconnect();
    destroyWindow();
}

// -------- private helpers --------

void LxcTerminal::ensureWindow(const QString &vmName, const QString &nodeName)
{
    if (m_window) {
        m_window->setWindowTitle(QStringLiteral("Console — %1 (%2)").arg(vmName, nodeName));
        return;
    }

    auto *win = new TerminalWindow();
    win->setAttribute(Qt::WA_DeleteOnClose, false);  // we manage lifetime
    win->setWindowTitle(QStringLiteral("Console — %1 (%2)").arg(vmName, nodeName));
    win->resize(900, 560);

    auto *central = new QWidget(win);
    auto *layout = new QVBoxLayout(central);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(0);

    // 0 = don't auto-start an internal shell; we drive it via sendText.
    auto *term = new QTermWidget(0, central);
    term->setColorScheme(QStringLiteral("DarkPastels"));
    term->setScrollBarPosition(QTermWidget::ScrollBarRight);
    term->setTerminalFont(QFont(QStringLiteral("Monospace"), 11));
    term->startTerminalTeletype();

    layout->addWidget(term);
    win->setCentralWidget(central);
    // Without explicit focus the user has to click into the widget before
    // any keystrokes reach QTermWidget's emulation. Grab focus on show.
    term->setFocusPolicy(Qt::StrongFocus);

    m_window = win;
    m_term = term;

    // Find the Konsole::Session that QTermWidget owns. Emulation (which
    // actually decodes VT escape sequences) is reachable from Session via
    // a raw pointer, but Emulation is not a QObject child of anything we
    // can findChild() so we route data injection through Session's slot.
    m_session = nullptr;
    for (auto *o : term->findChildren<QObject*>(QString(), Qt::FindChildrenRecursively)) {
        if (qstrcmp(o->metaObject()->className(), "Konsole::Session") == 0) {
            m_session = o;
            break;
        }
    }
    if (!m_session) {
        qWarning() << "LxcTerminal: Konsole::Session child not found on QTermWidget;"
                   << "incoming data will fall back to sendText (will echo).";
    } else {
        // Resolve the method signature once. Names that have shipped across
        // qtermwidget/Konsole versions: onReceiveBlock(const char*,int) is
        // the canonical Pty→Session forwarding slot. Some forks rename it.
        const QMetaObject *mo = m_session->metaObject();
        const char *candidates[] = {
            "onReceiveBlock(const char*,int)",
            "onReceiveBlock(QByteArray)",
            "receiveData(const char*,int)",
            nullptr,
        };
        m_sessionRecvSlot.clear();
        for (auto *cand : candidates) {
            if (!cand) break;
            if (mo->indexOfMethod(QMetaObject::normalizedSignature(cand).constData()) >= 0) {
                m_sessionRecvSlot = QByteArray(cand);
                break;
            }
        }
        if (m_sessionRecvSlot.isEmpty()) {
            qWarning() << "LxcTerminal: no known data-injection slot on Konsole::Session;"
                       << "this qtermwidget6 version may need a new candidate name added.";
        }
    }

    QObject::connect(win, &TerminalWindow::windowClosed, this, [this]() {
        disconnect();
        emit closed();
        if (m_window) m_window->deleteLater();
        m_window.clear();
        m_term.clear();
    });

    // QTermWidget6's public sendData is (const char *, int) only.
    QObject::connect(term, &QTermWidget::sendData,
                     this, &LxcTerminal::onTerminalSendDataRaw);

    // No public resize signal; install an event filter to catch QResizeEvent
    // and forward grid dimensions to the remote pty.
    term->installEventFilter(this);

    win->show();
    term->setFocus();
}

void LxcTerminal::destroyWindow()
{
    if (m_window) {
        m_window->close();
        m_window->deleteLater();
        m_window.clear();
        m_term.clear();
    }
}

void LxcTerminal::openSocket()
{
    if (m_host.isEmpty() || m_ticket.isEmpty() || m_user.isEmpty()) {
        emit errorOccurred(QStringLiteral("Missing host/ticket/user for LXC terminal"));
        setState(QStringLiteral("error"));
        return;
    }

    if (m_ws) {
        // Tear down any previous socket cleanly before re-opening.
        m_ws->disconnect(this);
        m_ws->close();
        m_ws->deleteLater();
        m_ws = nullptr;
    }

    setState(QStringLiteral("connecting"));
    m_phase = Phase::Connecting;
    m_authBuffer.clear();

    QUrl url;
    url.setScheme(QStringLiteral("wss"));
    url.setHost(m_host);
    url.setPort(m_apiPort);
    url.setPath(QStringLiteral("/api2/json/nodes/%1/lxc/%2/vncwebsocket")
                    .arg(m_node).arg(m_vmid));

    QUrlQuery q;
    q.addQueryItem(QStringLiteral("port"), QString::number(m_proxyPort));
    q.addQueryItem(QStringLiteral("vncticket"),
                   QString::fromLatin1(m_ticket.toPercentEncoding()));
    url.setQuery(q);

    m_ws = new QWebSocket(QString(), QWebSocketProtocol::VersionLatest, this);

    if (m_ignoreSsl) {
        QSslConfiguration cfg = m_ws->sslConfiguration();
        cfg.setPeerVerifyMode(QSslSocket::VerifyNone);
        m_ws->setSslConfiguration(cfg);
        QObject::connect(m_ws, &QWebSocket::sslErrors, this,
            [this](const QList<QSslError> &) {
                if (m_ws) m_ws->ignoreSslErrors();
            });
    }

    QObject::connect(m_ws, &QWebSocket::connected, this, [this]() {
        // Upgrade complete — burn auth header, send user:ticket\n, burn ticket.
        m_authHeader.fill(0);
        m_authHeader.clear();
        m_phase = Phase::Authenticating;
        if (m_ws) {
            QByteArray ba = m_user.toUtf8() + ':' + m_ticket + '\n';
            m_ws->sendTextMessage(QString::fromUtf8(ba));
            ba.fill(0);
            m_ticket.fill(0);
            m_ticket.clear();
        }
    });

    QObject::connect(m_ws, &QWebSocket::disconnected, this, [this]() {
        if (m_phase == Phase::Errored) return;
        setState(QStringLiteral("disconnected"));
        m_phase = Phase::Disconnected;
    });

    QObject::connect(m_ws, &QWebSocket::errorOccurred, this,
        [this](QAbstractSocket::SocketError) {
            if (!m_ws) return;
            const QString msg = m_ws->errorString();
            m_phase = Phase::Errored;
            setState(QStringLiteral("error"));
            emit errorOccurred(msg.isEmpty() ? QStringLiteral("LXC terminal error") : msg);
        });

    QObject::connect(m_ws, &QWebSocket::textMessageReceived, this,
        &LxcTerminal::handleTextFrame);
    QObject::connect(m_ws, &QWebSocket::binaryMessageReceived, this,
        &LxcTerminal::handleBinaryFrame);

    QNetworkRequest req(url);
    if (!m_authHeader.isEmpty()) {
        // Required — Proxmox returns 401 without it.
        req.setRawHeader("Authorization", m_authHeader);
    }
    m_ws->open(req);
}

// -------- WebSocket frame handlers --------

void LxcTerminal::handleTextFrame(const QString &text)
{
    handleBinaryFrame(text.toUtf8());
}

void LxcTerminal::handleBinaryFrame(const QByteArray &data)
{
    if (m_phase == Phase::Authenticating) {
        handleAuthLine(data);
        return;
    }
    if (m_phase != Phase::Connected) return;
    m_postAuthBytes += data.size();
    deliverToTerminal(data);
}

void LxcTerminal::deliverToTerminal(const QByteArray &data)
{
    if (m_session && !m_sessionRecvSlot.isEmpty()) {
        // Invoke Session::onReceiveBlock or equivalent. Match the resolved
        // signature: (const char*,int) is the most common, (QByteArray) the
        // alternate.
        bool ok = false;
        if (m_sessionRecvSlot.contains("QByteArray")) {
            ok = QMetaObject::invokeMethod(m_session, "onReceiveBlock",
                    Q_ARG(QByteArray, data));
        } else {
            // Both onReceiveBlock and receiveData take (const char*, int) here.
            const QByteArray slotName = m_sessionRecvSlot.left(m_sessionRecvSlot.indexOf('('));
            ok = QMetaObject::invokeMethod(m_session, slotName.constData(),
                    Q_ARG(const char*, data.constData()),
                    Q_ARG(int, data.size()));
        }
        if (!ok) {
            qWarning() << "LxcTerminal: invokeMethod on Session failed for slot"
                       << m_sessionRecvSlot;
        }
        return;
    }
    if (m_term) {
        // Last-resort fallback: produces echo loop, but at least something
        // visible. Should not normally be hit.
        m_term->sendText(QString::fromUtf8(data));
    }
}

void LxcTerminal::handleAuthLine(const QByteArray &line)
{
    m_authBuffer.append(line);

    // Proxmox replies with literal bytes "OK" on success. Some versions
    // include a trailing "\n", others don't — accept both. Anything else
    // (with at least 2 bytes seen) is an auth failure.
    if (m_authBuffer.startsWith("OK")) {
        m_phase = Phase::Connected;
        setState(QStringLiteral("connected"));

        // Consume "OK" plus an optional trailing newline; everything past
        // that is real terminal data.
        int consume = 2;
        if (m_authBuffer.size() > 2 && m_authBuffer.at(2) == '\n') consume = 3;
        if (m_authBuffer.size() > consume) {
            deliverToTerminal(m_authBuffer.mid(consume));
        }
        m_authBuffer.clear();

        // Two-pass resize: immediate (may be 81×25 placeholder) then 120ms
        // after layout settles. 500ms wake CR for silent-getty containers.
        // See docs/ARCHITECTURE.md for rationale.
        QTimer::singleShot(0,   this, [this]() { sendCurrentResize(); });
        QTimer::singleShot(120, this, [this]() { sendCurrentResize(); });

        m_postAuthBytes = 0;
        QTimer::singleShot(500, this, [this]() {
            const int threshold = 24;
            if (m_phase == Phase::Connected && m_ws && m_postAuthBytes < threshold) {
                m_ws->sendTextMessage(QStringLiteral("0:1:\r"));
            }
        });
        return;
    }

    // Need at least 2 bytes before we can be sure this isn't "OK" yet.
    if (m_authBuffer.size() < 2) return;

    m_phase = Phase::Errored;
    setState(QStringLiteral("error"));
    const QString msg = m_authBuffer.isEmpty()
        ? QStringLiteral("LXC terminal authentication failed")
        : QStringLiteral("LXC terminal auth rejected: %1").arg(QString::fromUtf8(m_authBuffer));
    emit errorOccurred(msg);
}

// -------- QTermWidget signal handlers --------

void LxcTerminal::onTerminalSendDataRaw(const char *s, int len)
{
    if (!m_ws || m_phase != Phase::Connected || !s || len <= 0) return;
    const QByteArray frame = QByteArrayLiteral("0:") + QByteArray::number(len)
                             + QByteArrayLiteral(":") + QByteArray(s, len);
    m_ws->sendTextMessage(QString::fromUtf8(frame));
}

void LxcTerminal::sendCurrentResize()
{
    if (!m_ws || m_phase != Phase::Connected || !m_term) return;
    int columns = m_term->screenColumnsCount();
    int lines   = m_term->screenLinesCount();
    // Fall back to 81×25 (not 80×24) so the ioctl produces a real delta and SIGWINCH fires.
    if (columns <= 0) columns = 81;
    if (lines   <= 0) lines   = 25;
    const QString frame = QStringLiteral("1:%1:%2:").arg(columns).arg(lines);
    m_ws->sendTextMessage(frame);
}

bool LxcTerminal::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_term && event->type() == QEvent::Resize) {
        // Defer — grid count isn't updated synchronously with QResizeEvent.
        QTimer::singleShot(0, this, [this]() { sendCurrentResize(); });
    }
    return QObject::eventFilter(watched, event);
}

void LxcTerminal::setState(const QString &state)
{
    if (m_state == state) return;
    m_state = state;
    emit stateChanged();
}

#include "lxcterminal.moc"
