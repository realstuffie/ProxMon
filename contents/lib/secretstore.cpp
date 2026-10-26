#include "secretstore.h"
#include <algorithm>
#ifdef PROXMON_SYSTEM_QTKEYCHAIN
#include <qt6keychain/keychain.h>
#else
#include <qtkeychain/keychain.h>
#endif
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusReply>
#include <QDBusVariant>
#include <QFile>
#include <QMap>
#include <QProcess>
#include <QRegularExpression>

using namespace QKeychain;

namespace {

// kwalletd holds replies while its unlock dialog is up, so all calls are
// asynchronous and never stall the plasmashell main thread. The timeout
// keeps failure feedback fast; a busy timeout arms a walletOpened retry.
constexpr int kKWalletCallTimeoutMs = 5000;

// Only these entries are ProxMon API tokens. Both the key listing and the
// KWallet import ignore anything else in the folder.
bool isSecretKey(const QString &key) {
    return key.startsWith(QStringLiteral("apiTokenSecret:"))
        || key.startsWith(QStringLiteral("pbsTokenSecret:"));
}

// QtKeychain fixes its backend at the first keychain job, so the choice is
// frozen once any SecretStore starts one.
bool s_envIsOurs = false;
bool s_jobStarted = false;
bool s_lockedSecretService = false;

bool envSelectsSecretService() {
    return qgetenv("QTKEYCHAIN_BACKEND") == "libsecret";
}

// QtKeychain reads QTKEYCHAIN_BACKEND once, when its first job starts. After
// that the value we set is dead weight and would leak to every program that
// plasmashell starts, such as terminals, where it would override their choice.
// Called when a job finishes, which is after QtKeychain has read it.
void releaseBackendEnv() {
    if (s_envIsOurs && s_jobStarted && qEnvironmentVariableIsSet("QTKEYCHAIN_BACKEND")) {
        qunsetenv("QTKEYCHAIN_BACKEND");
    }
}

void noteJobStarted() {
    if (s_jobStarted) return;
    s_lockedSecretService = envSelectsSecretService();
    s_jobStarted = true;
}

QString friendlyProviderName(const QString &comm) {
    const QString c = comm.toLower();
    if (c.contains(QStringLiteral("keepassxc"))) return QStringLiteral("KeePassXC");
    if (c.contains(QStringLiteral("gnome-keyring"))) return QStringLiteral("GNOME Keyring");
    if (c.contains(QStringLiteral("ksecretd")) || c.contains(QStringLiteral("kwalletd"))) {
        return QStringLiteral("KDE Wallet (ksecretd)");
    }
    return comm;
}

QStringList parseKWalletListOutput(const QString &out) {
    QStringList raw;

    const QRegularExpression quotedRe(QStringLiteral("\"([^\"]+)\""));
    QRegularExpressionMatchIterator it = quotedRe.globalMatch(out);
    while (it.hasNext()) {
        const QString s = it.next().captured(1);
        if (!s.isEmpty()) raw.push_back(s);
    }

    if (raw.isEmpty()) {
        const QStringList tokens = out.split(QRegularExpression(QStringLiteral("[\\r\\n\\t ]+")), Qt::SkipEmptyParts);
        for (const QString &t : tokens) {
            QString cleaned = t;
            cleaned.remove(QRegularExpression(QStringLiteral("^[\\(\\),]+|[\\(\\),]+$")));
            cleaned.remove('"');
            if (!cleaned.isEmpty()) raw.push_back(cleaned);
        }
    }

    return raw;
}

} // namespace

SecretStore::SecretStore(QObject *parent)
    : QObject(parent) {}

void SecretStore::setService(const QString &v) {
    if (m_service == v) return;
    m_service = v;
    emit serviceChanged();
}

void SecretStore::setKey(const QString &v) {
    if (m_key == v) return;
    m_key = v;
    emit keyChanged();
}

void SecretStore::readSecret(const QString &key,
                             SecretHandler onReady,
                             ErrorHandler onError,
                             bool promptIfLocked) {
    if (!promptIfLocked && usesSecretService()) {
        // Ask whether the keyring is locked first. Reading a locked one makes
        // the provider show an unlock dialog, and a refresh reads on every tick.
        checkCollectionLocked([this, key, onReady = std::move(onReady),
                               onError = std::move(onError)](bool locked) mutable {
            if (locked) {
                const QString provider = secretServiceProvider();
                if (onError) {
                    onError(QStringLiteral("%1 is locked. Unlock it to resume.")
                                .arg(provider.isEmpty() ? QStringLiteral("The keyring") : provider));
                }
                return;
            }
            startRead(key, std::move(onReady), std::move(onError));
        });
        return;
    }
    startRead(key, std::move(onReady), std::move(onError));
}

// Reports whether the default Secret Service collection is locked. Any
// failure to find out counts as unlocked, so the normal read decides.
void SecretStore::checkCollectionLocked(std::function<void(bool locked)> done) {
    QDBusMessage alias = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.secrets"),
        QStringLiteral("/org/freedesktop/secrets"),
        QStringLiteral("org.freedesktop.Secret.Service"),
        QStringLiteral("ReadAlias"));
    alias.setArguments({QStringLiteral("default")});

    auto *aliasWatcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(alias, kKWalletCallTimeoutMs), this);
    connect(aliasWatcher, &QDBusPendingCallWatcher::finished, this,
            [this, done = std::move(done)](QDBusPendingCallWatcher *w) mutable {
        const QDBusMessage reply = w->reply();
        w->deleteLater();
        const QString path = reply.type() == QDBusMessage::ReplyMessage
            ? reply.arguments().value(0).value<QDBusObjectPath>().path()
            : QString();
        if (path.isEmpty() || path == QLatin1String("/")) {
            done(false);
            return;
        }

        QDBusMessage get = QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.secrets"), path,
            QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
        get.setArguments({QStringLiteral("org.freedesktop.Secret.Collection"), QStringLiteral("Locked")});
        auto *lockedWatcher = new QDBusPendingCallWatcher(
            QDBusConnection::sessionBus().asyncCall(get, kKWalletCallTimeoutMs), this);
        connect(lockedWatcher, &QDBusPendingCallWatcher::finished, this,
                [done = std::move(done)](QDBusPendingCallWatcher *lw) {
            const QDBusMessage lockedReply = lw->reply();
            lw->deleteLater();
            const bool locked = lockedReply.type() == QDBusMessage::ReplyMessage
                && lockedReply.arguments().value(0).value<QDBusVariant>().variant().toBool();
            done(locked);
        });
    });
}

void SecretStore::startRead(const QString &key, SecretHandler onReady, ErrorHandler onError) {
    noteJobStarted();
    auto *job = new ReadPasswordJob(m_service, this);
    job->setKey(key);
    connect(job, &Job::finished, this,
            [job, onReady = std::move(onReady), onError = std::move(onError)]() mutable {
        releaseBackendEnv();
        if (job->error()) {
            // NotFound is common on first run; emit empty secret and no hard error.
            if (job->error() == QKeychain::EntryNotFound) {
                if (onReady) onReady(QString());
                job->deleteLater();
                return;
            }

            // Hard keyring failures must not be reported as an empty/missing secret,
            // otherwise multi-host resolution can misclassify them as legacy/missing state.
            if (onError) onError(job->errorString());
            job->deleteLater();
            return;
        }
        const QString secret = job->textData();
        if (onReady) onReady(secret);
        job->deleteLater();
    });
    job->start();
}

void SecretStore::writeSecret(const QString &secret) {
    noteJobStarted();
    auto *job = new WritePasswordJob(m_service, this);
    job->setKey(m_key);
    job->setTextData(secret);

    connect(job, &Job::finished, this, [this, job]() {
        releaseBackendEnv();
        const bool ok = !job->error();
        emit writeFinished(ok, ok ? QString() : job->errorString());
        job->deleteLater();
    });
    job->start();
}

void SecretStore::deleteSecret() {
    noteJobStarted();
    auto *job = new DeletePasswordJob(m_service, this);
    job->setKey(m_key);

    connect(job, &Job::finished, this, [this, job]() {
        releaseBackendEnv();
        const bool ok = !job->error();
        emit deleteFinished(ok, ok ? QString() : job->errorString());
        job->deleteLater();
    });
    job->start();
}

void SecretStore::armWalletOpenRetry() {
    m_listRetryPending = true;
    connectWalletOpened();
}

void SecretStore::watchWalletOpened() {
    m_notifyWalletOpened = true;
    connectWalletOpened();
}

void SecretStore::connectWalletOpened() {
    if (usesSecretService()) {
        // Providers announce an unlock in one of two ways. Some change the
        // collection's Locked property, which arrives as PropertiesChanged on
        // any collection path, so the path is left empty. KeePassXC sends no
        // property change; it sends Service.CollectionChanged on both lock and
        // unlock, so that handler asks for the Locked flag again.
        if (m_secretServiceSignalConnected) return;
        QDBusConnection bus = QDBusConnection::sessionBus();
        const bool properties = bus.connect(
            QStringLiteral("org.freedesktop.secrets"),
            QString(),
            QStringLiteral("org.freedesktop.DBus.Properties"),
            QStringLiteral("PropertiesChanged"),
            this, SLOT(onSecretServiceChanged(QString,QVariantMap,QStringList)));
        const bool collection = bus.connect(
            QStringLiteral("org.freedesktop.secrets"),
            QStringLiteral("/org/freedesktop/secrets"),
            QStringLiteral("org.freedesktop.Secret.Service"),
            QStringLiteral("CollectionChanged"),
            this, SLOT(onCollectionChanged(QDBusObjectPath)));
        m_secretServiceSignalConnected = properties || collection;
        return;
    }
    if (m_walletSignalConnected) return;
    m_walletSignalConnected = QDBusConnection::sessionBus().connect(
        QStringLiteral("org.kde.kwalletd6"),
        QStringLiteral("/modules/kwalletd6"),
        QStringLiteral("org.kde.KWallet"),
        QStringLiteral("walletOpened"),
        this, SLOT(onWalletOpened(QString)));
}

void SecretStore::onWalletOpened(const QString &wallet) {
    Q_UNUSED(wallet);
    QDBusConnection::sessionBus().disconnect(
        QStringLiteral("org.kde.kwalletd6"),
        QStringLiteral("/modules/kwalletd6"),
        QStringLiteral("org.kde.KWallet"),
        QStringLiteral("walletOpened"),
        this, SLOT(onWalletOpened(QString)));
    m_walletSignalConnected = false;
    const bool retryList = m_listRetryPending;
    const bool notify = m_notifyWalletOpened;
    m_listRetryPending = false;
    m_notifyWalletOpened = false;
    if (notify) emit walletOpened();
    if (retryList) listKeys();
}

void SecretStore::onSecretServiceChanged(const QString &interface, const QVariantMap &changed,
                                         const QStringList &invalidated) {
    Q_UNUSED(invalidated);
    if (interface != QLatin1String("org.freedesktop.Secret.Collection")) return;
    if (!changed.contains(QStringLiteral("Locked")) || changed.value(QStringLiteral("Locked")).toBool()) return;
    secretServiceUnlocked();
}

void SecretStore::onCollectionChanged(const QDBusObjectPath &) {
    // This fires for a lock as well as an unlock, so look at the flag.
    checkCollectionLocked([this](bool locked) {
        if (!locked) secretServiceUnlocked();
    });
}

void SecretStore::secretServiceUnlocked() {
    if (!m_secretServiceSignalConnected) return;
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.disconnect(
        QStringLiteral("org.freedesktop.secrets"),
        QString(),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this, SLOT(onSecretServiceChanged(QString,QVariantMap,QStringList)));
    bus.disconnect(
        QStringLiteral("org.freedesktop.secrets"),
        QStringLiteral("/org/freedesktop/secrets"),
        QStringLiteral("org.freedesktop.Secret.Service"),
        QStringLiteral("CollectionChanged"),
        this, SLOT(onCollectionChanged(QDBusObjectPath)));
    m_secretServiceSignalConnected = false;
    // From here on it is the same as a wallet opening: retry the failed read.
    onWalletOpened(QString());
}

void SecretStore::emitFilteredKeys(const QStringList &raw) {
    QStringList filtered;
    std::copy_if(raw.begin(), raw.end(), std::back_inserter(filtered), [&](const QString &k) {
        return k.startsWith(QStringLiteral("apiTokenSecret:")) && !filtered.contains(k);
    });

    if (filtered.isEmpty()) {
        emit keyListError(QStringLiteral("Failed to read the keyring entry list"));
    }

    emit keysReady(filtered);
}

void SecretStore::asyncKWalletCall(const QString &method, const QVariantList &args,
                                   std::function<void(const QDBusMessage &)> handler) {
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.kwalletd6"),
        QStringLiteral("/modules/kwalletd6"),
        QStringLiteral("org.kde.KWallet"),
        method);
    msg.setArguments(args);
    const QDBusPendingCall pending =
        QDBusConnection::sessionBus().asyncCall(msg, kKWalletCallTimeoutMs);
    auto *watcher = new QDBusPendingCallWatcher(pending, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [handler = std::move(handler)](QDBusPendingCallWatcher *w) {
        handler(w->reply());
        w->deleteLater();
    });
}

void SecretStore::finishKeyListFailure(const QDBusMessage &reply, const QString &message) {
    // A busy timeout means kwalletd exists but is waiting on its unlock
    // dialog; arm a one-shot retry on walletOpened instead of giving up
    // for the whole session.
    const QDBusError::ErrorType err = QDBusError(reply).type();
    if (err == QDBusError::NoReply || err == QDBusError::Timeout) {
        armWalletOpenRetry();
    }
    m_listInFlight = false;
    emit keyListError(message);
    emit keysReady({});
}

void SecretStore::listKWalletKeys() {
    if (m_listInFlight) return;
    m_listInFlight = true;

    asyncKWalletCall(QStringLiteral("networkWallet"), {},
                     [this](const QDBusMessage &nameReply) {
        const QString wallet = nameReply.type() == QDBusMessage::ReplyMessage
            ? nameReply.arguments().value(0).toString().trimmed()
            : QString();
        if (wallet.isEmpty()) {
            finishKeyListFailure(nameReply, QStringLiteral("Failed to resolve KWallet name"));
            return;
        }

        asyncKWalletCall(QStringLiteral("open"),
            {wallet, static_cast<qlonglong>(0), QStringLiteral("proxmox-monitor")},
            [this](const QDBusMessage &openReply) {
                const int handle = openReply.type() == QDBusMessage::ReplyMessage
                    ? openReply.arguments().value(0).toInt()
                    : -1;
                if (handle < 0) {
                    finishKeyListFailure(openReply, QStringLiteral("Failed to open KWallet"));
                    return;
                }
                startKWalletEntryList(handle);
            });
    });
}

void SecretStore::startKWalletEntryList(int handle) {
    asyncKWalletCall(QStringLiteral("entryList"),
        {handle, QStringLiteral("ProxMon"), QStringLiteral("proxmox-monitor")},
        [this, handle](const QDBusMessage &reply) {
            if (reply.type() == QDBusMessage::ReplyMessage) {
                finishKeyListSuccess(reply.arguments().value(0).toStringList(), handle);
                return;
            }
            asyncKWalletCall(QStringLiteral("entryList"),
                {handle, m_service, QStringLiteral("proxmox-monitor")},
                [this, handle](const QDBusMessage &fallbackReply) {
                    const QStringList raw = fallbackReply.type() == QDBusMessage::ReplyMessage
                        ? fallbackReply.arguments().value(0).toStringList()
                        : QStringList();
                    finishKeyListSuccess(raw, handle);
                });
        });
}

void SecretStore::finishKeyListSuccess(const QStringList &raw, int handle) {
    if (!raw.isEmpty()) {
        m_listInFlight = false;
        emitFilteredKeys(raw);
        return;
    }
    startQdbusFallback(handle);
}

// Fallback: QProcess qdbus
void SecretStore::startQdbusFallback(int handle) {
    if (m_kwalletListProcess) {
        m_kwalletListProcess->deleteLater();
        m_kwalletListProcess = nullptr;
    }

    auto *proc = new QProcess(this);
    m_kwalletListProcess = proc;

    const QStringList args{
        QStringLiteral("org.kde.kwalletd6"),
        QStringLiteral("/modules/kwalletd6"),
        QStringLiteral("org.kde.KWallet.entryList"),
        QString::number(handle),
        QStringLiteral("ProxMon"),
        QStringLiteral("proxmox-monitor")
    };

    connect(proc,QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),this,
            [this, proc](int, QProcess::ExitStatus) {
                if (m_kwalletListProcess != proc) {
                    proc->deleteLater();
                    return;
                }
                m_kwalletListProcess = nullptr;
                m_listInFlight = false;
                emitFilteredKeys(parseKWalletListOutput(QString::fromUtf8(proc->readAllStandardOutput())));
                proc->deleteLater();
            });

    connect(proc,&QProcess::errorOccurred,this,[this, proc](QProcess::ProcessError) {
                if (m_kwalletListProcess != proc) {
                    proc->deleteLater();
                    return;
                }
                m_kwalletListProcess = nullptr;
                m_listInFlight = false;
                emit keyListError(QStringLiteral("Failed to read KWallet entry list"));
                emit keysReady({});
                proc->deleteLater();
            });

    proc->start(QStringLiteral("qdbus"), args);
}

bool SecretStore::backendSelectionSupported() {
#ifdef PROXMON_QTKEYCHAIN_BACKEND_SELECTION
    return true;
#else
    return false;
#endif
}

void SecretStore::selectBackend(bool useSecretService) {
    if (!backendSelectionSupported() || s_jobStarted) return;
    if (useSecretService) {
        // A QTKEYCHAIN_BACKEND the user set always wins; only replace our own.
        if (!qEnvironmentVariableIsEmpty("QTKEYCHAIN_BACKEND") && !s_envIsOurs) return;
        qputenv("QTKEYCHAIN_BACKEND", "libsecret");
        s_envIsOurs = true;
    } else if (s_envIsOurs) {
        qunsetenv("QTKEYCHAIN_BACKEND");
        s_envIsOurs = false;
    }
}

bool SecretStore::usesSecretService() {
    if (!backendSelectionSupported()) return false;
    return s_jobStarted ? s_lockedSecretService : envSelectsSecretService();
}

QString SecretStore::envOverride() {
    if (!backendSelectionSupported()) return QString();
    return s_envIsOurs ? QString() : QString::fromLocal8Bit(qgetenv("QTKEYCHAIN_BACKEND"));
}

QString SecretStore::secretServiceProvider() {
    QDBusConnectionInterface *bus = QDBusConnection::sessionBus().interface();
    if (!bus) return {};
    // Both calls go to the bus daemon, not the provider, so a provider that is
    // busy or locked cannot stall them.
    const QDBusReply<QString> owner = bus->serviceOwner(QStringLiteral("org.freedesktop.secrets"));
    if (!owner.isValid()) return {};
    const QDBusReply<uint> pid = bus->servicePid(owner.value());
    if (!pid.isValid()) return {};
    QFile comm(QStringLiteral("/proc/%1/comm").arg(pid.value()));
    if (!comm.open(QIODevice::ReadOnly)) return {};
    return friendlyProviderName(QString::fromUtf8(comm.readAll()).trimmed());
}

void SecretStore::listKeys() {
    if (usesSecretService()) {
        listSecretServiceKeys();
    } else {
        listKWalletKeys();
    }
}

// QtKeychain stores each Secret Service item with the attributes
// user=<key>, server=<service> and type, so the keys can be found by
// searching for server=<service> and reading each item's user attribute.
void SecretStore::listSecretServiceKeys() {
    if (m_listInFlight) return;
    m_listInFlight = true;
    qDBusRegisterMetaType<QMap<QString, QString>>();

    QDBusArgument attrs;
    attrs.beginMap(QMetaType(QMetaType::QString), QMetaType(QMetaType::QString));
    attrs.beginMapEntry();
    attrs << QStringLiteral("server") << m_service;
    attrs.endMapEntry();
    attrs.endMap();

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.secrets"),
        QStringLiteral("/org/freedesktop/secrets"),
        QStringLiteral("org.freedesktop.Secret.Service"),
        QStringLiteral("SearchItems"));
    msg.setArguments({QVariant::fromValue(attrs)});

    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(msg, kKWalletCallTimeoutMs), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *w) {
        const QDBusMessage reply = w->reply();
        w->deleteLater();
        if (reply.type() != QDBusMessage::ReplyMessage) {
            m_listInFlight = false;
            emit keyListError(QStringLiteral("Failed to search the Secret Service"));
            emit keysReady({});
            return;
        }
        // SearchItems returns (unlocked, locked); attributes are readable on both.
        QStringList paths;
        for (const QVariant &part : reply.arguments()) {
            for (const QDBusObjectPath &p : qdbus_cast<QList<QDBusObjectPath>>(part)) {
                paths.push_back(p.path());
            }
        }
        readNextItemAttributes(paths, {});
    });
}

void SecretStore::readNextItemAttributes(QStringList paths, QStringList found) {
    if (paths.isEmpty()) {
        m_listInFlight = false;
        emitFilteredKeys(found);
        return;
    }
    const QString path = paths.takeFirst();
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.secrets"),
        path,
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("Get"));
    msg.setArguments({QStringLiteral("org.freedesktop.Secret.Item"), QStringLiteral("Attributes")});

    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(msg, kKWalletCallTimeoutMs), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, paths, found](QDBusPendingCallWatcher *w) {
        const QDBusMessage reply = w->reply();
        w->deleteLater();
        QStringList next = found;
        if (reply.type() == QDBusMessage::ReplyMessage) {
            const QVariant inner = reply.arguments().value(0).value<QDBusVariant>().variant();
            const QMap<QString, QString> attrs = qdbus_cast<QMap<QString, QString>>(inner);
            const QString user = attrs.value(QStringLiteral("user"));
            if (!user.isEmpty()) next.push_back(user);
        }
        readNextItemAttributes(paths, next);
    });
}

void SecretStore::importFromKWallet() {
    if (m_importInFlight) return;
    m_importInFlight = true;
    m_importImported = m_importSkipped = m_importFailed = 0;
    m_importKeys.clear();

    asyncKWalletCall(QStringLiteral("networkWallet"), {}, [this](const QDBusMessage &nameReply) {
        const QString wallet = nameReply.type() == QDBusMessage::ReplyMessage
            ? nameReply.arguments().value(0).toString().trimmed()
            : QString();
        if (wallet.isEmpty()) {
            finishImport(QStringLiteral("Could not reach KWallet"));
            return;
        }
        asyncKWalletCall(QStringLiteral("open"),
            {wallet, static_cast<qlonglong>(0), m_service},
            [this](const QDBusMessage &openReply) {
                m_importHandle = openReply.type() == QDBusMessage::ReplyMessage
                    ? openReply.arguments().value(0).toInt()
                    : -1;
                if (m_importHandle < 0) {
                    finishImport(QStringLiteral("Could not open KWallet"));
                    return;
                }
                asyncKWalletCall(QStringLiteral("entryList"),
                    {m_importHandle, m_service, m_service},
                    [this](const QDBusMessage &listReply) {
                        if (listReply.type() != QDBusMessage::ReplyMessage) {
                            finishImport(QStringLiteral("Could not list the KWallet entries"));
                            return;
                        }
                        const QStringList all = listReply.arguments().value(0).toStringList();
                        std::copy_if(all.begin(), all.end(), std::back_inserter(m_importKeys), isSecretKey);
                        importNextKey();
                    });
            });
    });
}

void SecretStore::importNextKey() {
    if (m_importKeys.isEmpty()) {
        finishImport(QString());
        return;
    }
    const QString key = m_importKeys.takeFirst();

    // Look in the target first so an import never overwrites a secret that was
    // already saved there.
    readSecret(key, [this, key](const QString &existing) {
        if (!existing.isEmpty()) {
            ++m_importSkipped;
            importNextKey();
            return;
        }
        asyncKWalletCall(QStringLiteral("readPassword"),
            {m_importHandle, m_service, key, m_service},
            [this, key](const QDBusMessage &reply) {
                QString secret = reply.type() == QDBusMessage::ReplyMessage
                    ? reply.arguments().value(0).toString()
                    : QString();
                if (secret.isEmpty()) {
                    ++m_importFailed;
                    importNextKey();
                    return;
                }
                noteJobStarted();
                auto *job = new WritePasswordJob(m_service, this);
                job->setKey(key);
                job->setTextData(secret);
                secret.clear();
                connect(job, &Job::finished, this, [this, job]() {
                    releaseBackendEnv();
                    if (job->error()) {
                        ++m_importFailed;
                    } else {
                        ++m_importImported;
                    }
                    job->deleteLater();
                    importNextKey();
                });
                job->start();
            });
    }, [this](const QString &error) {
        // The target keyring itself failed, for example it was locked and the
        // user dismissed the unlock prompt. The remaining keys would fail too.
        finishImport(error);
    }, /*promptIfLocked=*/true);
}

void SecretStore::finishImport(const QString &error) {
    m_importInFlight = false;
    m_importHandle = -1;
    m_importKeys.clear();
    emit importFinished(m_importImported, m_importSkipped, m_importFailed, error);
}
