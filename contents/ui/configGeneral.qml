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
    property string cfg_apiTokenSecret: ""
    property alias cfg_pbsEnabled: singleHostSection.pbsEnabled
    property alias cfg_pbsHost: singleHostSection.pbsHostText
    property alias cfg_pbsPort: singleHostSection.pbsPortValue
    property alias cfg_pbsTokenId: singleHostSection.pbsTokenIdText
    property string cfg_pbsTokenSecretBuffer: ""
    property string cfg_pbsTokenSecretBufferDefault: ""
    property alias cfg_pbsIgnoreSsl: singleHostSection.pbsIgnoreSsl
    property alias cfg_pbsTrustedCertPem: singleHostSection.pbsTrustedCertPem
    property alias cfg_pbsTrustedCertPath: singleHostSection.pbsTrustedCertPath
    property alias cfg_pbsBackupWarningDays: singleHostSection.pbsWarningDays
    property alias cfg_pbsBackupStaleDays: singleHostSection.pbsStaleDays
    property alias cfg_pbsRefreshInterval: singleHostSection.pbsRefreshInterval
    property bool cfg_pbsEnabledDefault: false
    property string cfg_pbsHostDefault: ""
    property int cfg_pbsPortDefault: 8007
    property string cfg_pbsTokenIdDefault: ""
    property bool cfg_pbsIgnoreSslDefault: false
    property string cfg_pbsTrustedCertPemDefault: ""
    property string cfg_pbsTrustedCertPathDefault: ""
    property int cfg_pbsBackupWarningDaysDefault: 7
    property int cfg_pbsBackupStaleDaysDefault: 14
    property int cfg_pbsRefreshIntervalDefault: 3600
    property string cfg_apiTokenSecretDefault: ""
    property string cfg_trustedCertPem: ""
    property string cfg_trustedCertPath: ""
    property alias cfg_refreshInterval: refreshField.value
    property alias cfg_ignoreSsl: ignoreSslCheck.checked
    property bool cfg_enableNotifications: true
    property string cfg_pbsExcludeVmids: ""
    property string cfg_pbsExcludeTag: ""


    // Multi-host mode (cfg_* values are provided by the KCM engine)
    property string cfg_connectionMode: "single"
    property string cfg_multiHostsJson: "[]"
    property string cfg_multiHostSecretsJson: "{}"
    property string cfg_multiHostSecretsJsonDefault: "{}"
    property bool cfg_multiHostSharedCert: true
    property bool cfg_multiHostSharedCertDefault: true

    // Behavior-tab cfg_* keys are also injected into every KCM page by Plasma.
    // Declare inert placeholders here so configGeneral.qml accepts the initial
    // property set instead of warning about missing properties.
    property bool cfg_consoleEnabled: true
    property bool cfg_consoleEnabledDefault: true
    property bool cfg_powerActionsEnabled: true
    property bool cfg_powerActionsEnabledDefault: true
    property string cfg_defaultSorting: "status"
    property string cfg_defaultSortingDefault: "status"
    property string cfg_compactMode: "cpu"
    property string cfg_compactModeDefault: "cpu"
    property bool cfg_lowLatency: false
    property bool cfg_lowLatencyDefault: false
    property bool cfg_debugLogToJournal: false
    property bool cfg_debugLogToJournalDefault: false
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
    property string cfg_appearanceNodeColor: ""
    property string cfg_appearanceNodeColorDefault: ""

    // Auto-retry (handled in main.qml)
    property alias cfg_autoRetry: retrySection.autoRetryChecked
    property alias cfg_retryStartSeconds: retrySection.retryStartValue
    property alias cfg_retryMaxSeconds: retrySection.retryMaxValue

    // Default values for Plasma
    property string cfg_proxmoxHostDefault: ""
    property int cfg_proxmoxPortDefault: 8006
    property string cfg_apiTokenIdDefault: ""
    property string cfg_trustedCertPemDefault: ""
    property string cfg_trustedCertPathDefault: ""

    property string cfg_connectionModeDefault: "single"
    property string cfg_multiHostsJsonDefault: "[]"
    property int cfg_refreshIntervalDefault: 30
    property bool cfg_ignoreSslDefault: true
    property bool cfg_enableNotificationsDefault: true
    property string cfg_pbsExcludeVmidsDefault: ""
    property string cfg_pbsExcludeTagDefault: ""

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
      Single-host secrets still bridge through a transient runtime handoff.
      Multi-host secrets now prefer direct keyring writes and only fall back to the
      legacy JSON stash if no direct writer is available.
    */

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 15

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
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
                    root.cfg_connectionMode = currentValue
                }
            }
        }

        ConfigGeneralSingleHostSection {
            id: singleHostSection
            Layout.fillWidth: true
            visible: (root.cfg_connectionMode || "single") === "single"
            trustedCertPem: root.cfg_trustedCertPem
            trustedCertPath: root.cfg_trustedCertPath
            controller: typeof kcm !== "undefined" && kcm.controller ? kcm.controller : null // qmllint disable unqualified
            onStashSecret: function(secret) {
                root.cfg_apiTokenSecret = secret
            }
            onForgetSecret: function() {
                root.cfg_apiTokenSecret = ""
            }
            onStashPbsSecret: function(secret) {
                root.cfg_pbsTokenSecretBuffer = secret
            }
            onPveCertPemEdited: function(value) { root.cfg_trustedCertPem = value }
            onPveCertPathEdited: function(value) { root.cfg_trustedCertPath = value }
        }

        ConfigGeneralMultiHostSection {
            Layout.fillWidth: true
            visible: (root.cfg_connectionMode || "single") === "multiHost"
            trustedCertPem: root.cfg_trustedCertPem
            trustedCertPath: root.cfg_trustedCertPath
            multiHostSharedCert: root.cfg_multiHostSharedCert
            ensureMultiHostsLen: root.ensureMultiHostsLen
            saveMultiHosts: root.saveMultiHosts
            multiHostSecretKey: root.multiHostSecretKey
            cfg_multiHostSecretsJson: root.cfg_multiHostSecretsJson
            controller: typeof kcm !== "undefined" && kcm.controller ? kcm.controller : null // qmllint disable unqualified
            onUpdateSecretsJson: function(value) {
                root.cfg_multiHostSecretsJson = value
            }
            onPveCertPemEdited: function(value) { root.cfg_trustedCertPem = value }
            onPveCertPathEdited: function(value) { root.cfg_trustedCertPath = value }
            onMultiHostSharedCertToggled: function(value) { root.cfg_multiHostSharedCert = value }
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
            ColumnLayout {
                spacing: 2
                QQC2.CheckBox {
                    id: ignoreSslCheck
                    checked: true
                    text: "Ignore SSL certificate errors"
                }
                QQC2.Label {
                    text: "⚠ Disables certificate validation. Only use on trusted networks with self-signed certs."
                    visible: ignoreSslCheck.checked
                    font.pixelSize: 11
                    color: "#ff3333"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.leftMargin: 24
                }
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
            implicitHeight: 1
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
            enableNotifications: cfg_enableNotifications
            saveStatusText: saveStatus.text
            saveStatusColor: saveStatus.color
            loadStatusText: loadStatus.text
            loadStatusColor: loadStatus.color
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
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
