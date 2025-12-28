#pragma once
#include <QObject>
#include <QString>

class SecretStore : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString service READ service WRITE setService NOTIFY serviceChanged)
    Q_PROPERTY(QString key READ key WRITE setKey NOTIFY keyChanged)

public:
    explicit SecretStore(QObject *parent = nullptr);

    QString service() const { return m_service; }
    void setService(const QString &v);

    QString key() const { return m_key; }
    void setKey(const QString &v);

    // Async read/write because QtKeychain is async
    Q_INVOKABLE void readSecret();
    Q_INVOKABLE void writeSecret(const QString &secret);
    Q_INVOKABLE void deleteSecret();

signals:
    void serviceChanged();
    void keyChanged();

    void secretReady(const QString &secret);
    void writeFinished(bool ok, const QString &error);
    void deleteFinished(bool ok, const QString &error);
    void error(const QString &message);

private:
    QString m_service = QStringLiteral("ProxMon");
    QString m_key = QStringLiteral("apiTokenSecret");
};
