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
        // Skip QtKeychain's blocking backend probe: on Plasma 6 the answer
        // is always kwallet6, and probing a busy kwalletd stalls the GUI
        // thread. Respect an existing override.
        if (qEnvironmentVariableIsEmpty("QTKEYCHAIN_BACKEND")) {
            qputenv("QTKEYCHAIN_BACKEND", "kwallet6");
        }
        qmlRegisterType<ProxmoxController>(uri, 1, 0, "ProxmoxController");
        qmlRegisterType<Notifier>(uri, 1, 0, "Notifier");
        qmlRegisterType<VncFrameView>(uri, 1, 0, "VncFrameView");
        qmlRegisterType<VncClient>(uri, 1, 0, "VncClient");
        qmlRegisterType<VncWsProxy>(uri, 1, 0, "VncWsProxy");
        qmlRegisterType<LxcTerminal>(uri, 1, 0, "LxcTerminal");
    }
};
#include "plugin.moc"
