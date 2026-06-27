#include <QQmlExtensionPlugin>
#include <qqml.h>
#include "proxmoxcontroller.h"
#include "notifier.h"
#include "vncclient.h"
#include "vncframeview.h"
#include "vncwsproxy.h"
#include "lxcterminal.h"

class ProxmoxClientPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override {
        Q_ASSERT(uri == QLatin1String("org.kde.plasma.proxmox"));
        qmlRegisterType<ProxmoxController>(uri, 1, 0, "ProxmoxController");
        qmlRegisterType<Notifier>(uri, 1, 0, "Notifier");
        qmlRegisterType<VncFrameView>(uri, 1, 0, "VncFrameView");
        qmlRegisterType<VncClient>(uri, 1, 0, "VncClient");
        qmlRegisterType<VncWsProxy>(uri, 1, 0, "VncWsProxy");
        qmlRegisterType<LxcTerminal>(uri, 1, 0, "LxcTerminal");
    }
};
#include "plugin.moc"
