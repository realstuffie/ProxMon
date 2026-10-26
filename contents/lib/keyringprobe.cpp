#include "keyringprobe.h"
#include "secretstore.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusReply>
#include <QStringList>

KeyringProbe::KeyringProbe(QObject *parent)
    : QObject(parent) {}

bool KeyringProbe::backendSelectable() const {
    return SecretStore::backendSelectionSupported();
}

QVariantMap KeyringProbe::probe(bool wantKeePassXC) const {
    const bool usingSecretService = SecretStore::usesSecretService();

    bool kwalletRunning = false;
    bool kwalletActivatable = false;
    bool secretServiceActivatable = false;
    if (QDBusConnectionInterface *bus = QDBusConnection::sessionBus().interface()) {
        const QDBusReply<bool> registered = bus->isServiceRegistered(QStringLiteral("org.kde.kwalletd6"));
        kwalletRunning = registered.isValid() && registered.value();
        const QDBusReply<QStringList> activatable = bus->activatableServiceNames();
        if (activatable.isValid()) {
            kwalletActivatable = activatable.value().contains(QStringLiteral("org.kde.kwalletd6"));
            secretServiceActivatable = activatable.value().contains(QStringLiteral("org.freedesktop.secrets"));
        }
    }

#ifdef PROXMON_HAVE_LIBSECRET
    const bool libsecretBuilt = true;
#else
    const bool libsecretBuilt = false;
#endif

    return {
        {QStringLiteral("usingSecretService"), usingSecretService},
        {QStringLiteral("restartNeeded"), wantKeePassXC != usingSecretService},
        {QStringLiteral("envOverride"), SecretStore::envOverride()},
        {QStringLiteral("libsecretBuilt"), libsecretBuilt},
        {QStringLiteral("backendSelectable"), backendSelectable()},
        {QStringLiteral("kwalletRunning"), kwalletRunning},
        {QStringLiteral("kwalletActivatable"), kwalletActivatable},
        {QStringLiteral("secretServiceOwner"), SecretStore::secretServiceProvider()},
        {QStringLiteral("secretServiceActivatable"), secretServiceActivatable},
    };
}
