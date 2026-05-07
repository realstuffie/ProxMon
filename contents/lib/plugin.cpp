#include <QQmlExtensionPlugin>
#include <qqml.h>
#include "proxmoxclient.h"
#include "proxmoxcontroller.h"
#include "secretstore.h"
#include "notifier.h"
#include "vncclient.h"
#include "vncframeview.h"
#include "lxcterminal.h"

class ProxmoxClientPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override {
        Q_ASSERT(uri == QLatin1String("org.kde.plasma.proxmox"));
        qmlRegisterType<ProxmoxClient>(uri, 1, 0, "ProxmoxClient");
        qmlRegisterType<ProxmoxController>(uri, 1, 0, "ProxmoxController");
        qmlRegisterType<SecretStore>(uri, 1, 0, "SecretStore");
        qmlRegisterType<Notifier>(uri, 1, 0, "Notifier");
        qmlRegisterType<VncFrameView>(uri, 1, 0, "VncFrameView");
        qmlRegisterType<VncClient>(uri, 1, 0, "VncClient");
        qmlRegisterType<LxcTerminal>(uri, 1, 0, "LxcTerminal");
    }
};
#include "plugin.moc"