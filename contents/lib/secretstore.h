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
    //
    // On the Secret Service a locked keyring ends in onError at once, without
    // an unlock prompt, so a monitor polling in the background does not pop a
    // dialog on every refresh. promptIfLocked lets an action the user asked for,
    // such as the import, trigger the unlock dialog instead.
    void readSecret(const QString &key,
                    SecretHandler onReady,
                    ErrorHandler onError,
                    bool promptIfLocked = false);

    // Async writes/listing are used by the controller's configuration bridge.
    void writeSecret(const QString &secret);
    void deleteSecret();
    // Lists stored ProxMon keys from whichever keyring is in use.
    void listKeys();
    void listKWalletKeys();

    // true makes QtKeychain use the Secret Service (KeePassXC); false leaves
    // QtKeychain's own tiered detection alone (KWallet first on Plasma).
    // QtKeychain fixes its backend at the first keychain job, so this only
    // takes effect before that; later calls are ignored. A QTKEYCHAIN_BACKEND
    // the user set always wins.
    static void selectBackend(bool useSecretService);
    // True when keychain jobs go to the Secret Service because of
    // selectBackend() or QTKEYCHAIN_BACKEND=libsecret. Detection that falls
    // back to the Secret Service on its own is not reported here.
    static bool usesSecretService();
    // A QTKEYCHAIN_BACKEND from the environment that ProxMon did not set, or
    // empty. It beats the KeePassXC option. Terminals started from a plasmashell
    // that ran an older ProxMon inherit kwallet6 from it.
    static QString envOverride();
    // Name of the program that owns org.freedesktop.secrets on the session
    // bus, such as "KeePassXC" or "GNOME Keyring", or empty if nothing does.
    static QString secretServiceProvider();

    // Copies ProxMon's secrets from KWallet into the keyring in use. Never
    // overwrites a secret the target already has and never deletes from KWallet.
    void importFromKWallet();

    // Emit walletOpened() once, the next time kwalletd opens a wallet. Lets
    // callers retry a failed read when the user unlocks, instead of polling.
    void watchWalletOpened();

signals:
    void serviceChanged();
    void keyChanged();

    void writeFinished(bool ok, const QString &error);
    void deleteFinished(bool ok, const QString &error);
    void keysReady(const QStringList &keys);
    void keyListError(const QString &message);
    void walletOpened();
    // error is empty on a normal finish, even when some keys were skipped or failed.
    void importFinished(int imported, int skipped, int failed, const QString &error);

private slots:
    void onWalletOpened(const QString &wallet);
    void onSecretServiceChanged(const QString &interface, const QVariantMap &changed,
                                const QStringList &invalidated);

private:
    void startRead(const QString &key, SecretHandler onReady, ErrorHandler onError);
    void checkCollectionLocked(std::function<void(bool locked)> done);
    void emitFilteredKeys(const QStringList &raw);
    void listSecretServiceKeys();
    void readNextItemAttributes(QStringList paths, QStringList found);
    void finishImport(const QString &error);
    void importNextKey();
    void armWalletOpenRetry();
    void connectWalletOpened();
    void asyncKWalletCall(const QString &method, const QVariantList &args,
                          std::function<void(const QDBusMessage &)> handler);
    void startKWalletEntryList(int handle);
    void finishKeyListSuccess(const QStringList &raw, int handle);
    void finishKeyListFailure(const QDBusMessage &reply, const QString &message);
    void startQdbusFallback(int handle);

    QString m_service = QStringLiteral("ProxMon");
    QString m_key = QStringLiteral("apiTokenSecret");
    QProcess *m_kwalletListProcess = nullptr;
    bool m_walletSignalConnected = false;
    bool m_secretServiceSignalConnected = false;
    bool m_listRetryPending = false;
    bool m_notifyWalletOpened = false;
    bool m_listInFlight = false;

    bool m_importInFlight = false;
    int m_importHandle = -1;
    QStringList m_importKeys;
    int m_importImported = 0;
    int m_importSkipped = 0;
    int m_importFailed = 0;
};
