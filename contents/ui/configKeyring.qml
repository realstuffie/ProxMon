import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

/*
  The keyring tab. Only the three keyring settings are used here. Plasma injects
  every cfg_* key into every settings page, so the rest are inert placeholders;
  ./check-config-pages.sh checks that no page is missing one.

  The section needs the native plugin, so it loads through a Loader. If the
  plugin cannot be resolved, this tab shows a message and the other tabs are
  unaffected. Do not access `Plasmoid` from a KCM page.
*/
KCM.SimpleKCM {
    id: root

    property string cfg_proxmoxHost: ""
    property string cfg_proxmoxHostDefault: ""
    property int cfg_proxmoxPort: 8006
    property int cfg_proxmoxPortDefault: 8006
    property string cfg_apiTokenId: ""
    property string cfg_apiTokenIdDefault: ""
    property string cfg_apiTokenSecret: ""
    property string cfg_apiTokenSecretDefault: ""
    property string cfg_trustedCertPem: ""
    property string cfg_trustedCertPemDefault: ""
    property string cfg_trustedCertPath: ""
    property string cfg_trustedCertPathDefault: ""
    property int cfg_refreshInterval: 30
    property int cfg_refreshIntervalDefault: 30
    property bool cfg_ignoreSsl: false
    property bool cfg_ignoreSslDefault: false
    property bool cfg_pbsEnabled: false
    property bool cfg_pbsEnabledDefault: false
    property bool cfg_storageEnabled: true
    property bool cfg_storageEnabledDefault: true
    property string cfg_storageFilter: ""
    property string cfg_storageFilterDefault: ""
    property string cfg_pbsHost: ""
    property string cfg_pbsHostDefault: ""
    property string cfg_pbsDatastore: ""
    property string cfg_pbsDatastoreDefault: ""
    property string cfg_pbsNamespace: "*"
    property string cfg_pbsNamespaceDefault: "*"
    property int cfg_pbsPort: 8007
    property int cfg_pbsPortDefault: 8007
    property string cfg_pbsTokenId: ""
    property string cfg_pbsTokenIdDefault: ""
    property string cfg_pbsTokenSecretBuffer: ""
    property string cfg_pbsTokenSecretBufferDefault: ""
    property bool cfg_pbsIgnoreSsl: false
    property bool cfg_pbsIgnoreSslDefault: false
    property string cfg_pbsTrustedCertPem: ""
    property string cfg_pbsTrustedCertPemDefault: ""
    property string cfg_pbsTrustedCertPath: ""
    property string cfg_pbsTrustedCertPathDefault: ""
    property int cfg_pbsBackupWarningDays: 7
    property int cfg_pbsBackupWarningDaysDefault: 7
    property int cfg_pbsBackupStaleDays: 14
    property int cfg_pbsBackupStaleDaysDefault: 14
    property int cfg_pbsRefreshInterval: 3600
    property int cfg_pbsRefreshIntervalDefault: 3600
    property string cfg_connectionMode: "single"
    property string cfg_connectionModeDefault: "single"
    property bool cfg_multiHostSharedCert: true
    property bool cfg_multiHostSharedCertDefault: true
    property string cfg_multiHostsJson: "[]"
    property string cfg_multiHostsJsonDefault: "[]"
    property string cfg_multiHostSecretsJson: "{}"
    property string cfg_multiHostSecretsJsonDefault: "{}"
    property string cfg_pbsExcludeTag: ""
    property string cfg_pbsExcludeTagDefault: ""
    property string cfg_pbsExcludeVmids: ""
    property string cfg_pbsExcludeVmidsDefault: ""
    property bool cfg_consoleEnabled: true
    property bool cfg_consoleEnabledDefault: true
    property string cfg_terminalSize: "medium"
    property string cfg_terminalSizeDefault: "medium"
    property bool cfg_powerActionsEnabled: true
    property bool cfg_powerActionsEnabledDefault: true
    property bool cfg_statsEnabled: true
    property bool cfg_statsEnabledDefault: true
    property string cfg_defaultSorting: "status"
    property string cfg_defaultSortingDefault: "status"
    property var cfg_customGuestOrder: []
    property var cfg_customGuestOrderDefault: []
    property string cfg_compactMode: "cpu"
    property string cfg_compactModeDefault: "cpu"
    property bool cfg_enableNotifications: true
    property bool cfg_enableNotificationsDefault: true
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
    property bool cfg_autoRetry: true
    property bool cfg_autoRetryDefault: true
    property int cfg_retryStartSeconds: 5
    property int cfg_retryStartSecondsDefault: 5
    property int cfg_retryMaxSeconds: 300
    property int cfg_retryMaxSecondsDefault: 300
    property bool cfg_useKeePassXC: false
    property bool cfg_useKeePassXCDefault: false
    property int cfg_keyringImportToken: 0
    property int cfg_keyringImportTokenDefault: 0
    property string cfg_keyringImportStatus: ""
    property string cfg_keyringImportStatusDefault: ""
    property bool cfg_lowLatency: false
    property bool cfg_lowLatencyDefault: false
    property bool cfg_debugLogToJournal: false
    property bool cfg_debugLogToJournalDefault: false
    property string cfg_appearanceRunningColor: ""
    property string cfg_appearanceRunningColorDefault: ""
    property string cfg_appearanceStoppedColor: ""
    property string cfg_appearanceStoppedColorDefault: ""
    property string cfg_appearanceNodeColor: ""
    property string cfg_appearanceNodeColorDefault: ""
    property int cfg_appearanceCardTintOpacity: 10
    property int cfg_appearanceCardTintOpacityDefault: 10
    property int cfg_appearanceWindowOpacity: 100
    property int cfg_appearanceWindowOpacityDefault: 100

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 15

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: sectionLoader.status === Loader.Error
            type: Kirigami.MessageType.Error
            text: "The ProxMon plugin could not be loaded, so the keyring options are unavailable. "
                + "Reinstall with install.sh and restart Plasma."
        }

        Loader {
            id: sectionLoader
            Layout.fillWidth: true
            source: "components/ConfigKeyringSection.qml"
        }

        // The page owns the cfg_* values; the section only shows and edits them.
        Binding {
            target: sectionLoader.item
            property: "useKeePassXC"
            value: root.cfg_useKeePassXC
            when: sectionLoader.item !== null
        }

        Binding {
            target: sectionLoader.item
            property: "importStatus"
            value: root.cfg_keyringImportStatus
            when: sectionLoader.item !== null
        }

        Connections {
            target: sectionLoader.item

            function onUseKeePassXCChanged() {
                root.cfg_useKeePassXC = sectionLoader.item.useKeePassXC
            }

            function onImportRequested() {
                root.cfg_keyringImportToken += 1
            }
        }
    }
}
