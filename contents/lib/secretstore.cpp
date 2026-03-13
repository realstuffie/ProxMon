#include "secretstore.h"
#include <qtkeychain/keychain.h>
#include <QDBusInterface>
#include <QDBusReply>
#include <QProcess>
#include <QRegularExpression>

using namespace QKeychain;

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

void SecretStore::readSecret() {
    auto *job = new ReadPasswordJob(m_service, this);
    job->setKey(m_key);
    connect(job, &Job::finished, this, [this, job]() {
        if (job->error()) {
            // NotFound is common on first run; emit empty secret and no hard error.
            if (job->error() == QKeychain::EntryNotFound) {
                emit secretReady(QString());
                job->deleteLater();
                return;
            }

            emit error(job->errorString());
            emit secretReady(QString());
            job->deleteLater();
            return;
        }
        emit secretReady(job->textData());
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

void SecretStore::listKWalletKeys() {
    QDBusInterface kwallet(
        "org.kde.kwalletd6",
        "/modules/kwalletd6",
        "org.kde.KWallet",
        QDBusConnection::sessionBus(),
        this
    );

    if (!kwallet.isValid()) {
        emit keyListError(QStringLiteral("KWallet D-Bus interface is not available"));
        emit keysReady({});
        return;
    }

    QDBusReply<QString> walletName = kwallet.call("networkWallet");
    // qDebug() << "[ProxMon] networkWallet valid:" << walletName.isValid() << "value:" << walletName.value();
    if (!walletName.isValid() || walletName.value().trimmed().isEmpty()) {
        emit keyListError(QStringLiteral("Failed to resolve KWallet name"));
        emit keysReady({});
        return;
    }

    const QString wallet = walletName.value().trimmed();
    QDBusReply<int> handle = kwallet.call("open", wallet, static_cast<qlonglong>(0), QStringLiteral("proxmox-monitor"));
    // qDebug() << "[ProxMon] open handle valid:" << handle.isValid() << "value:" << handle.value() << "error:" << handle.error().message();
    if (!handle.isValid() || handle.value() < 0) {
        emit keyListError(QStringLiteral("Failed to open KWallet"));
        emit keysReady({});
        return;
    }

    QStringList raw;
    QDBusReply<QStringList> keys = kwallet.call("entryList", handle.value(), QStringLiteral("ProxMon"), QStringLiteral("proxmox-monitor"));
    // qDebug() << "[ProxMon] entryList(ProxMon) valid:" << keys.isValid() << "value:" << keys.value() << "error:" << keys.error().message();
    if (keys.isValid()) {
        raw = keys.value();
    } else {
        QDBusReply<QStringList> keysFallback = kwallet.call("entryList", handle.value(), m_service, QStringLiteral("proxmox-monitor"));
        // qDebug() << "[ProxMon] entryList(fallback) valid:" << keysFallback.isValid() << "value:" << keysFallback.value() << "error:" << keysFallback.error().message();
        if (keysFallback.isValid()) {
            raw = keysFallback.value();
        }
    }

    // Fallback: QProcess qdbus
    if (raw.isEmpty()) {
        // qDebug() << "[ProxMon] DBus entryList empty, trying QProcess fallback";
        QProcess proc;
        proc.start(QStringLiteral("qdbus"), QStringList{
            QStringLiteral("org.kde.kwalletd6"),
            QStringLiteral("/modules/kwalletd6"),
            QStringLiteral("org.kde.KWallet.entryList"),
            QString::number(handle.value()),
            QStringLiteral("ProxMon"),
            QStringLiteral("proxmox-monitor")
        });

        if (proc.waitForStarted(1500) && proc.waitForFinished(3000)) {
            const QString out = QString::fromUtf8(proc.readAllStandardOutput());
            // qDebug() << "[ProxMon] QProcess output:" << out;

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
        } else {
            // qDebug() << "[ProxMon] QProcess failed to start or finish";
        }
    }

    QStringList filtered;
    for (const QString &k : raw) {
        if (k.startsWith(QStringLiteral("apiTokenSecret:")) && !filtered.contains(k)) filtered.push_back(k);
    }

    // qDebug() << "[ProxMon] filtered keys:" << filtered;

    if (filtered.isEmpty()) {
        emit keyListError(QStringLiteral("Failed to read KWallet entry list"));
    }

    emit keysReady(filtered);
}
