#pragma once
#include <QObject>
#include <QString>
#include <QVariantMap>

// Reports which keyrings this session offers, for the settings page. Every
// call goes to the D-Bus daemon only, so a locked or busy keyring cannot stall it.
class KeyringProbe : public QObject {
    Q_OBJECT

public:
    explicit KeyringProbe(QObject *parent = nullptr);

    // wantKeePassXC is the KeePassXC option as it stands in settings.
    // Keys of the result:
    //   usingSecretService         keychain jobs go to the Secret Service now
    //   restartNeeded              wantKeePassXC differs from usingSecretService
    //   envOverride                QTKEYCHAIN_BACKEND from the environment, which
    //                              beats the option, or ""
    //   libsecretBuilt             this build can talk to the Secret Service
    //   backendSelectable          the QtKeychain in use honours QTKEYCHAIN_BACKEND,
    //                              so the KeePassXC option can work
    //   kwalletRunning/Activatable kwalletd6 is on the bus / can be started
    //   secretServiceOwner         program that owns org.freedesktop.secrets, or ""
    //   secretServiceActivatable   D-Bus can start a Secret Service provider
    Q_INVOKABLE QVariantMap probe(bool wantKeePassXC) const;

    // Whether the KeePassXC option can work in this build. No D-Bus involved,
    // so the config dialog can ask it while it builds its list of tabs.
    Q_INVOKABLE bool backendSelectable() const;
};
