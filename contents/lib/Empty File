#include <QQmlExtensionPlugin>
#include <qqml.h>

#include "proxmoxclient.h"

class ProxmoxClientPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    void registerTypes(const char *uri) override {
        // must match qmldir "module ..."
        Q_ASSERT(uri == QLatin1String("org.kde.plasma.proxmox"));

        qmlRegisterType<ProxmoxClient>(uri, 1, 0, "ProxmoxClient");
    }
};

#include "plugin.moc"
