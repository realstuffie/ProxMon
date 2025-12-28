#include "secretstore.h"

#include <qtkeychain/keychain.h>

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
            // Still surface the message via error() so QML can decide what to do.
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
