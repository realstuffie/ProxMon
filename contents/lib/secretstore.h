#pragma once
#include <functional>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariant>

QT_BEGIN_NAMESPACE
class QDBusMessage;
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

private slots:
    void onWalletOpened(const QString &wallet);

private:
    void emitFilteredKWalletKeys(const QStringList &raw);
    void armWalletOpenRetry();
    void asyncKWalletCall(const QString &method, const QVariantList &args,
                          std::function<void(const QDBusMessage &)> handler);
    void startKWalletEntryList(int handle);
    void finishKeyListSuccess(const QStringList &raw, int handle);
    void finishKeyListFailure(const QDBusMessage &reply, const QString &message);
    void startQdbusFallback(int handle);

    QString m_service = QStringLiteral("ProxMon");
    QString m_key = QStringLiteral("apiTokenSecret");
    QProcess *m_kwalletListProcess = nullptr;
    bool m_walletOpenRetryArmed = false;
    bool m_listInFlight = false;
};
