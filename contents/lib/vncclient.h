#pragma once

#include <QObject>
#include <QImage>
#include <QHash>
#include <QMutex>
#include <QQueue>
#include <QThread>
#include <atomic>
#include <functional>

struct _rfbClient;
typedef struct _rfbClient rfbClient;

class VncClient : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(int frameWidth READ frameWidth NOTIFY frameSizeChanged)
    Q_PROPERTY(int frameHeight READ frameHeight NOTIFY frameSizeChanged)

public:
    void setFrameSize(int w, int h);
    explicit VncClient(QObject *parent = nullptr);
    ~VncClient();

    QString state() const { return m_state; }
    int frameWidth() const { return m_frameWidth; }
    int frameHeight() const { return m_frameHeight; }

    Q_INVOKABLE void connectToVnc(const QString &host, int port);
    Q_INVOKABLE void setTicketSecure(const QByteArray &ticket);
    Q_INVOKABLE void disconnect();
    Q_INVOKABLE void sendKeyEvent(int qtKey, const QString &text, int location, bool pressed);
    Q_INVOKABLE void sendPointerEvent(int x, int y, int qtButtons);
    Q_INVOKABLE void sendWheelEvent(int x, int y, int steps, bool up, bool horizontal = false);
    Q_INVOKABLE void allKeysUp();

    /*  Called from the worker-thread updateCallback to mark that new pixel data
        arrived. The poll loop copies + emits once after HandleRFBServerMessage
        so all dirty-rect tiles in one server message are coalesced into a single
        frameUpdated signal instead of N separate copies and paints.
    */
    void markFrameDirty() noexcept { m_frameDirty.store(true, std::memory_order_relaxed); }

signals:
    void stateChanged();
    void frameSizeChanged();
    void frameUpdated(const QImage &image, int x, int y, int w, int h);
    void errorOccurred(const QString &message);

private:
    QHash<quint32, quint32> m_keyDownList;
    void setState(const QString &state);
    void postCmd(std::function<void(rfbClient*)> fn);

    rfbClient        *m_rfb     = nullptr;
    QThread          *m_thread  = nullptr;  // owns rfbInitClient + poll loop
    std::atomic<bool> m_running  { false };
    std::atomic<bool> m_frameDirty { false };

    QMutex m_cmdMutex;
    QQueue<std::function<void(rfbClient*)>> m_cmdQueue;

    QByteArray m_ticket;
    QString m_state       = QStringLiteral("disconnected");
    int     m_frameWidth  = 0;
    int     m_frameHeight = 0;
};
