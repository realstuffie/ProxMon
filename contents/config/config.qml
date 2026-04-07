import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: "Connection Settings"
        icon: "preferences-system-network"
        source: "../ui/configGeneral.qml"
    }
    
    ConfigCategory {
        name: "Behavior"
        icon: "configure"
        source: "../ui/configBehavior.qml"
    }

    ConfigCategory {
        name: "Appearance"
        icon: "preferences-desktop-color"
        source: "../ui/configAppearance.qml"
    }
}
