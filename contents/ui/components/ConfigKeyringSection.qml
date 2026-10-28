import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "../../lib/proxmox" as ProxMon

ColumnLayout {
    id: root

    property alias useKeePassXC: keepassCheck.checked
    // Result of the last import, written by the widget after it runs.
    property string importStatus: ""
    // Emitted by the import button. The import itself runs in the widget after Apply.
    signal importRequested()

    // Result of KeyringProbe.probe(); refreshed on open, on toggle and by the button.
    property var info: ({})

    function refresh() {
        info = probe.probe(keepassCheck.checked)
    }

    // The page sets the checkbox from its stored value and on Restore Defaults,
    // as well as the user clicking it, so refresh on every change.
    onUseKeePassXCChanged: refresh()

    readonly property string owner: info.secretServiceOwner || ""

    Layout.fillWidth: true
    spacing: 12

    ProxMon.KeyringProbe {
        id: probe
    }

    // Restarting kills the plasmashell that runs this dialog, so the command
    // detaches first. A systemd-managed plasmashell is restarted through its
    // unit; otherwise it is quit and started again with QTKEYCHAIN_BACKEND
    // removed, so a value inherited from an older ProxMon cannot override the
    // option.
    function restartPlasma() {
        restartExec.connectSource(
            "setsid -f sh -c \"sleep 1; "
            + "if systemctl --user is-active --quiet plasma-plasmashell.service; "
            + "then systemctl --user restart plasma-plasmashell.service; "
            + "else kquitapp6 plasmashell; sleep 2; env -u QTKEYCHAIN_BACKEND kstart plasmashell; fi\" "
            + ">/dev/null 2>&1")
    }

    Plasma5Support.DataSource {
        id: restartExec
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
        }
    }

    Component.onCompleted: refresh()

    QQC2.CheckBox {
        id: keepassCheck
        text: "Store token secrets in KeePassXC instead of KWallet"
        checked: false
        Layout.leftMargin: 45
    }

    QQC2.Label {
        Layout.leftMargin: 45
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: "Needs KeePassXC's Secret Service integration. Takes effect after a Plasma restart. "
            + "Monitoring pauses while the database is locked."
    }

    QQC2.Label {
        Layout.leftMargin: 45
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: {
            const kwallet = root.info.kwalletRunning
                ? "KWallet: running"
                : (root.info.kwalletActivatable ? "KWallet: not running, starts on demand" : "KWallet: not found");
            const secrets = root.owner !== ""
                ? "Secret Service: owned by " + root.owner
                : (root.info.secretServiceActivatable
                    ? "Secret Service: nobody owns it yet, but D-Bus can start a provider"
                    : "Secret Service: no provider");
            return kwallet + "\n" + secrets;
        }
    }

    QQC2.Label {
        Layout.leftMargin: 45
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.negativeTextColor
        visible: text !== ""
        text: {
            if (!keepassCheck.checked) return "";
            if (root.info.libsecretBuilt === false) {
                return "This build has no Secret Service support. Install the libsecret development files and rebuild.";
            }
            if (root.owner === "") {
                return "Nothing owns the Secret Service yet. Start KeePassXC with its Secret Service integration enabled.";
            }
            if (root.owner !== "KeePassXC") {
                return "The Secret Service is owned by " + root.owner + ", not KeePassXC. ProxMon would store "
                    + "its secrets there. The \"Using KeePassXC\" page in the wiki explains how to free it.";
            }
            return "";
        }
    }

    QQC2.Label {
        Layout.leftMargin: 45
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.negativeTextColor
        visible: (root.info.envOverride || "") !== ""
        text: "QTKEYCHAIN_BACKEND=" + (root.info.envOverride || "") + " is set in Plasma's environment and "
            + "wins over this option. Run unset QTKEYCHAIN_BACKEND before kstart plasmashell, or log "
            + "out and back in."
    }

    Kirigami.InlineMessage {
        Layout.leftMargin: 45
        Layout.fillWidth: true
        visible: root.info.restartNeeded === true
        type: Kirigami.MessageType.Warning
        text: "Plasma has to restart before the keyring changes. Press Apply first. "
            + "Restarting reloads every panel and closes this dialog."
        actions: [
            Kirigami.Action {
                text: "Restart Plasma"
                icon.name: "system-reboot"
                onTriggered: root.restartPlasma()
            }
        ]
    }

    RowLayout {
        Layout.leftMargin: 45
        spacing: 10

        QQC2.Button {
            text: "Check again"
            onClicked: root.refresh()
        }

        QQC2.Button {
            text: "Import secrets from KWallet"
            enabled: keepassCheck.checked && root.info.usingSecretService === true
            onClicked: root.importRequested()
        }
    }

    QQC2.Label {
        Layout.leftMargin: 45
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: "The import runs after Apply. It copies KWallet secrets into KeePassXC, leaves "
            + "existing entries alone and deletes nothing from KWallet."
    }

    QQC2.Label {
        Layout.leftMargin: 45
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        visible: root.importStatus !== ""
        text: "Last import: " + root.importStatus
    }
}
