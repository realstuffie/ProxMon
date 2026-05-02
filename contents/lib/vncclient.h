#pragma once

#include <QObject>
#include <QImage>
#include <QHash>
#include <QTimer>

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

    Q_INVOKABLE void connectToVnc(const QString &host,
                                   int port,
                                   const QString &vncTicket);
    Q_INVOKABLE void disconnect();
    Q_INVOKABLE void sendKeyEvent(int qtKey, const QString &text, int location, bool pressed);
    Q_INVOKABLE void sendPointerEvent(int x, int y, int buttonMask);
    Q_INVOKABLE void allKeysUp();

signals:
    void stateChanged();
    void frameSizeChanged();
    void frameUpdated(const QImage &image);
    void errorOccurred(const QString &message);

private:
    QHash<quint32, quint32> m_keyDownList;
    void setState(const QString &state);
    void pollLoop();
    rfbClient *m_rfb = nullptr;
    QString m_state = QStringLiteral("disconnected");
    int m_frameWidth = 0;
    int m_frameHeight = 0;
    QTimer *m_pollTimer = nullptr;
};
