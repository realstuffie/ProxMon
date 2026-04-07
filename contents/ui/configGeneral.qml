import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import "components"
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kcmutils as KCM
/*
  NOTE:
  Config QML (KCM) runs in a separate context than the plasmoid itself and
  should not depend on the native plugin being loadable. Otherwise the entire
  Connection tab may fail to load if the plugin can't be resolved.

  ALSO:
  Do not access `Plasmoid` from a KCM page. The config dialog injects cfg_*
  properties; use those as the single source of truth. Accessing Plasmoid here
  causes "Plasmoid is not defined" and can prevent config pages from loading.
*/

KCM.SimpleKCM {
    id: root

    // Connection properties (aliased to UI controls)
    property alias cfg_proxmoxHost: singleHostSection.hostText
    property alias cfg_proxmoxPort: singleHostSection.portValue
    property alias cfg_apiTokenId: singleHostSection.tokenIdText
    property alias cfg_apiTokenSecret: singleHostSection.tokenSecretText
    property alias cfg_refreshInterval: refreshField.value
    property alias cfg_ignoreSsl: ignoreSslCheck.checked
    property alias cfg_enableNotifications: enableNotificationsCheck.checked

    // Multi-host mode (cfg_* values are provided by the KCM engine)
    property string cfg_connectionMode: "single"
    property string cfg_multiHostsJson: "[]"
    property string cfg_multiHostSecretsJson: "{}"

    // Behavior-tab cfg_* keys are also injected into every KCM page by Plasma.
    // Declare inert placeholders here so configGeneral.qml accepts the initial
    // property set instead of warning about missing properties.
    property string cfg_defaultSorting: "status"
    property string cfg_defaultSortingDefault: "status"
    property string cfg_compactMode: "cpu"
    property string cfg_compactModeDefault: "cpu"
    property bool cfg_lowLatency: false
    property bool cfg_lowLatencyDefault: false
    property string cfg_appearanceRunningColor: ""
    property string cfg_appearanceRunningColorDefault: ""
    property string cfg_appearanceStoppedColor: ""
    property string cfg_appearanceStoppedColorDefault: ""
    property int cfg_appearanceCardTintOpacity: 10
    property int cfg_appearanceCardTintOpacityDefault: 10
    property int cfg_appearanceWindowOpacity: 100
    property int cfg_appearanceWindowOpacityDefault: 100
    property string cfg_notifyMode: "all"
    property string cfg_notifyModeDefault: "all"
    property string cfg_notifyFilter: ""
    property string cfg_notifyFilterDefault: ""
    property bool cfg_notifyOnStart: true
    property bool cfg_notifyOnStartDefault: true
    property bool cfg_notifyOnStop: true
    property bool cfg_notifyOnStopDefault: true
    property bool cfg_notifyOnNodeChange: true
    property bool cfg_notifyOnNodeChangeDefault: true
    property bool cfg_notifyRateLimitEnabled: true
    property bool cfg_notifyRateLimitEnabledDefault: true
    property int cfg_notifyRateLimitSeconds: 120
    property int cfg_notifyRateLimitSecondsDefault: 120
    property bool cfg_redactNotifyIdentities: true
    property bool cfg_redactNotifyIdentitiesDefault: true

    // Auto-retry (handled in main.qml)
    property alias cfg_autoRetry: retrySection.autoRetryChecked
    property alias cfg_retryStartSeconds: retrySection.retryStartValue
    property alias cfg_retryMaxSeconds: retrySection.retryMaxValue

    // Default values for Plasma
    property string cfg_proxmoxHostDefault: ""
    property int cfg_proxmoxPortDefault: 8006
    property string cfg_apiTokenIdDefault: ""
    property string cfg_apiTokenSecretDefault: ""

    property string cfg_connectionModeDefault: "single"
    property string cfg_multiHostsJsonDefault: "[]"
    property string cfg_multiHostSecretsJsonDefault: "{}"
    property int cfg_refreshIntervalDefault: 30
    property bool cfg_ignoreSslDefault: true
    property bool cfg_enableNotificationsDefault: true

    // Auto-retry defaults
    property bool cfg_autoRetryDefault: true
    property int cfg_retryStartSecondsDefault: 5
    property int cfg_retryMaxSecondsDefault: 300

    // DataSource for saving settings to file
    Plasma5Support.DataSource {
        id: saveExec
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            if (data["exit code"] === 0) {
                saveStatus.text = "✓ Saved!"
                saveStatus.color = Kirigami.Theme.positiveTextColor
            } else {
                saveStatus.text = "✗ Failed"
                saveStatus.color = Kirigami.Theme.negativeTextColor
            }
            saveStatusTimer.restart()
            disconnectSource(source)
        }
    }

    // DataSource for loading settings from file
    Plasma5Support.DataSource {
        id: loadExec
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            if (data["exit code"] === 0 && data["stdout"]) {
                try {
                    var s = JSON.parse(data["stdout"])
                    if (s.host) singleHostSection.hostText = s.host
                    if (s.port) singleHostSection.portValue = s.port
                    if (s.tokenId) singleHostSection.tokenIdText = s.tokenId
                    if (s.tokenSecret) singleHostSection.tokenSecretText = s.tokenSecret
                    if (s.refreshInterval) refreshField.value = s.refreshInterval
                    if (s.ignoreSsl !== undefined) ignoreSslCheck.checked = s.ignoreSsl
                    if (s.enableNotifications !== undefined) enableNotificationsCheck.checked = s.enableNotifications
                    loadStatus.text = "✓ Loaded!"
                    loadStatus.color = Kirigami.Theme.positiveTextColor
                } catch (e) {
                    loadStatus.text = "No defaults saved"
                    loadStatus.color = Kirigami.Theme.neutralTextColor
                }
            } else {
                loadStatus.text = "No defaults saved"
                loadStatus.color = Kirigami.Theme.neutralTextColor
            }
            loadStatusTimer.restart()
            disconnectSource(source)
        }
    }

    // Timers to clear status messages
    Timer {
        id: saveStatusTimer
        interval: 3000
        onTriggered: saveStatus.text = ""
    }

    Timer {
        id: loadStatusTimer
        interval: 3000
        onTriggered: loadStatus.text = ""
    }

    // Helper function to escape JSON for shell
    function escapeForShell(str) {
        return str.replace(/\\/g, "\\\\").replace(/'/g, "'\\''")
    }

    function parseMultiHosts() {
        try {
            var arr = JSON.parse(cfg_multiHostsJson || "[]")
            if (!Array.isArray(arr)) return []
            return arr.slice(0, 5)
        } catch (e) {
            return []
        }
    }

    function saveMultiHosts(arr) {
        cfg_multiHostsJson = JSON.stringify((arr || []).slice(0, 5))
    }

    function ensureMultiHostsLen(n) {
        var arr = parseMultiHosts()
        while (arr.length < n) {
            arr.push({ name: "", host: "", port: 8006, tokenId: "", enabled: true })
        }
        for (var i = 0; i < arr.length; i++) {
            if (arr[i].enabled === undefined) arr[i].enabled = true
        }
        return arr.slice(0, n)
    }

    function multiHostSecretKey(entry) {
        var host = (entry && entry.host) ? String(entry.host).trim().toLowerCase() : ""
        var port = (entry && entry.port) ? String(entry.port) : "8006"
        var tokenId = (entry && entry.tokenId) ? String(entry.tokenId).trim() : ""
        var key = (!host || !tokenId) ? "" : ("apiTokenSecret:" + tokenId + "@" + host + ":" + port)
        return key
    }

    /*
      Keyring handling is done by the plasmoid runtime (main.qml), which can load the
      native plugin. Keep the KCM simple and always loadable.
      The secret field here is treated as an input that will be migrated into keyring
      when the widget runs.
    */

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 15

        // Connection Settings Section
        Kirigami.Heading {
            text: "Connection Settings"
            level: 2
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            QQC2.Label {
                text: "Mode:"
                Layout.alignment: Qt.AlignVCenter
            }

            QQC2.ComboBox {
                id: connectionModeCombo
                model: [
                    { text: "Single host", value: "single" },
                    { text: "Multi-host (up to 5)", value: "multiHost" }
                ]
                textRole: "text"
                valueRole: "value"
                Layout.fillWidth: true

                Component.onCompleted: {
                    var v = root.cfg_connectionMode || "single"
                    currentIndex = (v === "multiHost") ? 1 : 0
                }

                onActivated: {
                    cfg_connectionMode = model[currentIndex].value
                }
            }
        }

        ConfigGeneralSingleHostSection {
            id: singleHostSection
            Layout.fillWidth: true
            visible: (root.cfg_connectionMode || "single") === "single"
            onStashSecret: function(secret) {
                cfg_apiTokenSecret = secret
            }
            onForgetSecret: function() {
                cfg_apiTokenSecret = ""
            }
        }

        ConfigGeneralMultiHostSection {
            Layout.fillWidth: true
            visible: (root.cfg_connectionMode || "single") === "multiHost"
            ensureMultiHostsLen: root.ensureMultiHostsLen
            saveMultiHosts: root.saveMultiHosts
            multiHostSecretKey: root.multiHostSecretKey
            cfg_multiHostSecretsJson: root.cfg_multiHostSecretsJson
            onUpdateSecretsJson: function(value) {
                root.cfg_multiHostSecretsJson = value
            }
        }

        GridLayout {
            columns: 2
            columnSpacing: 15
            rowSpacing: 12
            Layout.fillWidth: true

            QQC2.Label {
                text: "Refresh Interval:"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            RowLayout {
                spacing: 8
                QQC2.SpinBox {
                    id: refreshField
                    from: 5
                    to: 3600
                    value: 30
                    editable: true
                }
                QQC2.Label {
                    text: "seconds"
                    opacity: 0.7
                }
            }

            QQC2.Label {
                text: "SSL Verification:"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            QQC2.CheckBox {
                id: ignoreSslCheck
                checked: true
                text: "Ignore SSL certificate errors"
            }

            QQC2.Label {
                text: "Notifications:"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            QQC2.CheckBox {
                id: enableNotificationsCheck
                checked: true
                text: "Enable desktop notifications"
            }
        }

        // Notification info
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Kirigami.Icon {
                source: "dialog-information"
                implicitWidth: 16
                implicitHeight: 16
                opacity: 0.7
            }
            QQC2.Label {
                text: "Notifications are sent when VMs, containers, or nodes change state. Configure filters in the Behavior tab."
                font.pixelSize: 11
                opacity: 0.7
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        // Auth/config refresh hint (Plasma sometimes caches plasmoid runtime state)
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Kirigami.Icon {
                source: "dialog-warning"
                implicitWidth: 16
                implicitHeight: 16
                opacity: 0.7
            }

            QQC2.Label {
                text: "If updating Host/Token settings doesn’t take effect immediately, restart Plasma (plasmashell) or remove/re-add the widget to force a full reload."
                font.pixelSize: 11
                opacity: 0.7
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.3
        }

        ConfigGeneralRetrySection {
            id: retrySection
            autoRetryChecked: true
        }

        QtObject {
            id: saveStatus
            property string text: ""
            property color color: Kirigami.Theme.textColor
        }

        QtObject {
            id: loadStatus
            property string text: ""
            property color color: Kirigami.Theme.textColor
        }

        ConfigGeneralDefaultsSection {
            saveExec: root.saveExec
            loadExec: root.loadExec
            escapeForShell: root.escapeForShell
            singleHostSection: singleHostSection
            refreshField: refreshField
            ignoreSslCheck: ignoreSslCheck
            enableNotificationsCheck: enableNotificationsCheck
            saveStatusText: saveStatus.text
            saveStatusColor: saveStatus.color
            loadStatusText: loadStatus.text
            loadStatusColor: loadStatus.color
            onStashSecret: function(secret) {
                cfg_apiTokenSecret = secret
            }
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.3
            Layout.topMargin: 10
        }

        // API Token Help
        Kirigami.Heading {
            text: "How to Create an API Token"
            level: 3
        }

        QQC2.Label {
            text: "1. Log into Proxmox web interface\n" +
                  "2. Go to Datacenter → Permissions → API Tokens\n" +
                  "3. Click 'Add' and create a token\n" +
                  "4. Token ID must be in the format: user@realm!tokenname\n" +
                  "5. IMPORTANT: If you enable 'Privilege Separation', you must grant permissions to BOTH the user and the token.\n" +
                  "   Proxmox calculates effective permissions as the intersection of user + token ACLs.\n" +
                  "6. Copy the token secret immediately (it is shown only once)"
            font.pixelSize: 11
            opacity: 0.7
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
