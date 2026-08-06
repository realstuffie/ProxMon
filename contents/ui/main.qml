pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.core as PlasmaCore
import "components"
import "components/configportability.mjs" as ConfigPortability
// qmllint disable unused-imports
import "../lib/proxmox" as ProxMon
// qmllint enable unused-imports


PlasmoidItem {
    id: root

    function switchSizeFromSize(formFactor, compactMax, fullMin) {
        if (Plasmoid.formFactor === PlasmaCore.Types.Planar) {
            return -1
        }

        if (Plasmoid.formFactor === formFactor) {
            return 1
        }

        if (!Number.isFinite(compactMax)) {
            compactMax = compactRepresentationItem?.implicitWidth ?? Kirigami.Units.iconSizes.enormous - 1
        }

        if (fullMin <= 0) {
            fullMin = Kirigami.Units.iconSizes.enormous - 1
        }

        return Math.max(compactMax, fullMin)
    }

    switchWidth: switchSizeFromSize(PlasmaCore.Types.Horizontal, compactRepresentationItem?.implicitWidth ?? Infinity, fullRepresentationItem?.Layout.minimumWidth ?? -1)
    switchHeight: switchSizeFromSize(PlasmaCore.Types.Vertical, compactRepresentationItem?.implicitHeight ?? Infinity, fullRepresentationItem?.Layout.minimumHeight ?? -1)


    activationTogglesExpanded: true

    toolTipMainText: "Proxmox Monitor"
    toolTipSubText: {
        if (!configured) {
            if (!hasCoreConfig) return "Not configured — right-click to configure"
            if (controller.secretState === "loading" || controller.refreshResolvingSecrets) return "Loading credentials…"
            if (controller.secretState === "missing") return "Missing token secret — open settings"
            if (controller.secretState === "error") return "Keyring error — check logs"
            return "Not configured"
        }
        if (loading) return "Loading…"
        if (errorMessage) return "Error: " + errorMessage
        var nn = displayedNodeList.length
        var txt = nn + " node" + (nn !== 1 ? "s" : "")
        txt += " · " + runningVMs + "/" + displayedVmData.length + " VMs"
        txt += " · " + runningLXC + "/" + displayedLxcData.length + " CTs"
        if (lastUpdate) txt += "\nUpdated: " + lastUpdate
        return txt 
    }

    // Connection mode: "single" | "multiHost"
    property string connectionMode: Plasmoid.configuration.connectionMode || "single"
    property bool multiHostSharedCert: Plasmoid.configuration.multiHostSharedCert !== false

    // Single-host connection properties
    property string proxmoxHost: Plasmoid.configuration.proxmoxHost || ""
    property int proxmoxPort: Plasmoid.configuration.proxmoxPort || 8006
    property string apiTokenId: Plasmoid.configuration.apiTokenId || ""
    property string apiTokenSecret: Plasmoid.configuration.apiTokenSecret || ""
    property string trustedCertPem: Plasmoid.configuration.trustedCertPem || ""
    property string trustedCertPath: Plasmoid.configuration.trustedCertPath || ""

    // Multi-host config (KCM stores these)
    property string multiHostsJson: Plasmoid.configuration.multiHostsJson || "[]"
    property string multiHostSecretsJson: Plasmoid.configuration.multiHostSecretsJson || "{}"

    ProxMon.ProxmoxController {
        id: controller
        connectionMode: root.connectionMode
        host: root.proxmoxHost
        port: root.proxmoxPort
        tokenId: root.apiTokenId
        trustedCertPem: root.trustedCertPem
        trustedCertPath: root.trustedCertPath
        multiHostsJson: root.multiHostsJson
        multiHostSharedCert: root.multiHostSharedCert
        pbsEnabled: root.pbsEnabled
        pbsHost: root.pbsHost
        pbsPort: root.pbsPort
        pbsTokenId: root.pbsTokenId
        pbsIgnoreSsl: root.pbsIgnoreSsl
        pbsTrustedCertPem: root.pbsTrustedCertPem
        pbsTrustedCertPath: root.pbsTrustedCertPath
        pbsBackupWarningDays: root.pbsBackupWarningDays
        pbsBackupStaleDays: root.pbsBackupStaleDays
        pbsRefreshInterval: root.pbsRefreshInterval
        pbsExcludeTag: root.pbsExcludeTag
        pbsExcludeVmids: root.pbsExcludeVmids
        debugEnabled: root.devMode
        ignoreSsl: root.ignoreSsl
        lowLatency: root.lowLatency
        defaultSorting: root.defaultSorting
        // Gate single-host model maintenance to when the popup is open.
        viewActive: root.expanded
        autoRetry: root.autoRetry
        retryStartMs: root.retryStartMs
        retryMaxMs: root.retryMaxMs
        onRestoreSingleConfigRequested: function(host, port, tokenId) {
            Plasmoid.configuration.connectionMode = "single"
            Plasmoid.configuration.proxmoxHost = host
            Plasmoid.configuration.proxmoxPort = port
            Plasmoid.configuration.apiTokenId = tokenId
        }
        onRestoreMultiHostConfigRequested: function(value) {
            Plasmoid.configuration.connectionMode = "multiHost"
            Plasmoid.configuration.multiHostsJson = value
        }
        onSecretStateChanged: {
            if (controller.secretState === "ready" && root.configured && !root.loading && !root.isRefreshing && !configRefreshDebounce.running) {
                root.fetchData()
            }
        }
    }
    Component {
        id: consoleComponent
        VncConsole {}
    }
    /*
    LXC console is a C++-managed QMainWindow with QTermWidget inside;
    no QML wrapper. We instantiate the C++ object directly via this
    Component so we get a per-VM lifetime managed by QML's GC + the
    LxcTerminal::closed() signal.
    */
    Component {
        id: lxcTerminalComponent
        ProxMon.LxcTerminal {}
    }
    property var openConsoles: ({})

    function consoleWindowKey(sessionKey, kind, node, vmid) {
        return String(sessionKey || "single") + "::" + String(kind) + "::" + String(node) + "::" + String(vmid)
    }

    property int refreshInterval: (Plasmoid.configuration.refreshInterval || 30) * 1000
    property bool ignoreSsl: Plasmoid.configuration.ignoreSsl === true
    property bool lowLatency: Plasmoid.configuration.lowLatency === true
    property bool pbsEnabled: Plasmoid.configuration.pbsEnabled === true
    property string pbsHost: Plasmoid.configuration.pbsHost || ""
    property int pbsPort: Math.max(1, Plasmoid.configuration.pbsPort || 8007)
    property string pbsTokenId: Plasmoid.configuration.pbsTokenId || ""
    property string pbsTrustedCertPem: Plasmoid.configuration.pbsTrustedCertPem || ""
    property string pbsTrustedCertPath: Plasmoid.configuration.pbsTrustedCertPath || ""
    // Temporary KConfig handoff from the settings page. Keep this bound so a
    // newly saved secret is migrated immediately rather than waiting for the
    // plasmoid to restart. The change handler below clears KConfig first.
    property string pbsTokenSecretBuffer: Plasmoid.configuration.pbsTokenSecretBuffer || ""
    property bool pbsIgnoreSsl: Plasmoid.configuration.pbsIgnoreSsl === true
    property int pbsBackupWarningDays: Math.max(1, Plasmoid.configuration.pbsBackupWarningDays || 7)
    property int pbsBackupStaleDays: Math.max(1, Plasmoid.configuration.pbsBackupStaleDays || 14)
    property int pbsRefreshInterval: Math.max(1800, Plasmoid.configuration.pbsRefreshInterval || 3600)
    property string pbsExcludeTag: Plasmoid.configuration.pbsExcludeTag || ""
    property string pbsExcludeVmids: Plasmoid.configuration.pbsExcludeVmids || ""
    property string defaultSorting: Plasmoid.configuration.defaultSorting || "status"

    // Auto-retry/backoff
    property bool autoRetry: Plasmoid.configuration.autoRetry !== false
    property int retryStartMs: Math.max(1000, (Plasmoid.configuration.retryStartSeconds || 5) * 1000)
    property int retryMaxMs: Math.max(retryStartMs, (Plasmoid.configuration.retryMaxSeconds || 300) * 1000)
    property int retryAttempt: controller ? controller.retryAttempt : 0
    property int retryNextDelayMs: controller ? controller.retryNextDelayMs : 0
    // Propagated explicitly via Connections.onRetryStatusTextChanged below.
    // Do NOT re-add a controller binding here: imperative clearing in
    // triggerRefreshFromConfigChange would silently kill it.
    property string retryStatusText: ""
    property string pbsError: ""

    // Notification properties
    property bool enableNotifications: Plasmoid.configuration.enableNotifications !== false
    property string notifyMode: Plasmoid.configuration.notifyMode || "all"
    property string notifyFilter: Plasmoid.configuration.notifyFilter || ""
    property bool notifyOnStop: Plasmoid.configuration.notifyOnStop !== false
    property bool notifyOnStart: Plasmoid.configuration.notifyOnStart !== false
    property bool notifyOnNodeChange: Plasmoid.configuration.notifyOnNodeChange !== false
    property bool redactNotifyIdentities: Plasmoid.configuration.redactNotifyIdentities !== false
    property bool notifyRateLimitEnabled: Plasmoid.configuration.notifyRateLimitEnabled !== false
    property int notifyRateLimitSeconds: Math.max(0, Plasmoid.configuration.notifyRateLimitSeconds || 120)
    // key => epoch ms
    property var notifyLastSent: ({})

    // Compact label mode: "cpu" (default), "running", "error", "lastUpdate"
    property string compactMode: Plasmoid.configuration.compactMode || "cpu"

    property bool controllerPendingResolvedRefresh: false

    // Data and refresh state are owned by the controller.
    property var displayedProxmoxData: controller.displayedProxmoxData
    property var displayedVmData: controller.displayedVmData
    property var displayedLxcData: controller.displayedLxcData
    property var displayedEndpoints: controller.displayedEndpoints
    property var displayedEndpointsModel: {
        var arr = []
        var src = controller && controller.displayedEndpoints ? controller.displayedEndpoints : []
        for (var i = 0; i < src.length; i++) arr.push(src[i])
        return arr
    }

    onDisplayedEndpointsModelChanged: {
        logDebug("[ProxMon UI] mode=" + connectionMode
                 + " configured=" + configured
                 + " loading=" + loading
                 + " error=" + errorMessage
                 + " endpointsModel=" + (displayedEndpointsModel ? displayedEndpointsModel.length : -1))
    }
    property var displayedNodeList: controller.displayedNodeList

    // Stats (RRD history + IP address) cache, keyed by vmid.
    // Rebuilt via Object.assign on every update rather than mutated in place,
    // since QML only re-evaluates bindings when a property actually changes
    // reference - an in-place mutation of the same object is invisible to it.
    property var statsDataByVmid: ({})
    property var statsLoadingByVmid: ({})

    function getStatsData(vmid) {
        return root.statsDataByVmid[vmid] !== undefined ? root.statsDataByVmid[vmid] : null
    }
    function isStatsLoading(vmid) {
        return root.statsLoadingByVmid[vmid] === true
    }
    function setStatsLoading(vmid, isLoading) {
        var m = Object.assign({}, root.statsLoadingByVmid)
        if (isLoading) { m[vmid] = true } else { delete m[vmid] }
        root.statsLoadingByVmid = m
    }
    function setStatsData(vmid, data) {
        var m = Object.assign({}, root.statsDataByVmid)
        m[vmid] = data
        root.statsDataByVmid = m
        root.setStatsLoading(vmid, false)
    }
    function requestStats(kind, nodeName, vmid) {
        root.setStatsLoading(vmid, true)
        controller.fetchStats("", kind, nodeName, vmid)
    }

    property bool loading: controller ? controller.loading : false
    property bool isRefreshing: controller ? controller.isRefreshing : false
    // Propagated explicitly via Connections.onErrorMessageChanged below.
    // Do NOT re-add a controller binding here: imperative writes (fetchData,
    // console/action errors, config changes) would silently kill it.
    property string errorMessage: ""
    property string lastUpdate: controller ? controller.lastUpdate : ""

    property bool actionPermHintShown: false
    property string actionPermHint: ""

    property var debugLog: []
    readonly property int debugLogMaxLines: 100

    property bool hasCoreConfig: {
        if (connectionMode === "multiHost") {
            // core config is at least one endpoint entry (host + tokenId)
            try {
                var arr = JSON.parse(multiHostsJson || "[]")
                if (!Array.isArray(arr)) return false
                for (var i = 0; i < arr.length; i++) {
                    var e = arr[i] || {}
                    if (e.enabled === false) continue
                    var h = (e.host || "").trim()
                    var t = (e.tokenId || "").trim()
                    if (h !== "" && t !== "") return true
                }
            } catch (e2) {}
            return false
        }
        return proxmoxHost !== "" && apiTokenId !== ""
    }

    /* "configured" means we have at least one usable endpoint and secrets resolved.
        During refresh-time secret re-resolution, keep the widget in configured state
        so it does not flash the not-configured UI between refreshes.
    */
    property bool configured: {
        if (connectionMode === "multiHost") {
            if (controller.secretState === "ready" && controller.endpoints && controller.endpoints.length > 0) return true
            return controller.refreshResolvingSecrets && displayedEndpoints && displayedEndpoints.length > 0
        }
        if (hasCoreConfig && controller.secretState === "ready") return true
        return hasCoreConfig && controller.refreshResolvingSecrets
    }
    property bool defaultsLoaded: false
    property bool devMode: false
    readonly property bool debugLogToJournal: false
    property int footerClickCount: 0

    // Per-item action busy map: key "node:kind:vmid" => true
    property var actionBusy: ({})

    // Two-click confirmation state (works in plasmoids where popups/dialogs may not render reliably)
    property string armedActionKey: ""
    property string armedLabel: ""

    Timer {
        id: armedTimer
        interval: 5000
        repeat: false
        onTriggered: {
            root.armedActionKey = ""
            root.armedLabel = ""
        }
    }

    // Avoid QQC2 Popup/Dialog in plasmoids

    // Collapsed state tracking for nodes
    property var collapsedNodes: ({})

    // State tracking for notifications
    property var previousVmStates: ({})
    property var previousLxcStates: ({})
    property var previousNodeStates: ({})
    property bool initialLoadComplete: false

    // Anonymization data for dev mode
    readonly property var anonNodeNames: ["server-01", "server-02", "server-03", "pve-node", "cluster-main"]
    readonly property var anonVmNames: ["web-server", "database", "backup-srv", "dev-env", "test-vm", "mail-server", "proxy", "monitoring", "gitlab", "nextcloud"]
    readonly property var anonLxcNames: ["nginx-proxy", "pihole", "postgres-db", "redis-cache", "mqtt-broker", "homeassistant", "grafana", "prometheus", "traefik", "portainer"]

    // Calculate total height needed (use displayed data)
    readonly property int nodeCount: displayedProxmoxData && displayedProxmoxData.data ? displayedProxmoxData.data.length : 0
    readonly property int vmCount: displayedVmData.length
    readonly property int lxcCount: displayedLxcData.length
    readonly property int calculatedHeight: {
        var h = 50
        if (!configured) return 200
        if (displayedProxmoxData && displayedProxmoxData.data) h += displayedProxmoxData.data.length * 90
        if (vmCount > 0) h += 28 + (vmCount * 36)
        if (lxcCount > 0) h += 28 + (lxcCount * 36)
        h += 40
        h += 20
        return Math.max(200, Math.min(h, 600))
    }

    Timer {
        id: footerClickTimer
        interval: 1000
        onTriggered: root.footerClickCount = 0
    }

    // Keep platform colors from Kirigami, but standardize shape/opacity rhythm
    readonly property int uiRadiusS: 4
    readonly property int uiRadiusM: 6
    readonly property int uiRadiusL: 8
    readonly property real uiBorderOpacity: 0.22
    readonly property color uiRunningColor: Plasmoid.configuration.appearanceRunningColor || Kirigami.Theme.positiveTextColor
    readonly property color uiStoppedColor: Plasmoid.configuration.appearanceStoppedColor || Kirigami.Theme.disabledTextColor
    readonly property color uiNodeColor: Plasmoid.configuration.appearanceNodeColor || Kirigami.Theme.backgroundColor
    readonly property real uiCardTintOpacity: Math.max(0, Math.min((Plasmoid.configuration.appearanceCardTintOpacity !== undefined ? Plasmoid.configuration.appearanceCardTintOpacity : 10) / 100, 0.40))
    readonly property real uiWindowOpacity: Math.max(0.60, Math.min((Plasmoid.configuration.appearanceWindowOpacity !== undefined ? Plasmoid.configuration.appearanceWindowOpacity : 100) / 100, 1.0))
    readonly property real uiSurfaceAltOpacity: uiCardTintOpacity > 0 ? uiCardTintOpacity : 0.10
    readonly property real uiSurfaceRunningOpacity: uiCardTintOpacity > 0 ? Math.min(uiCardTintOpacity + 0.02, 0.40) : 0.12
    readonly property real uiNodeCardOpacity: 0.98
    readonly property real uiMutedTextOpacity: 0.68
    readonly property int uiRowHeight: 30


    // Shell-escape for executable datasource usage
    function escapeShell(str) {
            if (!str) return ""
            return str.replace(/'/g, "'\\''")
        }

    // Clamp/sanitize CPU values coming from Proxmox.
    // On some restarts the initial cpu field can be garbage.
    function safeCpuPercent(cpuFraction) {
        var x = Number(cpuFraction)
        if (!isFinite(x) || isNaN(x)) return 0
        // Proxmox reports CPU as fraction (0..1 typically, can exceed 1 on some metrics).
        x = Math.max(0, Math.min(x, 1))
        return x * 100
    }
 
    // Redact sensitive identity fragments in debug logs / copied debug output.
    // Matches "user@realm" and "!tokenid"
    property string secretRedactRegex: "([A-Za-z0-9._-]+)@([A-Za-z0-9._-]+)|!([A-Za-z0-9._:-]+)"

    function redactSecretsForDebug(str) {
        str = String(str || "")
        return str.replace(new RegExp(secretRedactRegex, "g"), function(match, user, realm, tokenId) {
            if (user && realm) return "REDACTED@" + realm
            if (tokenId) return "!REDACTED"
            return match
        })
    }

    // Debug logging is gated behind developer mode to avoid flood.
    function logDebug(message) {
        if (!devMode) return

        var now = new Date()
        var timestamp = now.getFullYear() + "-" +
            (now.getMonth() + 1).toString().padStart(2, '0') + "-" +
            now.getDate().toString().padStart(2, '0') + " " +
            now.getHours().toString().padStart(2, '0') + ":" +
            now.getMinutes().toString().padStart(2, '0') + ":" +
            now.getSeconds().toString().padStart(2, '0') + "." +
            now.getMilliseconds().toString().padStart(3, '0')
        var safeMessage = redactSecretsForDebug(message)
        var line = "[Proxmox " + timestamp + "] " + safeMessage
        if (debugLogToJournal) console.log(line)

        var newLog = debugLog.slice()
        newLog.push(line)
        if (newLog.length > debugLogMaxLines) newLog.splice(0, newLog.length - debugLogMaxLines)
        debugLog = newLog
    }

    function buildDebugInfo() {
        var info = {
            version: (Plasmoid.metaData && Plasmoid.metaData.version) ? Plasmoid.metaData.version : "",
            host: proxmoxHost ? "REDACTED_HOST" : "",
            port: proxmoxPort,
            tokenId: apiTokenId ? redactSecretsForDebug(apiTokenId) : "",
            ignoreSsl: ignoreSsl,
            refreshIntervalSeconds: Math.round(refreshInterval / 1000),
            autoRetry: autoRetry,
            retryStartSeconds: Math.round(retryStartMs / 1000),
            retryMaxSeconds: Math.round(retryMaxMs / 1000),
            lastUpdate: lastUpdate,
            errorMessage: redactSecretsForDebug(errorMessage),
            nodeCount: displayedNodeList.length,
            vmCount: displayedVmData.length,
            lxcCount: displayedLxcData.length,
            trustedCertPemSet: !!((trustedCertPem || "").trim()),
            trustedCertPathSet: !!((trustedCertPath || "").trim()),
            qmlLog: debugLog.map(function(line) { return redactSecretsForDebug(line) }),
            controllerLog: controller ? controller.debugLog : []
        }
        return JSON.stringify(info, null, 2)
    }

    function copyDebugInfo() {
        var payload = buildDebugInfo()
        var encoded = Qt.btoa(payload)
        var cmd = "sh -lc 'printf %s \"" + encoded + "\" | base64 -d | " +
            "if command -v wl-copy >/dev/null 2>&1; then wl-copy; " +
            "elif command -v xclip >/dev/null 2>&1; then xclip -selection clipboard; " +
            "else exit 1; fi'"
        executable.connectSource(cmd)
        sendNotification("Debug logs copied")
    }


    // Escape regex special chars except "*"
    function escapeRegexPattern(str) {
        if (!str) return ""
        // Escape regex metacharacters but intentionally leave "*" untouched so
        // shouldNotify() can expand wildcard filters into ".*" afterwards.
        return str.replace(/[.+?^${}()|[\]\\]/g, "\\$&")
    }

    // Check if a VM/container should trigger notifications based on filter
    function shouldNotify(name, vmid) {
        if (notifyMode === "all") {
            return true
        }

        // Empty filter behavior:
        // - whitelist: nothing matches => no notifications
        // - blacklist: nothing excluded => notify everything
        if (!notifyFilter || notifyFilter.trim() === "") {
            return notifyMode === "blacklist"
        }

        var filters = notifyFilter.split(",").map(function(f) {
            return f.trim().toLowerCase()
        }).filter(function(f) {
            return f.length > 0
        })

        if (filters.length === 0) {
            return notifyMode === "blacklist"
        }

        var nameL = (name || "").toLowerCase()
        var vmidStr = String(vmid)

        var matches = filters.some(function(filter) {
            // Check for wildcard patterns
            if (filter.indexOf("*") !== -1) {
                // Expand literal wildcard markers only after escaping the rest of
                // the pattern; otherwise inputs like "web*" become /^web\*$/.
                var escaped = escapeRegexPattern(filter).replace(/\*/g, ".*")
                var regex = new RegExp("^" + escaped + "$")
                return regex.test(nameL) || regex.test(vmidStr)
            }
            // Exact match
            return nameL === filter || vmidStr === filter
        })

        if (notifyMode === "whitelist") {
            return matches
        } else if (notifyMode === "blacklist") {
            return !matches
        }

        return true
    }

    ProxMon.Notifier {
        id: notifier
    }

    function shouldRateLimitNotify(key) {
        if (!notifyRateLimitEnabled) return false
        if (!notifyRateLimitSeconds || notifyRateLimitSeconds <= 0) return false
        if (!key) return false

        var last = notifyLastSent[key]
        if (!last) return false

        var now = Date.now()
        return (now - last) < (notifyRateLimitSeconds * 1000)
    }

    function markNotifySent(key) {
        if (!key) return
        var now = Date.now()
        var newMap = Object.assign({}, notifyLastSent)
        newMap[key] = now
        notifyLastSent = newMap
    }

    function sendNotification(title, message, iconName, rateLimitKey) {
        if (!enableNotifications) {
            return
        }

        if (rateLimitKey && shouldRateLimitNotify(rateLimitKey)) {
            logDebug("Notification rate-limited: " + rateLimitKey)
            return
        }

        // Prevent newlines from breaking the shell command
        title = (title || "").replace(/[\r\n]+/g, " ")
        message = (message || "").replace(/[\r\n]+/g, " ")

        // Redact sensitive "user@realm!tokenid" fragments from notification text.
        function redactIdentities(str) {
            str = String(str || "")
            // redact "user@realm" portion but preserve realm
            str = str.replace(/([A-Za-z0-9._-]+)@([A-Za-z0-9._-]+)/g, "REDACTED@$2")
            // redact token id portion after "!"
            str = str.replace(/!([A-Za-z0-9._:-]+)/g, "!REDACTED")
            return str
        }

        if (redactNotifyIdentities) {
            title = redactIdentities(title)
            message = redactIdentities(message)
        }

        logDebug("Notification: " + title + " - " + message)

        // Prefer D-Bus notifier; fallback to notify-send.
        if (notifier.notify(title, message, iconName || "proxmox-monitor", 5000)) {
            if (rateLimitKey) markNotifySent(rateLimitKey)
            return
        }

        var safeIcon = escapeShell(iconName || "proxmox-monitor")
        var safeTitle = escapeShell(title)
        var safeMessage = escapeShell(message)

        var notifyCmd = "notify-send -i '" + safeIcon + "' -a 'Proxmox Monitor' '" + safeTitle + "' '" + safeMessage + "'"
        executable.connectSource(notifyCmd)
        if (rateLimitKey) markNotifySent(rateLimitKey)
    }

    // Test notifications function
    function testNotifications() {
        logDebug("Testing notifications...")
        sendNotification("VM Stopped", "test-vm (100) on pve1 is now stopped", "dialog-warning")
    }

    // Multi-host notification state keys must be namespaced by endpoint/session so
    // identical node names / VMIDs on different controller.endpoints do not overwrite each other.
    function multiHostNodeStateKey(sessionKey, nodeName) {
        return String(sessionKey) + "::" + String(nodeName || "")
    }

    function multiHostVmStateKey(sessionKey, nodeName, vmid) {
        return String(sessionKey) + "::" + String(nodeName || "") + "_vm_" + vmid
    }

    function multiHostLxcStateKey(sessionKey, nodeName, vmid) {
        return String(sessionKey) + "::" + String(nodeName || "") + "_lxc_" + vmid
    }

    function pushGroupedNotificationEntry(entries, kindLabel, item) {
        entries.push({
            kind: kindLabel,
            vmid: String(item.vmid),
            name: String(item.name || item.vmid)
        })
    }

    function formatGroupedNotificationSection(entries, kindLabel, verb) {
        var matching = entries.filter(function(entry) {
            return entry.kind === kindLabel
        })
        if (matching.length === 0) return ""

        var ids = matching.map(function(entry) { return entry.vmid }).join(", ")
        var names = matching.map(function(entry) { return entry.name }).join(", ")
        var label = kindLabel === "CT" ? "LXCs" : (kindLabel + "s")
        return label + ": " + ids + "  " + names
    }

    function sendGroupedNotification(entries, iconName, rateLimitKey, verb) {
        if (!entries || entries.length === 0) return

        var sections = []
        var vmSection = formatGroupedNotificationSection(entries, "VM", verb)
        var ctSection = formatGroupedNotificationSection(entries, "CT", verb)
        if (vmSection) sections.push(vmSection)
        if (ctSection) sections.push(ctSection)

        if (sections.length === 0) return

        var kinds = entries.map(function(entry) { return entry.kind })
        var hasVm = kinds.indexOf("VM") !== -1
        var hasCt = kinds.indexOf("CT") !== -1
        var title = hasVm && !hasCt
            ? (verb === "started" ? "VMs Started" : "VMs Stopped")
            : hasCt && !hasVm
            ? (verb === "started" ? "LXCs Started" : "LXCs Stopped")
            : (verb === "started" ? "Workloads Started" : "Workloads Stopped")

        sendNotification(title, sections.join("; "), iconName, rateLimitKey)
    }

    // Check for state changes and send notifications
    function checkStateChanges() {
        if (connectionMode === "multiHost") {
            var multiStartedEntries = []
            var multiStoppedEntries = []

            // No displayed endpoint buckets means there is nothing stable to compare yet.
            if (!displayedEndpoints || displayedEndpoints.length === 0) return

            if (!initialLoadComplete) {
                logDebug("checkStateChanges(multi): Initial load, recording states")

                // Record initial node states
                for (var mn = 0; mn < displayedEndpoints.length; mn++) {
                    var endpoint = displayedEndpoints[mn]
                    if (!endpoint || !endpoint.sessionKey || !endpoint.nodes) continue

                    for (var mni = 0; mni < endpoint.nodes.length; mni++) {
                        var multiNode = endpoint.nodes[mni]
                        previousNodeStates[multiHostNodeStateKey(endpoint.sessionKey, multiNode.node)] = multiNode.status
                    }
                }

                // Record initial VM states per endpoint/session. Items missing sessionKey
                // are ignored silently so partial/malformed multi-host data does not spam logs.
                for (var mvi = 0; mvi < displayedVmData.length; mvi++) {
                    var multiVm = displayedVmData[mvi]
                    if (!multiVm || !multiVm.sessionKey) continue
                    previousVmStates[multiHostVmStateKey(multiVm.sessionKey, multiVm.node, multiVm.vmid)] = multiVm.status
                }

                // Record initial LXC states per endpoint/session.
                for (var mli = 0; mli < displayedLxcData.length; mli++) {
                    var multiLxc = displayedLxcData[mli]
                    if (!multiLxc || !multiLxc.sessionKey) continue
                    previousLxcStates[multiHostLxcStateKey(multiLxc.sessionKey, multiLxc.node, multiLxc.vmid)] = multiLxc.status
                }

                initialLoadComplete = true
                return
            }

            // Check nodes for state changes
            if (notifyOnNodeChange) {
                for (var mei = 0; mei < displayedEndpoints.length; mei++) {
                    var endpointData = displayedEndpoints[mei]
                    if (!endpointData || !endpointData.sessionKey || !endpointData.nodes) continue

                    for (var mni2 = 0; mni2 < endpointData.nodes.length; mni2++) {
                        var nodeDataMulti = endpointData.nodes[mni2]
                        var nodeStateKey = multiHostNodeStateKey(endpointData.sessionKey, nodeDataMulti.node)
                        var prevNodeStateMulti = previousNodeStates[nodeStateKey]

                        if (prevNodeStateMulti !== undefined && prevNodeStateMulti !== nodeDataMulti.status) {
                            if (prevNodeStateMulti === "online" && nodeDataMulti.status !== "online") {
                                sendNotification(
                                    "Node Offline",
                                    nodeDataMulti.node + " is now " + nodeDataMulti.status,
                                    "dialog-error",
                                    "node:" + endpointData.sessionKey + ":" + nodeDataMulti.node + ":offline"
                                )
                            } else if (prevNodeStateMulti !== "online" && nodeDataMulti.status === "online") {
                                sendNotification(
                                    "Node Online",
                                    nodeDataMulti.node + " is back online",
                                    "dialog-information",
                                    "node:" + endpointData.sessionKey + ":" + nodeDataMulti.node + ":online"
                                )
                            }
                        }
                        previousNodeStates[nodeStateKey] = nodeDataMulti.status
                    }
                }
            }

            // Check VMs for state changes per endpoint/session while keeping existing
            // notification content and rate-limit keys unchanged.
            for (var mvm = 0; mvm < displayedVmData.length; mvm++) {
                var vmItemMulti = displayedVmData[mvm]
                if (!vmItemMulti || !vmItemMulti.sessionKey) continue

                var vmStateKeyMulti = multiHostVmStateKey(vmItemMulti.sessionKey, vmItemMulti.node, vmItemMulti.vmid)
                var prevVmStateMulti = previousVmStates[vmStateKeyMulti]

                if (prevVmStateMulti !== undefined && prevVmStateMulti !== vmItemMulti.status) {
                    if (shouldNotify(vmItemMulti.name, vmItemMulti.vmid)) {
                        if (notifyOnStop && prevVmStateMulti === "running" && vmItemMulti.status !== "running") {
                            pushGroupedNotificationEntry(multiStoppedEntries, "VM", vmItemMulti)
                        } else if (notifyOnStart && prevVmStateMulti !== "running" && vmItemMulti.status === "running") {
                            pushGroupedNotificationEntry(multiStartedEntries, "VM", vmItemMulti)
                        }
                    }
                        // Safety-net: clear busy spinner if status changed                    if (root.isActionBusy(vmItemMulti.node, "qemu", vmItemMulti.vmid, vmItemMulti.sessionKey))
                        root.setActionBusy(vmItemMulti.node, "qemu", vmItemMulti.vmid, false, vmItemMulti.sessionKey)
                }
                previousVmStates[vmStateKeyMulti] = vmItemMulti.status
            }

            // Check LXCs for state changes per endpoint/session while keeping existing
            // notification content and rate-limit keys unchanged.
            for (var mlx = 0; mlx < displayedLxcData.length; mlx++) {
                var lxcItemMulti = displayedLxcData[mlx]
                if (!lxcItemMulti || !lxcItemMulti.sessionKey) continue

                var lxcStateKeyMulti = multiHostLxcStateKey(lxcItemMulti.sessionKey, lxcItemMulti.node, lxcItemMulti.vmid)
                var prevLxcStateMulti = previousLxcStates[lxcStateKeyMulti]

                if (prevLxcStateMulti !== undefined && prevLxcStateMulti !== lxcItemMulti.status) {
                    if (shouldNotify(lxcItemMulti.name, lxcItemMulti.vmid)) {
                        if (notifyOnStop && prevLxcStateMulti === "running" && lxcItemMulti.status !== "running") {
                            pushGroupedNotificationEntry(multiStoppedEntries, "CT", lxcItemMulti)
                        } else if (notifyOnStart && prevLxcStateMulti !== "running" && lxcItemMulti.status === "running") {
                            pushGroupedNotificationEntry(multiStartedEntries, "CT", lxcItemMulti)
                        }
                    }
                    // Safety-net: clear busy spinner if status changed
                    if (root.isActionBusy(lxcItemMulti.node, "lxc", lxcItemMulti.vmid, lxcItemMulti.sessionKey))
                        root.setActionBusy(lxcItemMulti.node, "lxc", lxcItemMulti.vmid, false, lxcItemMulti.sessionKey)
                }
                previousLxcStates[lxcStateKeyMulti] = lxcItemMulti.status
            }

            logDebug("checkStateChanges(multi): started=" + multiStartedEntries.length + " stopped=" + multiStoppedEntries.length)
            sendGroupedNotification(multiStartedEntries,
                                    "dialog-information",
                                    "grouped:multi:running:" + multiStartedEntries.map(function(entry) { return entry.kind + ":" + entry.vmid }).sort().join(","),
                                    "started")
            sendGroupedNotification(multiStoppedEntries,
                                    "dialog-warning",
                                    "grouped:multi:stopped:" + multiStoppedEntries.map(function(entry) { return entry.kind + ":" + entry.vmid }).sort().join(","),
                                    "stopped")
            return
        }

        var startedEntries = []
        var stoppedEntries = []

        if (!initialLoadComplete) {
            // Record initial node states
            if (displayedProxmoxData && displayedProxmoxData.data) {
                for (var n = 0; n < displayedProxmoxData.data.length; n++) {
                    var node = displayedProxmoxData.data[n]
                    previousNodeStates[node.node] = node.status
                }
            }

            // Record initial VM states
            for (var i = 0; i < displayedVmData.length; i++) {
                var vm = displayedVmData[i]
                var vmKey = vm.node + "_vm_" + vm.vmid
                previousVmStates[vmKey] = vm.status
            }

            // Record initial LXC states
            for (var j = 0; j < displayedLxcData.length; j++) {
                var lxc = displayedLxcData[j]
                var lxcKey = lxc.node + "_lxc_" + lxc.vmid
                previousLxcStates[lxcKey] = lxc.status
            }

            initialLoadComplete = true
            return
        }

        // Check nodes for state changes
        if (notifyOnNodeChange && displayedProxmoxData && displayedProxmoxData.data) {
            for (var ni = 0; ni < displayedProxmoxData.data.length; ni++) {
                var nodeData = displayedProxmoxData.data[ni]
                var prevNodeState = previousNodeStates[nodeData.node]

                if (prevNodeState !== undefined && prevNodeState !== nodeData.status) {
                    if (prevNodeState === "online" && nodeData.status !== "online") {
                        sendNotification(
                            "Node Offline",
                            nodeData.node + " is now " + nodeData.status,
                            "dialog-error",
                            "node:" + nodeData.node + ":offline"
                        )
                    } else if (prevNodeState !== "online" && nodeData.status === "online") {
                        sendNotification(
                            "Node Online",
                            nodeData.node + " is back online",
                            "dialog-information",
                            "node:" + nodeData.node + ":online"
                        )
                    }
                }
                previousNodeStates[nodeData.node] = nodeData.status
            }
        }

        // Check VMs for state changes
        for (var vi = 0; vi < displayedVmData.length; vi++) {
            var vmItem = displayedVmData[vi]
            var vmStateKey = vmItem.node + "_vm_" + vmItem.vmid
            var prevVmState = previousVmStates[vmStateKey]

            if (prevVmState !== undefined && prevVmState !== vmItem.status) {
                logDebug("checkStateChanges: VM " + vmItem.name + " changed from " + prevVmState + " to " + vmItem.status)

                // Check if this VM should trigger notifications
                if (shouldNotify(vmItem.name, vmItem.vmid)) {
                    if (notifyOnStop && prevVmState === "running" && vmItem.status !== "running") {
                        pushGroupedNotificationEntry(stoppedEntries, "VM", vmItem)
                    } else if (notifyOnStart && prevVmState !== "running" && vmItem.status === "running") {
                        pushGroupedNotificationEntry(startedEntries, "VM", vmItem)
                    }
                }
                // Safety-net: clear busy spinner if status changed
                if (root.isActionBusy(vmItem.node, "qemu", vmItem.vmid))
                    root.setActionBusy(vmItem.node, "qemu", vmItem.vmid, false)
            }
            previousVmStates[vmStateKey] = vmItem.status
        }

        // Check LXCs for state changes
        for (var li = 0; li < displayedLxcData.length; li++) {
            var lxcItem = displayedLxcData[li]
            var lxcStateKey = lxcItem.node + "_lxc_" + lxcItem.vmid
            var prevLxcState = previousLxcStates[lxcStateKey]

            if (prevLxcState !== undefined && prevLxcState !== lxcItem.status) {
                logDebug("checkStateChanges: LXC " + lxcItem.name + " changed from " + prevLxcState + " to " + lxcItem.status)

                // Check if this LXC should trigger notifications
                if (shouldNotify(lxcItem.name, lxcItem.vmid)) {
                    if (notifyOnStop && prevLxcState === "running" && lxcItem.status !== "running") {
                        pushGroupedNotificationEntry(stoppedEntries, "CT", lxcItem)
                    } else if (notifyOnStart && prevLxcState !== "running" && lxcItem.status === "running") {
                        pushGroupedNotificationEntry(startedEntries, "CT", lxcItem)
                    }
                }
                // Safety-net: clear busy spinner if status changed
                if (root.isActionBusy(lxcItem.node, "lxc", lxcItem.vmid))
                    root.setActionBusy(lxcItem.node, "lxc", lxcItem.vmid, false)
            }
            previousLxcStates[lxcStateKey] = lxcItem.status
        }

        sendGroupedNotification(startedEntries,
                                "dialog-information",
                                "grouped:single:running:" + startedEntries.map(function(entry) { return entry.kind + ":" + entry.vmid }).sort().join(","),
                                "started")
        sendGroupedNotification(stoppedEntries,
                                "dialog-warning",
                                "grouped:single:stopped:" + stoppedEntries.map(function(entry) { return entry.kind + ":" + entry.vmid }).sort().join(","),
                                "stopped")
    }



    function actionKey(nodeName, kind, vmid, sessionKey) {
        if (sessionKey) return sessionKey + "::" + nodeName + ":" + kind + ":" + vmid
        return nodeName + ":" + kind + ":" + vmid
    }

    function isActionBusy(nodeName, kind, vmid, sessionKey) {
        return actionBusy[actionKey(nodeName, kind, vmid, sessionKey)] === true
    }

    function setActionBusy(nodeName, kind, vmid, busy, sessionKey) {
        var key = actionKey(nodeName, kind, vmid, sessionKey)
        var newBusy = Object.assign({}, actionBusy)
        if (busy) {
            newBusy[key] = true
        } else {
            delete newBusy[key]
        }
        actionBusy = newBusy
    }


    function confirmAndRunAction(kind, nodeName, vmid, displayName, action) {
        // Plasma sometimes doesn't show QQC2.Popup/Overlay sometimes, We Use safe "two-step confirmation" instead.
        logDebug("confirmAndRunAction: " + kind + " " + nodeName + " " + vmid + " " + action)

        var key = kind + ":" + nodeName + ":" + vmid + ":" + action
        if (armedActionKey === key && armedTimer.running) {
            armedActionKey = ""
            armedTimer.stop()
            setActionBusy(nodeName, kind, vmid, true)
            controller.runAction("", kind, nodeName, vmid, action)
            return
        }

        armedActionKey = key
        armedLabel = "Click again to confirm " + action + " (" + kind + " " + vmid + ")"
        armedTimer.restart()
    }

    function confirmAndRunActionForSession(sessionKey, kind, nodeName, vmid, displayName, action) {
        logDebug("confirmAndRunActionForSession: " + sessionKey + " " + kind + " " + nodeName + " " + vmid + " " + action)

        var key = sessionKey + "::" + kind + ":" + nodeName + ":" + vmid + ":" + action
        if (armedActionKey === key && armedTimer.running) {
            armedActionKey = ""
            armedTimer.stop()
            setActionBusy(nodeName, kind, vmid, true, sessionKey)
            controller.runAction(sessionKey, kind, nodeName, vmid, action)
            return
        }

        armedActionKey = key
        armedLabel = "Click again to confirm " + action + " (" + kind + " " + vmid + ")"
        armedTimer.restart()
    }

    // Toggle node collapsed state
    function toggleNodeCollapsed(nodeName, sessionKey) {
        var k = (connectionMode === "multiHost" && sessionKey) ? endpointNodeKey(sessionKey, nodeName) : nodeName
        var newState = !isNodeCollapsed(nodeName, sessionKey)
        logDebug("toggleNodeCollapsed: " + k + " -> " + (newState ? "collapsed" : "expanded"))
        var newCollapsed = Object.assign({}, collapsedNodes)
        newCollapsed[k] = newState
        collapsedNodes = newCollapsed
    }

    // Check if node is collapsed
    function isNodeCollapsed(nodeName, sessionKey) {
        var k2 = (connectionMode === "multiHost" && sessionKey) ? endpointNodeKey(sessionKey, nodeName) : nodeName
        return collapsedNodes[k2] === true
    }


    function anonymizeHost(host) {
        if (!devMode) return host
        return "192.168.x.x"
    }

    function anonymizeNodeName(name, index) {
        if (!devMode) return name
        return anonNodeNames[index % anonNodeNames.length]
    }

    function anonymizeVmName(name, index) {
        if (!devMode) return name
        return anonVmNames[index % anonVmNames.length]
    }

    function anonymizeLxcName(name, index) {
        if (!devMode) return name
        return anonLxcNames[index % anonLxcNames.length]
    }

    function anonymizeVmId(id, index) {
        if (!devMode) return id
        return 100 + index
    }

    function anonymizeIp(ip) {
        if (!devMode) return ip
        return "192.168.x.x"
    }


    function handleFooterClick() {
        footerClickCount++
        if (footerClickCount >= 3) {
            devMode = !devMode
            footerClickCount = 0
            logDebug("Developer mode: ENABLED")
        }
        footerClickTimer.restart()
    }

    // Get node name from API URL
    function getNodeFromSource(source) {
        var match = source.match(/\/nodes\/([^\/]+)\//)
        return match ? match[1] : ""
    }

        // Atomically swap displayed data when all requests finish


    // Confirm is two-click (see confirmAndRunAction()); QQC2.Popup overlays are unreliable in plasmoids.

    Timer {
        id: secretResolveDebounce
        interval: 150
        repeat: false
        onTriggered: {
            root.logDebug("secretResolveDebounce: resolving secrets after config change")
            root.resolveSecretIfNeeded()
        }
    }

    function triggerSecretResolveFromConfigChange() {
        secretResolveDebounce.restart()
    }

    // Debounce refresh when config changes (avoids hammering API while user is typing).
    Timer {
        id: configRefreshDebounce
        interval: 600
        repeat: false
        onTriggered: {
            root.logDebug("configRefreshDebounce: triggering refresh after config change")
            root.fetchData()
        }
    }

    function triggerRefreshFromConfigChange(reason) {
        logDebug("config change: " + (reason || "unknown"))
        // Cancel in-flight requests and retry timers so we restart cleanly.
        controller.cancelRefresh()
        errorMessage = ""
        retryStatusText = ""
        armedActionKey = ""
        armedLabel = ""

        if (reason === "connectionMode" || reason === "multiHostsJson"
                || reason === "proxmoxHost" || reason === "proxmoxPort"
                || reason === "apiTokenId" || reason === "apiTokenSecret") {
            previousVmStates = ({})
            previousLxcStates = ({})
            previousNodeStates = ({})
            initialLoadComplete = false
        }

        // If secrets need re-resolving (e.g. token changed), resolveSecretIfNeeded() handlers will do it.
        // On mode/config swaps we may temporarily be unconfigured until the target config lands, so keep
        // the pending refresh armed and let secret/config handlers trigger the eventual fetch.
        if (!configured && !controllerPendingResolvedRefresh) return
        configRefreshDebounce.restart()
    }

    function refreshAfterSecretReady() {
        if (!controllerPendingResolvedRefresh) return
        controllerPendingResolvedRefresh = false
        if (!configured || loading || isRefreshing) return
        configRefreshDebounce.restart()
    }

    function fetchData() {
        errorMessage = ""
        controller.fetchData()
    }

    // Use displayed data for counts
    property int runningVMs: {
        var count = 0
        for (var i = 0; i < displayedVmData.length; i++) {
            if (displayedVmData[i].status === "running") count++
        }
        return count
    }

    property int runningLXC: {
        var count = 0
        for (var i = 0; i < displayedLxcData.length; i++) {
            if (displayedLxcData[i].status === "running") count++
        }
        return count
    }


    function endpointNodeKey(sessionKey, nodeName) {
        return String(sessionKey) + "::" + String(nodeName || "")
    }

    // Multi-host aggregation is controller-owned

    Connections {
        target: controller
        function onDisplayedEndpointsChanged() {
            root.checkStateChanges()
        }
        function onIsRefreshingChanged() {
            if (!controller.isRefreshing && root.connectionMode !== "multiHost") root.checkStateChanges()
        }
        function onErrorMessageChanged() {
            root.errorMessage = controller.errorMessage
        }
        function onRetryStatusTextChanged() {
            root.retryStatusText = controller.retryStatusText
        }
        function onPbsLastErrorChanged() {
            root.pbsError = controller.pbsLastError
        }
        function onActionReply(sessionKey, actionKind, node, vmid, action, data) {
            root.setActionBusy(node, actionKind, vmid, false, sessionKey)
        }
        function onConsoleReady(sessionKey, requestId, host, node, kind, vmid, vmName, vncPort, apiPort, ignoreSsl, trustedCertPem, trustedCertPath) {
            var key = root.consoleWindowKey(sessionKey, kind, node, vmid)
            if (root.openConsoles[key]) {
                // Auth header and ticket for reconnect are stashed in controller registry.
                root.openConsoles[key].consoleRequestId = requestId
                root.openConsoles[key].trustedCertPem = trustedCertPem
                root.openConsoles[key].trustedCertPath = trustedCertPath
                root.openConsoles[key].connectWithTicket(vncPort)
                root.openConsoles[key].raise()
                root.openConsoles[key].requestActivate()
                return
            }
            var win = consoleComponent.createObject(root, {
                controller: controller,
                host: host,
                nodeName: node,
                vmid: vmid,
                vmName: vmName || (kind + " " + vmid),
                vncPort: vncPort,
                sessionKey: sessionKey,
                consoleRequestId: requestId,
                kind: kind,
                apiPort: apiPort,
                ignoreSsl: ignoreSsl,
                trustedCertPem: trustedCertPem,
                trustedCertPath: trustedCertPath
            })
            root.openConsoles[key] = win
            win.closing.connect(function() {
                delete root.openConsoles[key]
                win.destroy()
            })
            win.requestReconnect.connect(function() {
                controller.openConsole(win.sessionKey, win.kind, win.nodeName, win.vmid, win.vmName)
            })
        }
        function onLxcConsoleReady(sessionKey, requestId, host, apiPort, node, vmid, vmName, proxyPort, user, ignoreSsl, trustedCertPem, trustedCertPath) {
            var kind = vmid === 0 ? "node" : "lxc"
            var key = root.consoleWindowKey(sessionKey, kind, node, vmid)
            var label = vmid === 0 ? (vmName || node) : (vmName || ("lxc " + vmid))
            if (root.openConsoles[key]) {
                // Deliver fresh auth header and ticket from C++ registry.
                controller.deliverConsoleAuth(requestId, root.openConsoles[key])
                controller.deliverConsoleTicket(requestId, root.openConsoles[key])
                root.openConsoles[key].connectWithTicket(proxyPort, user, ignoreSsl)
                root.openConsoles[key].raise()
                return
            }
            var term = lxcTerminalComponent.createObject(root)
            if (!term) {
                console.warn("LxcTerminal createObject failed:",
                             lxcTerminalComponent.errorString())
                return
            }
            // Closure-capture session info so requestReconnect can round-trip
            // back to controller.openConsole. (QML won't allow attaching ad-hoc
            // properties to a C++ QObject; capture is the clean equivalent.)
            var capturedSession = sessionKey
            var capturedNode = node
            var capturedVmid = vmid
            var capturedLabel = label
            root.openConsoles[key] = term
            term.closed.connect(function() {
                delete root.openConsoles[key]
                term.destroy()
            })
            term.requestReconnect.connect(function() {
                if (capturedVmid === 0) {
                    controller.openConsole(capturedSession, "node", capturedNode, 0, capturedLabel)
                } else {
                    controller.openConsole(capturedSession, "lxc", capturedNode, capturedVmid, capturedLabel)
                }
            })
            // Deliver auth header and ticket from C++ registry before open().
            controller.deliverConsoleAuth(requestId, term)
            controller.deliverConsoleTicket(requestId, term)
            term.windowPreset = Plasmoid.configuration.terminalSize || "medium"
            term.open(host, apiPort, node, vmid, label, proxyPort, user, ignoreSsl, trustedCertPem, trustedCertPath)
        }
        function onConsoleError(node, kind, vmid, message) {
            root.errorMessage = "Console failed: " + message
        }
        function onActionError(sessionKey, actionKind, node, vmid, action, message) {
            root.setActionBusy(node, actionKind, vmid, false, sessionKey)
            root.errorMessage = message || ("Action failed: " + action)
            configRefreshDebounce.restart()
        }
        function onStatsReady(sessionKey, node, vmid, data) {
            root.setStatsData(vmid, data)
        }
        function onStatsError(sessionKey, node, vmid, message) {
            root.setStatsLoading(vmid, false)
            root.setStatsData(vmid, { error: message })
        }
    }

    function resolveSecretIfNeeded() {
        controller.resolveSecretsIfNeeded()
    }

    function migratePbsTokenSecretBuffer() {
        const secret = String(Plasmoid.configuration.pbsTokenSecretBuffer || "")
        const host = String(Plasmoid.configuration.pbsHost || "").trim()
        if (!controller || !secret.trim() || !host) return

        // Remove the plaintext handoff before starting the asynchronous
        // keychain write. The local QML value dies when this call returns.
        Plasmoid.configuration.pbsTokenSecretBuffer = ""
        controller.storeSinglePBSSecret(host, secret)
    }

    onProxmoxHostChanged: {
        if (connectionMode === "single") triggerSecretResolveFromConfigChange()
        triggerRefreshFromConfigChange("proxmoxHost")
    }
    onProxmoxPortChanged: {
        if (connectionMode === "single") triggerSecretResolveFromConfigChange()
        triggerRefreshFromConfigChange("proxmoxPort")
    }
    onApiTokenIdChanged: {
        if (connectionMode === "single") triggerSecretResolveFromConfigChange()
        triggerRefreshFromConfigChange("apiTokenId")
    }

    onApiTokenSecretChanged: {
        if (connectionMode === "single" && apiTokenSecret && apiTokenSecret.trim() !== "") {
            controller.storeSingleSecret(apiTokenSecret)
            Plasmoid.configuration.apiTokenSecret = ""
        }
        if (connectionMode === "single") triggerSecretResolveFromConfigChange()
        triggerRefreshFromConfigChange("apiTokenSecret")
    }
    onPbsTokenSecretBufferChanged: migratePbsTokenSecretBuffer()
    onTrustedCertPemChanged: triggerRefreshFromConfigChange("trustedCertPem")
    onTrustedCertPathChanged: triggerRefreshFromConfigChange("trustedCertPath")
    onPbsTrustedCertPemChanged: triggerRefreshFromConfigChange("pbsTrustedCertPem")
    onPbsTrustedCertPathChanged: triggerRefreshFromConfigChange("pbsTrustedCertPath")
    onMultiHostSecretsJsonChanged: {
        if (connectionMode !== "multiHost") return
        if (!multiHostSecretsJson || multiHostSecretsJson.trim() === "") return
        var map = {}
        try { map = JSON.parse(multiHostSecretsJson || "{}") } catch (e) { map = {} }
        var wrote = false
        for (var key in map) {
            if (!Object.prototype.hasOwnProperty.call(map, key)) continue
            var secret = String(map[key] || "")
            if (!secret.trim()) continue

            if (key.indexOf("apiTokenSecret:") === 0) {
                var body = key.slice("apiTokenSecret:".length)
                var colon = body.lastIndexOf(":")
                var left = colon > 0 ? body.slice(0, colon) : ""
                var port = colon > 0 ? Number(body.slice(colon + 1)) : 8006
                var at = left.lastIndexOf("@")
                var tokenId = at > 0 ? left.slice(0, at) : ""
                var host = at > 0 ? left.slice(at + 1) : ""
                if (!host || !tokenId) continue
                controller.storeMultiHostSecret(host, port > 0 ? port : 8006, tokenId, secret)
                wrote = true
                continue
            }

            if (key.indexOf("pbsTokenSecret:") === 0) {
                var pbsHost = key.slice("pbsTokenSecret:".length).trim()
                if (!pbsHost) continue
                controller.storeMultiHostPBSSecret(pbsHost, secret)
                wrote = true
            }
        }
        if (wrote) {
            Plasmoid.configuration.multiHostSecretsJson = "{}"
        }
    }
    onMultiHostSharedCertChanged: triggerRefreshFromConfigChange("multiHostSharedCert")

    onMultiHostsJsonChanged: {
        controllerPendingResolvedRefresh = true
        if (connectionMode === "multiHost") triggerSecretResolveFromConfigChange()
        triggerRefreshFromConfigChange("multiHostsJson")
    }
    onConnectionModeChanged: {
        controllerPendingResolvedRefresh = true
        triggerSecretResolveFromConfigChange()
        triggerRefreshFromConfigChange("connectionMode")
    }

    onRefreshIntervalChanged: triggerRefreshFromConfigChange("refreshInterval")
    onIgnoreSslChanged: triggerRefreshFromConfigChange("ignoreSsl")
    onPbsEnabledChanged: triggerRefreshFromConfigChange("pbsEnabled")
    onPbsHostChanged: {
        migratePbsTokenSecretBuffer()
        triggerRefreshFromConfigChange("pbsHost")
    }
    onPbsPortChanged: triggerRefreshFromConfigChange("pbsPort")
    onPbsTokenIdChanged: triggerRefreshFromConfigChange("pbsTokenId")
    onPbsIgnoreSslChanged: triggerRefreshFromConfigChange("pbsIgnoreSsl")
    onPbsBackupWarningDaysChanged: triggerRefreshFromConfigChange("pbsBackupWarningDays")
    onPbsBackupStaleDaysChanged: triggerRefreshFromConfigChange("pbsBackupStaleDays")
    onPbsRefreshIntervalChanged: triggerRefreshFromConfigChange("pbsRefreshInterval")
    onPbsExcludeTagChanged: triggerRefreshFromConfigChange("pbsExcludeTag")
    onPbsExcludeVmidsChanged: triggerRefreshFromConfigChange("pbsExcludeVmids")
    onAutoRetryChanged: triggerRefreshFromConfigChange("autoRetry")
    onRetryStartMsChanged: triggerRefreshFromConfigChange("retryStartMs")
    onRetryMaxMsChanged: triggerRefreshFromConfigChange("retryMaxMs")
    onEnableNotificationsChanged: triggerRefreshFromConfigChange("enableNotifications")
    onNotifyModeChanged: triggerRefreshFromConfigChange("notifyMode")
    onNotifyFilterChanged: triggerRefreshFromConfigChange("notifyFilter")
    onNotifyOnStopChanged: triggerRefreshFromConfigChange("notifyOnStop")
    onNotifyOnStartChanged: triggerRefreshFromConfigChange("notifyOnStart")
    onNotifyOnNodeChangeChanged: triggerRefreshFromConfigChange("notifyOnNodeChange")
    onNotifyRateLimitEnabledChanged: triggerRefreshFromConfigChange("notifyRateLimitEnabled")
    onNotifyRateLimitSecondsChanged: triggerRefreshFromConfigChange("notifyRateLimitSeconds")
    onCompactModeChanged: triggerRefreshFromConfigChange("compactMode")

    Component.onCompleted: {
        migratePbsTokenSecretBuffer()

        logDebug("Component.onCompleted: Plasmoid initialized")
        resolveSecretIfNeeded()

        if (!hasCoreConfig && connectionMode === "single") {
            logDebug("Component.onCompleted: Missing core config, attempting KWallet key detection")
            controller.listStoredKeys()
            loadDefaults.connectSource("cat ~/.config/proxmox-plasmoid/settings.json 2>/dev/null")
        }
    }


    // DataSource for loading default settings from file
    Plasma5Support.DataSource {
        id: loadDefaults
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            root.logDebug("loadDefaults: Received response")

            if (data["exit code"] === 0 && data["stdout"] && !root.defaultsLoaded) {
                // Same format as Backup/Restore: the validated export envelope.
                // Legacy flat seeds are still understood (tokenSecret in them is
                // never read). Values land on Plasmoid.configuration; the root
                // property bindings and onXChanged handlers propagate from there.
                var res = ConfigPortability.validateImportFile(data["stdout"])
                if (!res.ok)
                    res = ConfigPortability.parseLegacyDefaults(data["stdout"])
                if (res.ok) {
                    var keys = ConfigPortability.whitelistedKeys()
                    for (var i = 0; i < keys.length; i++) {
                        var k = keys[i]
                        if (res.config[k] !== undefined)
                            Plasmoid.configuration[k] = res.config[k]
                    }
                    root.defaultsLoaded = true
                    root.logDebug("loadDefaults: Settings applied from defaults file")
                } else {
                    root.logDebug("loadDefaults: No defaults found or file not recognized")
                }
            }
            disconnectSource(source)
        }
    }

    // DataSource for running local commands (notifications + reading defaults).
    // NOTE: API calls are handled by the native ProxmoxController (QNetworkAccessManager),
    // so we intentionally do NOT fetch Proxmox data via "executable" anymore.
    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            // We only use this datasource for fire-and-forget notify-send and for loadDefaults ("cat ...").
            disconnectSource(source)
        }
    }


    compactRepresentation: CompactRepresentation {
        hasCoreConfig: root.hasCoreConfig
        secretState: root.controller ? root.controller.secretState : "idle"
        configured: root.configured
        loading: root.loading
        isRefreshing: root.isRefreshing
        compactMode: root.compactMode
        runningVMs: root.runningVMs
        runningLXC: root.runningLXC
        displayedVmData: root.displayedVmData
        displayedLxcData: root.displayedLxcData
        lastUpdate: root.lastUpdate
        errorMessage: root.errorMessage
        connectionMode: root.connectionMode
        displayedEndpoints: root.displayedEndpointsModel
        displayedProxmoxData: root.displayedProxmoxData
        safeCpuPercent: root.safeCpuPercent
    }


    fullRepresentation: Item {
        id: fullRep
        Layout.preferredWidth: 420
        Layout.preferredHeight: Math.min(root.calculatedHeight, 500)
        Layout.minimumWidth: 380
        Layout.minimumHeight: 200
        Layout.maximumHeight: 600

        readonly property int headerHeight: 36
        readonly property int footerHeight: 24
        readonly property int horizontalMargin: 10
        readonly property int scrollSideMargin: 6
        readonly property int topMargin: 8
        readonly property int sectionSpacing: 4
        readonly property int bottomMargin: 8

        // Header
        RowLayout {
            id: headerRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: fullRep.horizontalMargin
            anchors.rightMargin: fullRep.horizontalMargin
            anchors.topMargin: fullRep.topMargin
            height: fullRep.headerHeight

            PlasmaComponents.Label {
                text: root.configured
                    ? (root.connectionMode === "multiHost"
                       ? "Proxmox - " + root.displayedEndpoints.length + " hosts"
                       : "Proxmox - " + root.anonymizeHost(root.proxmoxHost))
                    : "Proxmox Monitor"
                font.bold: true
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                text: "🔧"
                visible: root.devMode
                font.pixelSize: 14
            }

            // Copy debug info button (dev mode only)
            PlasmaComponents.Button {
                icon.name: "edit-copy"
                onClicked: root.copyDebugInfo()
                visible: root.devMode
                implicitHeight: 28
                implicitWidth: 28

                PlasmaComponents.ToolTip {
                    text: "Copy debug info (no secrets)"
                }
            }

            // Test notifications button
            PlasmaComponents.Button {
                icon.name: "notifications"
                onClicked: root.testNotifications()
                visible: root.devMode
                implicitHeight: 28
                implicitWidth: 28

                PlasmaComponents.ToolTip {
                    text: "Test notification"
                }
            }

            PlasmaComponents.Button {
                icon.name: "utilities-terminal"
                // Coerced with !! so the pre-first-data evaluation can't yield
                // undefined ("Unable to assign [undefined] to bool" at load).
                visible: !!(Plasmoid.configuration.consoleEnabled !== false
                      && root.connectionMode === "single"
                      && root.configured
                      && root.displayedProxmoxData
                      && root.displayedProxmoxData.data
                      && root.displayedProxmoxData.data.length > 0)
                implicitHeight: 28
                implicitWidth: 28
                onClicked: {
                    var node = root.displayedProxmoxData.data[0].node
                    controller.openConsole("", "node", node, 0, node)
                }
                PlasmaComponents.ToolTip { text: "Open host shell" }
            }

            Item {
                visible: root.configured
                implicitHeight: 28
                implicitWidth: 28
                Layout.preferredHeight: 28
                Layout.preferredWidth: 28

                PlasmaComponents.Button {
                    anchors.fill: parent
                    icon.name: "view-refresh"
                    onClicked: root.fetchData()
                    visible: !root.isRefreshing
                }

                PlasmaComponents.BusyIndicator {
                    anchors.centerIn: parent
                    running: root.isRefreshing
                    visible: root.isRefreshing
                    implicitWidth: 20
                    implicitHeight: 20
                }
            }
        }

        // Not configured / credential loading message
        ColumnLayout {
            anchors.top: statusBanner.bottom
            anchors.bottom: footerRow.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: fullRep.horizontalMargin
            anchors.rightMargin: fullRep.horizontalMargin
            visible: !root.configured
            spacing: 8

            Item { Layout.fillHeight: true }

            Kirigami.Icon {
                source: "configure"
                implicitWidth: 48
                implicitHeight: 48
                Layout.alignment: Qt.AlignHCenter
                opacity: 0.6
            }

            PlasmaComponents.Label {
                text: {
                    if (!root.hasCoreConfig) return "Not Configured"
                    if (controller.secretState === "loading" || controller.refreshResolvingSecrets) return "Loading Credentials…"
                    if (controller.secretState === "missing") return "Missing Token Secret"
                    if (controller.secretState === "error") return "Credentials Error"
                    return "Not Configured"
                }
                font.bold: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            PlasmaComponents.Label {
                text: {
                    if (!root.hasCoreConfig) return "Right-click → Configure Widget"
                    if (controller.secretState === "loading" || controller.refreshResolvingSecrets) return "Reading API token secret from keyring…"
                    if (controller.secretState === "missing") return "Open settings and re-enter the API Token Secret."
                    if (controller.secretState === "error") return "Keyring access failed. Check logs (journalctl --user -f)."
                    return "Right-click → Configure Widget"
                }
                opacity: 0.7
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 320
            }

            Item { Layout.fillHeight: true }
        }

        // Loading indicator (only on initial load)
        Item {
            anchors.top: statusBanner.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: fullRep.horizontalMargin
            anchors.rightMargin: fullRep.horizontalMargin
            height: root.loading ? 50 : 0
            visible: root.loading

            PlasmaComponents.BusyIndicator {
                anchors.centerIn: parent
                running: root.loading
            }
        }

        StatusBanner {
            id: statusBanner
            anchors.top: headerRow.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: fullRep.horizontalMargin
            anchors.rightMargin: fullRep.horizontalMargin
            anchors.topMargin: fullRep.sectionSpacing
            configured: root.configured
            hasCoreConfig: root.hasCoreConfig
            secretState: root.controller ? root.controller.secretState : "idle"
            refreshResolvingSecrets: root.controller ? root.controller.refreshResolvingSecrets : false
            loading: root.loading
            errorMessage: root.errorMessage
            partialFailure: root.controller ? root.controller.partialFailure : false
            retryStatusText: root.retryStatusText
            armedLabel: root.armedLabel
            actionPermHintShown: root.actionPermHintShown
            actionPermHint: root.actionPermHint
            pbsError: root.pbsError
            onRetry: function() { root.fetchData() }
        }

        // Scrollable Main Content
        Item {
            anchors.top: statusBanner.bottom
            anchors.bottom: footerRow.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: fullRep.sectionSpacing
            anchors.bottomMargin: fullRep.sectionSpacing
            anchors.leftMargin: fullRep.scrollSideMargin
            anchors.rightMargin: fullRep.scrollSideMargin
            visible: root.configured && !root.loading && root.errorMessage === ""

            QQC2.ScrollView {
                id: scrollView
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                clip: true

                QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
                QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AlwaysOff

                readonly property int __scrollbarGap: 0
                readonly property int __scrollbarReserve: 10

                ColumnLayout {
                    id: mainContentColumn
                    width: scrollView.availableWidth
                    spacing: 8

                Repeater {
                    visible: root.connectionMode === "single"
                    // Diffing model: rows update in place via dataChanged, so
                    // these delegates persist across refreshes instead of
                    // being rebuilt every poll.
                    model: controller.nodesModel

                    delegate: NodeSection {
                        required property int index
                        required property var itemData

                        nodeIndex: index
                        nodeModel: itemData
                        vmsModel: itemData ? itemData.vmsModel : null
                        lxcsModel: itemData ? itemData.lxcsModel : null
                        isCollapsed: root.isNodeCollapsed(itemData ? itemData.node : "")
                        uiRadiusS: root.uiRadiusS
                        uiRadiusL: root.uiRadiusL
                        uiBorderOpacity: root.uiBorderOpacity
                        uiSurfaceAltOpacity: root.uiSurfaceAltOpacity
                        uiSurfaceRunningOpacity: root.uiSurfaceRunningOpacity
                        uiNodeCardOpacity: root.uiNodeCardOpacity
                        uiWindowOpacity: root.uiWindowOpacity
                        uiNodeColor: root.uiNodeColor
                        uiRunningColor: root.uiRunningColor
                        uiStoppedColor: root.uiStoppedColor
                        uiRowHeight: root.uiRowHeight
                        scrollbarReserve: scrollView.__scrollbarReserve
                        safeCpuPercent: root.safeCpuPercent
                        anonymizeNodeName: root.anonymizeNodeName
                        anonymizeVmId: root.anonymizeVmId
                        anonymizeVmName: root.anonymizeVmName
                        anonymizeLxcName: root.anonymizeLxcName
                        anonymizeIp: root.anonymizeIp
                        isActionBusy: root.isActionBusy
                        armedActionKey: root.armedActionKey
                        armedTimerRunning: armedTimer.running
                        onToggleCollapsed: function(nodeName) { root.toggleNodeCollapsed(nodeName) }
                        onAction: function(kind, nodeName, vmid, displayName, action) {
                            root.confirmAndRunAction(kind, nodeName, vmid, displayName, action)
                        }
                        onConsole: function(kind, nodeName, vmid, displayName) {
                            controller.openConsole("", kind, nodeName, vmid, displayName)
                        }
                        onStatsToggled: function(kind, nodeName, vmid) {
                            root.requestStats(kind, nodeName, vmid)
                        }
                        getStatsData: root.getStatsData
                        isStatsLoading: root.isStatsLoading
                        statsEnabled: Plasmoid.configuration.powerActionsEnabled !== false
                        consoleEnabled: Plasmoid.configuration.consoleEnabled !== false
                        powerActionsEnabled: Plasmoid.configuration.powerActionsEnabled !== false
                    }
                }

                // Multi-host view (group by endpoint)
                Repeater {
                    visible: root.connectionMode === "multiHost"
                    // Diffing model: endpoint rows update in place, delegates
                    // persist across refreshes (same as the single-host path).
                    model: controller.endpointsModel

                    Component.onCompleted: {
                        root.logDebug("[ProxMon UI] multi repeater visible=" + visible
                                 + " mode=" + root.connectionMode
                                 + " modelLen=" + controller.endpointsModel.count)
                    }

                    delegate: MultiHostEndpointSection {
                        required property int index
                        required property var itemData
                        endpoint: itemData
                        nodesModel: itemData ? itemData.nodesModel : null
                        endpointIndex: index
                        anonymized: root.devMode
                        uiRadiusL: root.uiRadiusL
                        uiBorderOpacity: root.uiBorderOpacity
                        uiMutedTextOpacity: root.uiMutedTextOpacity
                        uiNodeCardOpacity: root.uiNodeCardOpacity
                        uiWindowOpacity: root.uiWindowOpacity
                        uiNodeColor: root.uiNodeColor
                        uiSurfaceAltOpacity: root.uiSurfaceAltOpacity
                        uiSurfaceRunningOpacity: root.uiSurfaceRunningOpacity
                        uiRunningColor: root.uiRunningColor
                        uiStoppedColor: root.uiStoppedColor
                        scrollbarReserve: scrollView.__scrollbarReserve
                        safeCpuPercent: root.safeCpuPercent
                        anonymizeNodeName: root.anonymizeNodeName
                        anonymizeVmId: root.anonymizeVmId
                        anonymizeVmName: root.anonymizeVmName
                        anonymizeLxcName: root.anonymizeLxcName
                        isNodeCollapsed: root.isNodeCollapsed
                        isActionBusy: root.isActionBusy
                        armedActionKey: root.armedActionKey
                        armedTimerRunning: armedTimer.running
                        armedActionSessionKey: root.armedActionKey.indexOf("::") !== -1 ? root.armedActionKey.split("::")[0] : ""
                        onToggleCollapsed: function(nodeName, sessionKey) {
                            root.toggleNodeCollapsed(nodeName, sessionKey)
                        }
                        onConsole: function(sessionKey, kind, nodeName, vmid, displayName) {
                            controller.openConsole(sessionKey, kind, nodeName, vmid, displayName)
                        }
                        onAction: function(sessionKey, kind, nodeName, vmid, displayName, action) {
                            root.confirmAndRunActionForSession(sessionKey, kind, nodeName, vmid, displayName, action)
                        }
                        consoleEnabled: Plasmoid.configuration.consoleEnabled !== false
                        powerActionsEnabled: Plasmoid.configuration.powerActionsEnabled !== false
                    }
                }

                // Empty state
                PlasmaComponents.Label {
                    text: "No nodes found"
                    visible: (root.connectionMode === "single")
                        ? (!root.displayedProxmoxData || !root.displayedProxmoxData.data || root.displayedProxmoxData.data.length === 0)
                        : (controller.endpointsModel.count === 0)
                    opacity: 0.6
                    Layout.alignment: Qt.AlignHCenter
                }

                // Bottom padding
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 4
                }
                }
            }
        }

        // Footer, keep it pinned to the bottom of the panel
        RowLayout {
            id: footerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: fullRep.horizontalMargin
            anchors.rightMargin: fullRep.horizontalMargin
            anchors.bottomMargin: fullRep.bottomMargin
            height: fullRep.footerHeight
            visible: root.configured

            MouseArea {
                Layout.fillWidth: true
                Layout.fillHeight: true
                onClicked: root.handleFooterClick()

                RowLayout {
                    anchors.fill: parent
                    spacing: 4

                    Kirigami.Icon {
                        source: "server-database"
                        implicitWidth: 12
                        implicitHeight: 12
                        opacity: 0.6
                    }

                    PlasmaComponents.Label {
                        text: root.displayedNodeList.length + (root.displayedNodeList.length === 1 ? " node" : " nodes")
                        font.pixelSize: 10
                        opacity: 0.6
                    }

                    Item { implicitWidth: 8 }

                    Kirigami.Icon {
                        source: "computer-symbolic"
                        implicitWidth: 12
                        implicitHeight: 12
                        opacity: 0.6
                    }

                    PlasmaComponents.Label {
                        text: root.runningVMs + "/" + root.displayedVmData.length
                        font.pixelSize: 10
                        opacity: 0.6
                    }

                    Item { implicitWidth: 8 }

                    Kirigami.Icon {
                        source: "lxc"
                        implicitWidth: 12
                        implicitHeight: 12
                        opacity: 0.6
                    }

                    PlasmaComponents.Label {
                        text: root.runningLXC + "/" + root.displayedLxcData.length
                        font.pixelSize: 10
                        opacity: 0.6
                    }

                    Item { Layout.fillWidth: true }

                    PlasmaComponents.Label {
                        text: root.lastUpdate ? "Updated: " + root.lastUpdate : ""
                        font.pixelSize: 10
                        opacity: 0.6
                    }
                }
            }
        }
    }


    Timer {
        interval: root.refreshInterval > 0 ? root.refreshInterval : 30000
        running: root.configured
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetchData()
    }
}
