#include <QQmlExtensionPlugin>
#include <qqml.h>

#include "proxmoxclient.h"
#include "secretstore.h"
#include "notifier.h"

class ProxmoxClientPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    void registerTypes(const char *uri) override {
        // must match qmldir "module ..."
        Q_ASSERT(uri == QLatin1String("org.kde.plasma.proxmox"));

        qmlRegisterType<ProxmoxClient>(uri, 1, 0, "ProxmoxClient");
        qmlRegisterType<SecretStore>(uri, 1, 0, "SecretStore");
        qmlRegisterType<Notifier>(uri, 1, 0, "Notifier");
    }
};

#include "plugin.moc"
