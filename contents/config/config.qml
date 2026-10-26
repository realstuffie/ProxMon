import QtQuick
import org.kde.plasma.configuration
import "../lib/proxmox" as ProxMon

ConfigModel {
    id: configModel

    // A QtKeychain older than 0.16.0 cannot be pointed at the Secret Service,
    // so the Keyring tab, which only holds the KeePassXC option, is hidden.
    property QtObject keyringProbe: ProxMon.KeyringProbe {}

    ConfigCategory {
        name: "Connection Settings"
        icon: "preferences-system-network"
        source: "../ui/configGeneral.qml"
    }

    ConfigCategory {
        name: "Keyring"
        icon: "security-high"
        source: "../ui/configKeyring.qml"
        visible: configModel.keyringProbe.backendSelectable()
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
