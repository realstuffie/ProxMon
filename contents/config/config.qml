import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: "Connection"
        icon: "network-server"
        source: "../ui/configGeneral.qml"
    }
    
    ConfigCategory {
        name: "Behavior"
        icon: "configure"
        source: "../ui/configBehavior.qml"
    }
}
