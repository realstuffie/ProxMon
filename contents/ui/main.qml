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
import "../lib/proxmox" as ProxMon

PlasmoidItem {
    id: root

    // Toggle expanded state when the applet is activated (e.g. keyboard shortcut).
    // The compactRepresentation also has a MouseArea for direct clicks.
    activationTogglesExpanded: true

    // Panel icon tooltip — updated whenever data changes.
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

    // ==================== CONNECTION / MODE ====================

    // Connection mode: "single" | "multiHost"
    property string connectionMode: Plasmoid.configuration.connectionMode || "single"

    // Single-host connection properties
    property string proxmoxHost: Plasmoid.configuration.proxmoxHost || ""
    property int proxmoxPort: Plasmoid.configuration.proxmoxPort || 8006
    property string apiTokenId: Plasmoid.configuration.apiTokenId || ""
    // apiTokenSecret stays bound to Plasmoid.configuration so onApiTokenSecretChanged
    // keeps firing whenever the user saves a new secret via the KCM.
    property string apiTokenSecret: Plasmoid.configuration.apiTokenSecret || ""
    // Multi-host config (KCM stores these)
    property string multiHostsJson: Plasmoid.configuration.multiHostsJson || "[]"
    // Plaintext stash from KCM; runtime migrates to keyring and clears it.
    property string multiHostSecretsJson: Plasmoid.configuration.multiHostSecretsJson || "{}"

    ProxMon.ProxmoxController {
        id: controller
        connectionMode: root.connectionMode
        host: root.proxmoxHost
        port: root.proxmoxPort
        tokenId: root.apiTokenId
        apiTokenSecret: root.apiTokenSecret
        multiHostsJson: root.multiHostsJson
        multiHostSecretsJson: root.multiHostSecretsJson
        ignoreSsl: root.ignoreSsl
        autoRetry: root.autoRetry
        retryStartMs: root.retryStartMs
        retryMaxMs: root.retryMaxMs
        onApiTokenSecretClearRequested: {
            Plasmoid.configuration.apiTokenSecret = ""
        }
        onMultiHostSecretsJsonChangedExternally: function(value) {
            Plasmoid.configuration.multiHostSecretsJson = value
            root.multiHostSecretsJson = value
        }
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
            if (controller.secretState === "ready" && root.configured && !root.loading && !root.isRefreshing) {
                root.fetchData()
            }
        }
    }

    property int refreshInterval: (Plasmoid.configuration.refreshInterval || 30) * 1000
    property bool ignoreSsl: Plasmoid.configuration.ignoreSsl !== false
    property string defaultSorting: Plasmoid.configuration.defaultSorting || "status"

    // Auto-retry/backoff
    property bool autoRetry: Plasmoid.configuration.autoRetry !== false
    property int retryStartMs: Math.max(1000, (Plasmoid.configuration.retryStartSeconds || 5) * 1000)
    property int retryMaxMs: Math.max(retryStartMs, (Plasmoid.configuration.retryMaxSeconds || 300) * 1000)
    property int retryAttempt: controller ? controller.retryAttempt : 0
    property int retryNextDelayMs: controller ? controller.retryNextDelayMs : 0
    property string retryStatusText: controller ? controller.retryStatusText : ""

    // Notification properties
    property bool enableNotifications: Plasmoid.configuration.enableNotifications !== false
    property string notifyMode: Plasmoid.configuration.notifyMode || "all"
    property string notifyFilter: Plasmoid.configuration.notifyFilter || ""
    property bool notifyOnStop: Plasmoid.configuration.notifyOnStop !== false
    property bool notifyOnStart: Plasmoid.configuration.notifyOnStart !== false
    property bool notifyOnNodeChange: Plasmoid.configuration.notifyOnNodeChange !== false

    // Notification privacy: redact user@realm and token IDs when present in notification text.
    property bool redactNotifyIdentities: Plasmoid.configuration.redactNotifyIdentities !== false

    // Notification rate limiting (seconds)
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
        console.log("[ProxMon UI] mode=", connectionMode,
                    "configured=", configured,
                    "loading=", loading,
                    "error=", errorMessage,
                    "endpointsModel=", displayedEndpointsModel ? displayedEndpointsModel.length : -1)
    }
    property var displayedNodeList: controller.displayedNodeList
    property bool loading: controller ? controller.loading : false
    property bool isRefreshing: controller ? controller.isRefreshing : false
    property string errorMessage: controller ? controller.errorMessage : ""
    property string lastUpdate: controller ? controller.lastUpdate : ""

    // One-time hint to guide users when action permissions are missing
    property bool actionPermHintShown: false
    property string actionPermHint: ""

    // Debug log (capped to debugLogMaxLines entries)
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

    // "configured" means we have at least one usable endpoint and secrets resolved.
    // During refresh-time secret re-resolution, keep the widget in configured state
    // so it does not flash the not-configured UI between refreshes.
    property bool configured: {
        if (connectionMode === "multiHost") {
            if (controller.secretState === "ready" && controller.endpoints && controller.endpoints.length > 0) return true
            return controller.refreshResolvingSecrets && displayedEndpoints && displayedEndpoints.length > 0
        }
        if (hasCoreConfig && controller.secretState === "ready") return true
        return hasCoreConfig && controller.refreshResolvingSecrets
    }
    property bool defaultsLoaded: false
    property bool devMode: true
    property int footerClickCount: 0

    // Per-item action busy map: key "node:kind:vmid" => true
    property var actionBusy: ({})

    // Two-click confirmation state (works in plasmoids where popups/dialogs may not render reliably)
    // If the same action is clicked again while the timer is running, it executes.
    property string armedActionKey: ""
    property string armedLabel: ""

    Timer {
        id: armedTimer
        interval: 5000
        repeat: false
        onTriggered: {
            armedActionKey = ""
            armedLabel = ""
        }
    }

    // Avoid QQC2 Popup/Dialog in plasmoids (overlay may not exist); use two-click confirm.

    // Multi-node support

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

    // Footer click sequence timer (dev mode toggle)
    Timer {
        id: footerClickTimer
        interval: 1000
        onTriggered: footerClickCount = 0
    }

    // ==================== VISUAL TOKENS ====================
    // Keep platform colors from Kirigami, but standardize shape/opacity rhythm
    // for a flatter, Adwaita-leaning look.
    readonly property int uiRadiusS: 4
    readonly property int uiRadiusM: 6
    readonly property int uiRadiusL: 8
    readonly property real uiBorderOpacity: 0.22
    readonly property color uiRunningColor: Plasmoid.configuration.appearanceRunningColor || Kirigami.Theme.positiveTextColor
    readonly property color uiStoppedColor: Plasmoid.configuration.appearanceStoppedColor || Kirigami.Theme.disabledTextColor
    readonly property real uiCardTintOpacity: Math.max(0, Math.min((Plasmoid.configuration.appearanceCardTintOpacity !== undefined ? Plasmoid.configuration.appearanceCardTintOpacity : 10) / 100, 0.40))
    readonly property real uiWindowOpacity: Math.max(0.60, Math.min((Plasmoid.configuration.appearanceWindowOpacity !== undefined ? Plasmoid.configuration.appearanceWindowOpacity : 100) / 100, 1.0))
    readonly property real uiSurfaceAltOpacity: uiCardTintOpacity > 0 ? uiCardTintOpacity : 0.10
    readonly property real uiSurfaceRunningOpacity: uiCardTintOpacity > 0 ? Math.min(uiCardTintOpacity + 0.02, 0.40) : 0.12
    readonly property real uiNodeCardOpacity: 0.98
    readonly property real uiMutedTextOpacity: 0.68
    readonly property int uiRowHeight: 30

    // ==================== UTILITY FUNCTIONS ====================

    // Shell-escape for executable datasource usage
    function escapeShell(str) {
            if (!str) return ""
            return str.replace(/'/g, "'\\''")
        }

    // Clamp/sanitize CPU values coming from Proxmox.
    // On some restarts the initial cpu field can be garbage (e.g. negative), which then renders as -4000%.
    function safeCpuPercent(cpuFraction) {
        var x = Number(cpuFraction)
        if (!isFinite(x) || isNaN(x)) return 0
        // Proxmox reports CPU as fraction (0..1 typically, can exceed 1 on some metrics).
        // Clamp to a sane range for UI.
        x = Math.max(0, Math.min(x, 1))
        return x * 100
    }
 
        ProxMon.ProxmoxClient {
        id: api
        // Single-host properties for legacy calls + actions.
        // For multi-host fetching we use requestNodesFor/requestQemuFor/requestLxcFor.
        host: proxmoxHost
        port: proxmoxPort
        tokenId: apiTokenId
        tokenSecret: ""
        ignoreSslErrors: ignoreSsl
        lowLatency: Plasmoid.configuration.lowLatency !== false


    }


    // Redact sensitive identity fragments in debug logs / copied debug output.
    // Matches "user@realm" and "!tokenid" style segments.
    property string secretRedactRegex: "([A-Za-z0-9._-]+)@([A-Za-z0-9._-]+)|!([A-Za-z0-9._:-]+)"

    function redactSecretsForDebug(str) {
        str = String(str || "")
        return str.replace(new RegExp(secretRedactRegex, "g"), function(match, user, realm, tokenId) {
            if (user && realm) return "REDACTED@" + realm
            if (tokenId) return "!REDACTED"
            return match
        })
    }

    // Debug logging is gated behind developer mode to avoid flooding the user journal.
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
        console.log(line)

        var newLog = debugLog.slice()
        newLog.push(line)
        if (newLog.length > debugLogMaxLines) newLog.splice(0, newLog.length - debugLogMaxLines)
        debugLog = newLog
    }

    function buildDebugInfo() {
        var info = {
            version: (Plasmoid.metaData && Plasmoid.metaData.version) ? Plasmoid.metaData.version : "",
            host: proxmoxHost,
            port: proxmoxPort,
            tokenId: apiTokenId,
            ignoreSsl: ignoreSsl,
            refreshIntervalSeconds: Math.round(refreshInterval / 1000),
            autoRetry: autoRetry,
            retryStartSeconds: Math.round(retryStartMs / 1000),
            retryMaxSeconds: Math.round(retryMaxMs / 1000),
            lastUpdate: lastUpdate,
            errorMessage: errorMessage,
            nodeCount: displayedNodeList.length,
            vmCount: displayedVmData.length,
            lxcCount: displayedLxcData.length,
            log: debugLog
        }
        return JSON.stringify(info, null, 2)
    }

    function copyDebugInfo() {
        // Pull plasmashell logs, keep only ProxMon lines, limit copied output.
        var linesToCopy = 100
        var sinceWindow = "30 min ago"
        var primaryScanLines = 1000
        var fallbackScanLines = 2000
        var filterRegex = "proxmox|proxmon"
        var cmdParts = [
            "sh -lc 'set -e;",
            "if command -v journalctl >/dev/null 2>&1; then",
            "LOGS=$(journalctl --user --unit=plasma-plasmashell.service --since \"" + sinceWindow + "\" -n " + primaryScanLines + " --no-pager 2>/dev/null | grep -Ei \"" + filterRegex + "\" | tail -n " + linesToCopy + " || true);",
            "if [ -z \"$LOGS\" ]; then",
            "LOGS=$(journalctl --user --since \"" + sinceWindow + "\" -n " + fallbackScanLines + " --no-pager 2>/dev/null | grep \"plasmashell\" | grep -Ei \"" + filterRegex + "\" | tail -n " + linesToCopy + " || true);",
            "fi;",
            "if command -v wl-copy >/dev/null 2>&1; then printf %s \"$LOGS\" | wl-copy;",
            "elif command -v xclip >/dev/null 2>&1; then printf %s \"$LOGS\" | xclip -selection clipboard;",
            "else exit 1; fi;",
            "else exit 1; fi'"
        ]

        var cmd = cmdParts.join(" ")
        executable.connectSource(cmd)
        sendNotification("Debug logs copied")
    }

    // ==================== NOTIFICATION FUNCTIONS ====================

    // Escape regex special chars except "*" (wildcard)
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
            // Exact match on name or vmid
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

    // Send desktop notification
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
        // This can appear in UPIDs (tasks) and logs.
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

    // Test notifications function (dev mode)
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

                // Record initial node states per endpoint/session.
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

            // Check nodes for state changes per endpoint/session.
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

    // ==================== NODE DATA FUNCTIONS ====================

    // Get VMs for a specific node (use displayed data)
    function getVmsForNode(nodeName) {
        var nodeVms = displayedVmData.filter(function(vm) {
            return vm.node === nodeName
        })
        return sortByStatus(nodeVms)
    }

    function getVmsForNodeMulti(sessionKey, nodeName) {
        var arr = []
        for (var i = 0; i < displayedEndpoints.length; i++) {
            var b = displayedEndpoints[i]
            if (!b || b.sessionKey !== sessionKey) continue
            arr = b.vms.filter(function(vm) {
                return vm.node === nodeName
            })
            break
        }
        return sortByStatus(arr)
    }

    // Get LXCs for a specific node (use displayed data)
    function getLxcForNode(nodeName) {
        var nodeLxc = displayedLxcData.filter(function(lxc) {
            return lxc.node === nodeName
        })
        return sortByStatus(nodeLxc)
    }

    function getLxcForNodeMulti(sessionKey, nodeName) {
        var arr2 = []
        for (var i2 = 0; i2 < displayedEndpoints.length; i2++) {
            var b2 = displayedEndpoints[i2]
            if (!b2 || b2.sessionKey !== sessionKey) continue
            arr2 = b2.lxcs.filter(function(lxc) {
                return lxc.node === nodeName
            })
            break
        }
        return sortByStatus(arr2)
    }

    // Get running VM count for a node (use displayed data)
    function getRunningVmsForNode(nodeName) {
        var count = 0
        for (var i = 0; i < displayedVmData.length; i++) {
            if (displayedVmData[i].node === nodeName && displayedVmData[i].status === "running") count++
        }
        return count
    }

    function getRunningVmsForNodeMulti(sessionKey, nodeName) {
        var vms = getVmsForNodeMulti(sessionKey, nodeName)
        var c = 0
        for (var i = 0; i < vms.length; i++) {
            if (vms[i].status === "running") c++
        }
        return c
    }

    // Get running LXC count for a node (use displayed data)
    function getRunningLxcForNode(nodeName) {
        var count = 0
        for (var i = 0; i < displayedLxcData.length; i++) {
            if (displayedLxcData[i].node === nodeName && displayedLxcData[i].status === "running") count++
        }
        return count
    }

    function getRunningLxcForNodeMulti(sessionKey, nodeName) {
        var lxcs = getLxcForNodeMulti(sessionKey, nodeName)
        var c2 = 0
        for (var i2 = 0; i2 < lxcs.length; i2++) {
            if (lxcs[i2].status === "running") c2++
        }
        return c2
    }

    // Get total VM count for a node (use displayed data)
    function getTotalVmsForNode(nodeName) {
        var count = 0
        for (var i = 0; i < displayedVmData.length; i++) {
            if (displayedVmData[i].node === nodeName) count++
        }
        return count
    }

    function getTotalVmsForNodeMulti(sessionKey, nodeName) {
        return getVmsForNodeMulti(sessionKey, nodeName).length
    }

    // Get total LXC count for a node (use displayed data)
    function getTotalLxcForNode(nodeName) {
        var count = 0
        for (var i = 0; i < displayedLxcData.length; i++) {
            if (displayedLxcData[i].node === nodeName) count++
        }
        return count
    }

    function getTotalLxcForNodeMulti(sessionKey, nodeName) {
        return getLxcForNodeMulti(sessionKey, nodeName).length
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
        // Plasma sometimes doesn't show QQC2.Popup/Overlay in plasmoids (no window overlay layer).
        // Use a safe "two-step confirmation" instead:
        //  - First click arms the action for a short time and changes the icon to "dialog-ok"
        //  - Second click within the window executes the action
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

    // Backwards-compatible helper (no longer used by action flow, but kept to avoid dangling references)
    function runPendingAction() {
        if (!pendingAction) return
        var a = pendingAction
        pendingAction = null
        setActionBusy(a.node, a.kind, a.vmid, true)
        api.requestAction(a.kind, a.node, a.vmid, a.action, ++actionSeq)
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

    // ==================== ANONYMIZATION FUNCTIONS ====================

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

    // ==================== UI HELPER FUNCTIONS ====================

    function handleFooterClick() {
        footerClickCount++
        if (footerClickCount >= 3) {
            devMode = !devMode
            footerClickCount = 0
            logDebug("Developer mode: ENABLED")
        }
        footerClickTimer.restart()
    }

    function sortByStatus(data) {
        if (!data || data.length === 0) return []

        function nameOf(x) {
            return (x && (x.name || x.hostname) ? String(x.name || x.hostname) : "")
        }

        return data.slice().sort(function(a, b) {
            var an = nameOf(a)
            var bn = nameOf(b)

            switch (defaultSorting) {
                case "status":
                    var aRunning = (a.status === "running") ? 0 : 1
                    var bRunning = (b.status === "running") ? 0 : 1
                    if (aRunning !== bRunning) return aRunning - bRunning
                    // secondary sort: name, then vmid for stability
                    var nc = an.localeCompare(bn)
                    if (nc !== 0) return nc
                    return (a.vmid || 0) - (b.vmid || 0)

                case "name":
                    var c1 = an.localeCompare(bn)
                    if (c1 !== 0) return c1
                    return (a.vmid || 0) - (b.vmid || 0)

                case "nameDesc":
                    var c2 = bn.localeCompare(an)
                    if (c2 !== 0) return c2
                    return (a.vmid || 0) - (b.vmid || 0)

                case "id":
                    return (a.vmid || 0) - (b.vmid || 0)

                case "idDesc":
                    return (b.vmid || 0) - (a.vmid || 0)

                default:
                    var aRun = (a.status === "running") ? 0 : 1
                    var bRun = (b.status === "running") ? 0 : 1
                    if (aRun !== bRun) return aRun - bRun
                    var c3 = an.localeCompare(bn)
                    if (c3 !== 0) return c3
                    return (a.vmid || 0) - (b.vmid || 0)
            }
        })
    }

    // Get node name from API URL
    function getNodeFromSource(source) {
        var match = source.match(/\/nodes\/([^\/]+)\//)
        return match ? match[1] : ""
    }

        // Atomically swap displayed data when all requests finish

    // ==================== API FUNCTIONS ====================

    // Sequencing for actions
    property int actionSeq: 0

    // Confirmation prompt state
    property var pendingAction: null

    // Confirm is two-click (see confirmAndRunAction()); QQC2.Popup overlays are unreliable in plasmoids.

    Timer {
        id: refreshWatchdog
        interval: 15000
        repeat: false
        onTriggered: {
            if (pendingNodeRequests > 0) {
                logDebug("refreshWatchdog: Timed out with " + pendingNodeRequests + " pending")
                api.cancelAll()
                pendingNodeRequests = 0

                if (tempVmData.length > 0 || tempLxcData.length > 0) {
                    errorMessage = "Partial data (some nodes timed out)"
                    checkRequestsComplete()
                } else {
                    errorMessage = "Request timed out"
                    isRefreshing = false
                    loading = false
                    scheduleRetry("Request timed out")
                }
            }
        }
    }


    Timer {
        id: secretResolveDebounce
        interval: 150
        repeat: false
        onTriggered: {
            logDebug("secretResolveDebounce: resolving secrets after config change")
            resolveSecretIfNeeded()
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
            logDebug("configRefreshDebounce: triggering refresh after config change")
            fetchData()
        }
    }

    function triggerRefreshFromConfigChange(reason) {
        logDebug("config change: " + (reason || "unknown"))
        // Cancel in-flight requests and retry timers so we restart cleanly.
        api.cancelAll()
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
        controller.fetchData()
    }

    function fetchVMs(nodeName) {
        if (!nodeName) return
        logDebug("fetchVMs: Requesting VMs for node: " + nodeName)
        api.requestQemu(nodeName, refreshSeq)
    }

    function fetchLXC(nodeName) {
        if (!nodeName) return
        logDebug("fetchLXC: Requesting LXCs for node: " + nodeName)
        api.requestLxc(nodeName, refreshSeq)
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

    // ==================== INITIALIZATION ====================

    function endpointNodeKey(sessionKey, nodeName) {
        return String(sessionKey) + "::" + String(nodeName || "")
    }

    // ---------- Multi-host: fetching / aggregation ----------

    property var tempEndpointsData: ({})

    function resetMultiTempData() {
        tempEndpointsData = ({})
        for (var i = 0; i < controller.endpoints.length; i++) {
            var ep = controller.endpoints[i]
            if (!ep) continue
            ensureEndpointBucket(ep.sessionKey)
        }
    }

    function isEndpointTimeout(message) {
        var m = String(message || "").toLowerCase()
        return m.indexOf("timed out") !== -1 || m.indexOf("timeout") !== -1
    }

    function ensureEndpointBucket(sessionKey) {
        var b = tempEndpointsData[sessionKey]
        if (b) return b
        // find meta
        var meta = null
        for (var i = 0; i < controller.endpoints.length; i++) {
            if (controller.endpoints[i].sessionKey === sessionKey) {
                meta = controller.endpoints[i]
                break
            }
        }
        b = {
            sessionKey: sessionKey,
            label: meta ? meta.label : "",
            host: meta ? meta.host : "",
            port: meta ? meta.port : 8006,
            error: "",
            offline: false,
            nodes: [],
            vms: [],
            lxcs: []
        }
        var newMap = Object.assign({}, tempEndpointsData)
        newMap[sessionKey] = b
        tempEndpointsData = newMap
        return b
    }

    function bucketsToArray(map) {
        var arr = []
        for (var i = 0; i < controller.endpoints.length; i++) {
            var ep = controller.endpoints[i]
            if (!ep) continue
            var bucket = map[ep.sessionKey] || {}
            arr.push({
                sessionKey: ep.sessionKey,
                label: ep.label,
                host: ep.host,
                port: ep.port,
                tokenId: ep.tokenId,
                secret: ep.secret,
                ignoreSsl: ep.ignoreSsl,
                error: bucket.error || "",
                offline: !!bucket.offline,
                nodes: bucket.nodes || [],
                vms: bucket.vms || [],
                lxcs: bucket.lxcs || []
            })
        }
        arr.sort(function(a, b) {
            var la = (a.label || a.host || a.sessionKey || "")
            var lb = (b.label || b.host || b.sessionKey || "")
            return String(la).localeCompare(String(lb))
        })
        return arr
    }

    function handleMultiReply(sessionKey, kind, node, data) {
        if (!sessionKey) return
        if (kind === "nodes") {
            var bucket = ensureEndpointBucket(sessionKey)
            var list = (data && data.data) ? data.data.slice() : []
            bucket.offline = false
            bucket.error = ""
            // annotate nodes with sessionKey for uniqueness/collapsing
            for (var i = 0; i < list.length; i++) {
                list[i].sessionKey = sessionKey
            }
            bucket.nodes = list

            // Schedule per-node QEMU/LXC
            var nodeNames = list.map(function(n) { return n.node })
            pendingNodeRequests += nodeNames.length * 2
            for (var ni = 0; ni < nodeNames.length; ni++) {
                var ep = endpointBySession(sessionKey)
                if (!ep) continue
                api.requestQemuFor(sessionKey, ep.host, ep.port, ep.tokenId, ep.secret, ep.ignoreSsl, nodeNames[ni], refreshSeq)
                api.requestLxcFor(sessionKey, ep.host, ep.port, ep.tokenId, ep.secret, ep.ignoreSsl, nodeNames[ni], refreshSeq)
            }

            // nodes call itself counts as one pending completion
            pendingNodeRequests--
            checkMultiRequestsComplete()
            return
        }

        if (kind === "qemu" || kind === "lxc") {
            var bucket2 = ensureEndpointBucket(sessionKey)
            var items = (data && data.data) ? data.data : []
            for (var j = 0; j < items.length; j++) {
                var it = items[j]
                it.node = node
                it.sessionKey = sessionKey
                if (kind === "qemu") bucket2.vms.push(it)
                else bucket2.lxcs.push(it)
            }
            pendingNodeRequests--
            checkMultiRequestsComplete()
        }
    }

    function handleMultiError(sessionKey, kind, node, message) {
        logDebug("api error (multi): " + sessionKey + " " + kind + " " + node + " - " + message)
        errorMessage = message || "Connection failed"

        var bucket = ensureEndpointBucket(sessionKey)
        if (bucket && kind === "nodes") {
            bucket.error = message || "Connection failed"
            bucket.offline = isEndpointTimeout(message)
            if (bucket.offline) {
                bucket.nodes = []
                bucket.vms = []
                bucket.lxcs = []
            }
        }

        // Decrement pending count for this individual request and continue.
        // If this is the last outstanding request, checkMultiRequestsComplete() will
        // commit whatever partial data we have from the successful controller.endpoints.
        pendingNodeRequests--
        if (pendingNodeRequests < 0) pendingNodeRequests = 0
        checkMultiRequestsComplete()
    }

    function endpointBySession(sessionKey) {
        for (var i = 0; i < controller.endpoints.length; i++) {
            if (controller.endpoints[i].sessionKey === sessionKey) return controller.endpoints[i]
        }
        return null
    }

    function checkMultiRequestsComplete() {
        if (pendingNodeRequests > 0) return
        refreshWatchdog.stop()
        checkStateChanges()
    }

    Connections {
        target: controller
        function onDisplayedEndpointsChanged() {
            if (connectionMode !== "multiHost") return
            checkStateChanges()
        }
    }

    function resolveSecretIfNeeded() {
        controller.resolveSecretsIfNeeded()
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

    // If the secret is entered via the config UI (legacy plaintext field), it updates
    // Plasmoid.configuration.apiTokenSecret but may not change apiTokenId/host/port.
    // React to it so the widget transitions out of "Not Configured" immediately.
    onApiTokenSecretChanged: {
        if (connectionMode === "single") triggerSecretResolveFromConfigChange()
        triggerRefreshFromConfigChange("apiTokenSecret")
    }
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
    onDefaultSortingChanged: triggerRefreshFromConfigChange("defaultSorting")
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
        logDebug("Component.onCompleted: Plasmoid initialized")
        resolveSecretIfNeeded()

        if (!hasCoreConfig && connectionMode === "single") {
            logDebug("Component.onCompleted: Missing core config, attempting KWallet key detection")
            controller.listStoredKeys()
            loadDefaults.connectSource("cat ~/.config/proxmox-plasmoid/settings.json 2>/dev/null")
        }
    }

    // ==================== DATA SOURCES ====================

    // DataSource for loading default settings from file
    Plasma5Support.DataSource {
        id: loadDefaults
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            logDebug("loadDefaults: Received response")

            if (data["exit code"] === 0 && data["stdout"] && !defaultsLoaded) {
                try {
                    var s = JSON.parse(data["stdout"])
                    logDebug("loadDefaults: Parsed settings file")

                    if (s.host) Plasmoid.configuration.proxmoxHost = s.host
                    if (s.port) Plasmoid.configuration.proxmoxPort = s.port
                    if (s.tokenId) Plasmoid.configuration.apiTokenId = s.tokenId
                    if (s.refreshInterval) Plasmoid.configuration.refreshInterval = s.refreshInterval
                    if (s.ignoreSsl !== undefined) Plasmoid.configuration.ignoreSsl = s.ignoreSsl
                    if (s.enableNotifications !== undefined) Plasmoid.configuration.enableNotifications = s.enableNotifications

                    proxmoxHost = s.host || ""
                    proxmoxPort = s.port || 8006
                    apiTokenId = s.tokenId || ""
                    refreshInterval = (s.refreshInterval || 30) * 1000
                    ignoreSsl = s.ignoreSsl !== false
                    enableNotifications = s.enableNotifications !== false
                    defaultsLoaded = true
                    logDebug("loadDefaults: Settings applied - host: " + proxmoxHost)
                } catch (e) {
                    logDebug("loadDefaults: No defaults found or parse error - " + e)
                }
            }
            disconnectSource(source)
        }
    }

    // DataSource for running local commands (notifications + reading defaults).
    // NOTE: API calls are handled by the native ProxMon.ProxmoxClient (QNetworkAccessManager),
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

    // ==================== COMPACT REPRESENTATION ====================

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
        onToggleExpanded: function() { root.expanded = !root.expanded }
    }

    // ==================== FULL REPRESENTATION ====================

    fullRepresentation: Item {
        id: fullRep
        Layout.preferredWidth: 380
        Layout.preferredHeight: Math.min(calculatedHeight, 500)
        Layout.minimumWidth: 350
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
                text: configured
                    ? (connectionMode === "multiHost"
                       ? "Proxmox - " + displayedEndpoints.length + " hosts"
                       : "Proxmox - " + anonymizeHost(proxmoxHost))
                    : "Proxmox Monitor"
                font.bold: true
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                text: "🔧"
                visible: devMode
                font.pixelSize: 14
            }

            // Copy debug info button (dev mode only)
            PlasmaComponents.Button {
                icon.name: "edit-copy"
                onClicked: copyDebugInfo()
                visible: devMode
                implicitHeight: 28
                implicitWidth: 28

                PlasmaComponents.ToolTip {
                    text: "Copy debug info (no secrets)"
                }
            }

            // Test notifications button (dev mode only)
            PlasmaComponents.Button {
                icon.name: "notifications"
                onClicked: testNotifications()
                visible: devMode
                implicitHeight: 28
                implicitWidth: 28

                PlasmaComponents.ToolTip {
                    text: "Test notification"
                }
            }

            PlasmaComponents.BusyIndicator {
                running: isRefreshing
                visible: isRefreshing
                implicitWidth: 20
                implicitHeight: 20
            }

            PlasmaComponents.Button {
                icon.name: "view-refresh"
                onClicked: fetchData()
                visible: configured && !isRefreshing
                implicitHeight: 28
                implicitWidth: 28
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
            visible: !configured
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
                    if (!hasCoreConfig) return "Not Configured"
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
                    if (!hasCoreConfig) return "Right-click → Configure Widget"
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
            height: loading ? 50 : 0
            visible: loading

            PlasmaComponents.BusyIndicator {
                anchors.centerIn: parent
                running: loading
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
            visible: configured && !loading && errorMessage === ""

            QQC2.ScrollView {
                id: scrollView
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                clip: true

                QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
                QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AsNeeded

                // Reserve width for overlay scrollbar so right-side actions aren't covered.
                // Keep this small; we also reserve it inside each row.
                readonly property int __scrollbarGap: 2
                readonly property int __scrollbarReserve: 14 + __scrollbarGap

                ColumnLayout {
                    id: mainContentColumn
                    width: scrollView.availableWidth
                    spacing: 8

                Repeater {
                    visible: connectionMode === "single"
                    model: displayedProxmoxData && displayedProxmoxData.data ? displayedProxmoxData.data : []

                    delegate: NodeSection {
                        required property int index
                        required property var modelData

                        nodeIndex: index
                        nodeModel: modelData
                        nodeVms: getVmsForNode(modelData ? modelData.node : "")
                        nodeLxc: getLxcForNode(modelData ? modelData.node : "")
                        isCollapsed: isNodeCollapsed(modelData ? modelData.node : "")
                        uiRadiusS: root.uiRadiusS
                        uiRadiusL: root.uiRadiusL
                        uiBorderOpacity: root.uiBorderOpacity
                        uiSurfaceAltOpacity: root.uiSurfaceAltOpacity
                        uiSurfaceRunningOpacity: root.uiSurfaceRunningOpacity
                        uiNodeCardOpacity: root.uiNodeCardOpacity
                        uiWindowOpacity: root.uiWindowOpacity
                        uiRunningColor: root.uiRunningColor
                        uiStoppedColor: root.uiStoppedColor
                        uiRowHeight: root.uiRowHeight
                        scrollbarReserve: scrollView.__scrollbarReserve
                        safeCpuPercent: root.safeCpuPercent
                        anonymizeNodeName: root.anonymizeNodeName
                        anonymizeVmId: root.anonymizeVmId
                        anonymizeVmName: root.anonymizeVmName
                        anonymizeLxcName: root.anonymizeLxcName
                        isActionBusy: root.isActionBusy
                        armedActionKey: root.armedActionKey
                        armedTimerRunning: armedTimer.running
                        getRunningVmsForNode: root.getRunningVmsForNode
                        getTotalVmsForNode: root.getTotalVmsForNode
                        getRunningLxcForNode: root.getRunningLxcForNode
                        getTotalLxcForNode: root.getTotalLxcForNode
                        onToggleCollapsed: function(nodeName) { root.toggleNodeCollapsed(nodeName) }
                        onAction: function(kind, nodeName, vmid, displayName, action) {
                            root.confirmAndRunAction(kind, nodeName, vmid, displayName, action)
                        }
                    }
                }

                // Multi-host view (group by endpoint)
                Repeater {
                    visible: connectionMode === "multiHost"
                    model: displayedEndpointsModel

                    Component.onCompleted: {
                        console.log("[ProxMon UI] multi repeater visible=", visible,
                                    "mode=", connectionMode,
                                    "modelLen=", displayedEndpointsModel ? displayedEndpointsModel.length : -1)
                    }

                    delegate: MultiHostEndpointSection {
                        required property var modelData
                        endpoint: modelData
                        uiRadiusL: root.uiRadiusL
                        uiBorderOpacity: root.uiBorderOpacity
                        uiMutedTextOpacity: root.uiMutedTextOpacity
                        uiNodeCardOpacity: root.uiNodeCardOpacity
                        uiWindowOpacity: root.uiWindowOpacity
                        uiRunningColor: root.uiRunningColor
                        uiStoppedColor: root.uiStoppedColor
                        scrollbarReserve: scrollView.__scrollbarReserve
                        safeCpuPercent: root.safeCpuPercent
                        anonymizeNodeName: root.anonymizeNodeName
                        anonymizeVmId: root.anonymizeVmId
                        anonymizeVmName: root.anonymizeVmName
                        anonymizeLxcName: root.anonymizeLxcName
                        getVmsForNodeMulti: root.getVmsForNodeMulti
                        getLxcForNodeMulti: root.getLxcForNodeMulti
                        isNodeCollapsed: root.isNodeCollapsed
                        getRunningVmsForNodeMulti: root.getRunningVmsForNodeMulti
                        getTotalVmsForNodeMulti: root.getTotalVmsForNodeMulti
                        getRunningLxcForNodeMulti: root.getRunningLxcForNodeMulti
                        getTotalLxcForNodeMulti: root.getTotalLxcForNodeMulti
                        isActionBusy: root.isActionBusy
                        armedActionKey: root.armedActionKey
                        armedTimerRunning: armedTimer.running
                        armedActionSessionKey: root.armedActionKey.indexOf("::") !== -1 ? root.armedActionKey.split("::")[0] : ""
                        onToggleCollapsed: function(nodeName, sessionKey) {
                            root.toggleNodeCollapsed(nodeName, sessionKey)
                        }
                        onAction: function(sessionKey, kind, nodeName, vmid, displayName, action) {
                            root.confirmAndRunActionForSession(sessionKey, kind, nodeName, vmid, displayName, action)
                        }
                    }
                }

                // Empty state
                PlasmaComponents.Label {
                    text: "No nodes found"
                    visible: (connectionMode === "single")
                        ? (!displayedProxmoxData || !displayedProxmoxData.data || displayedProxmoxData.data.length === 0)
                        : (displayedEndpointsModel.length === 0)
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

        // Footer (keep it pinned to the bottom of the panel; prevent "floating" during ScrollView relayout)
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

    // ==================== REFRESH TIMER ====================

    Timer {
        interval: root.refreshInterval > 0 ? root.refreshInterval : 30000
        running: root.configured
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetchData()
    }
}
