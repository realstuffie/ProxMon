#include "secretstore.h"
#include <algorithm>
#include <qtkeychain/keychain.h>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QProcess>
#include <QRegularExpression>

using namespace QKeychain;

namespace {

// kwalletd holds replies while its unlock dialog is up, so all calls are
// asynchronous and never stall the plasmashell main thread. The timeout
// keeps failure feedback fast; a busy timeout arms a walletOpened retry.
constexpr int kKWalletCallTimeoutMs = 5000;

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
                             ErrorHandler onError) {
    auto *job = new ReadPasswordJob(m_service, this);
    job->setKey(key);
    connect(job, &Job::finished, this,
            [job, onReady = std::move(onReady), onError = std::move(onError)]() mutable {
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
    auto *job = new WritePasswordJob(m_service, this);
    job->setKey(m_key);
    job->setTextData(secret);

    connect(job, &Job::finished, this, [this, job]() {
        const bool ok = !job->error();
        emit writeFinished(ok, ok ? QString() : job->errorString());
        job->deleteLater();
    });
    job->start();
}

void SecretStore::deleteSecret() {
    auto *job = new DeletePasswordJob(m_service, this);
    job->setKey(m_key);

    connect(job, &Job::finished, this, [this, job]() {
        const bool ok = !job->error();
        emit deleteFinished(ok, ok ? QString() : job->errorString());
        job->deleteLater();
    });
    job->start();
}

void SecretStore::armWalletOpenRetry() {
    if (m_walletOpenRetryArmed) return;
    m_walletOpenRetryArmed = QDBusConnection::sessionBus().connect(
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
    m_walletOpenRetryArmed = false;
    listKWalletKeys();
}

void SecretStore::emitFilteredKWalletKeys(const QStringList &raw) {
    QStringList filtered;
    std::copy_if(raw.begin(), raw.end(), std::back_inserter(filtered), [&](const QString &k) {
        return k.startsWith(QStringLiteral("apiTokenSecret:")) && !filtered.contains(k);
    });

    if (filtered.isEmpty()) {
        emit keyListError(QStringLiteral("Failed to read KWallet entry list"));
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
        emitFilteredKWalletKeys(raw);
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
                emitFilteredKWalletKeys(parseKWalletListOutput(QString::fromUtf8(proc->readAllStandardOutput())));
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
