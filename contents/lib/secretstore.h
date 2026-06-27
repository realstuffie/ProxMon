#pragma once
#include <functional>
#include <QObject>
#include <QString>
#include <QStringList>

QT_BEGIN_NAMESPACE
class QProcess;
QT_END_NAMESPACE

class SecretStore : public QObject {
    Q_OBJECT

public:
    using SecretHandler = std::function<void(const QString &secret)>;
    using ErrorHandler = std::function<void(const QString &message)>;

    explicit SecretStore(QObject *parent = nullptr);

    QString service() const { return m_service; }
    void setService(const QString &v);

    QString key() const { return m_key; }
    void setKey(const QString &v);

    // C++-only credential read. Completion handlers are attached to the
    // individual keychain job so concurrent endpoint reads cannot consume
    // each other's results. Secrets never cross the QML meta-object surface.
    void readSecret(const QString &key,
                    SecretHandler onReady,
                    ErrorHandler onError);

    // Async writes/listing are used by the controller's configuration bridge.
    void writeSecret(const QString &secret);
    void deleteSecret();
    void listKWalletKeys();

signals:
    void serviceChanged();
    void keyChanged();

    void writeFinished(bool ok, const QString &error);
    void deleteFinished(bool ok, const QString &error);
    void keysReady(const QStringList &keys);
    void keyListError(const QString &message);

private:
    void emitFilteredKWalletKeys(const QStringList &raw);

    QString m_service = QStringLiteral("ProxMon");
    QString m_key = QStringLiteral("apiTokenSecret");
    QProcess *m_kwalletListProcess = nullptr;
};
