pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import "../lib/proxmox" as ProxMon

PlasmoidItem {
    id: root

    // ==================== CONNECTION / MODE ====================

    // Connection mode: "single" | "multiHost"
    property string connectionMode: Plasmoid.configuration.connectionMode || "single"

    // Single-host connection properties
    property string proxmoxHost: Plasmoid.configuration.proxmoxHost || ""
    property int proxmoxPort: Plasmoid.configuration.proxmoxPort || 8006
    property string apiTokenId: Plasmoid.configuration.apiTokenId || ""
    // Token secret must live in keyring (SecretStore). Do not read from config.
    property string apiTokenSecret: ""

    // Multi-host config (KCM stores these)
    property string multiHostsJson: Plasmoid.configuration.multiHostsJson || "[]"
    // SECURITY: do not store/read secrets from config.
    property string multiHostSecretsJson: "{}"

    // secretState: idle|loading|ready|missing|error
    property string secretState: "idle"

    // Endpoints resolved in multi-host mode:
    // [{ sessionKey, label, host, port, tokenId, secret, ignoreSsl }]
    property var endpoints: []
    // Per-endpoint secret load progress
    property int secretsResolved: 0
    property int secretsTotal: 0

    property int refreshInterval: (Plasmoid.configuration.refreshInterval || 30) * 1000
    property bool ignoreSsl: Plasmoid.configuration.ignoreSsl !== false
    property string defaultSorting: Plasmoid.configuration.defaultSorting || "status"

    // Auto-retry/backoff
    property bool autoRetry: Plasmoid.configuration.autoRetry !== false
    property int retryStartMs: Math.max(1000, (Plasmoid.configuration.retryStartSeconds || 5) * 1000)
    property int retryMaxMs: Math.max(retryStartMs, (Plasmoid.configuration.retryMaxSeconds || 300) * 1000)
    property int retryAttempt: 0
    property int retryNextDelayMs: 0
    property string retryStatusText: ""

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

    // Raw data (updated during fetch)
    // Single-host legacy (kept for compatibility while wiring multi-host)
    property var proxmoxData: null
    property var vmData: []
    property var lxcData: []

    // Displayed data (only updated when all requests complete)
    // Single-host legacy (kept for compatibility while wiring multi-host)
    property var displayedProxmoxData: null
    property var displayedVmData: []
    property var displayedLxcData: []

    // Multi-host displayed buckets (preferred when connectionMode === "multiHost")
    // [{ sessionKey, label, host, port, nodes: [...], vms: [...], lxcs: [...] }]
    property var displayedEndpoints: []

    // State properties
    property bool loading: false
    property bool isRefreshing: false
    property string errorMessage: ""
    property string lastUpdate: ""

    // One-time hint to guide users when action permissions are missing
    property bool actionPermHintShown: false
    property string actionPermHint: ""

    property bool hasCoreConfig: {
        if (connectionMode === "multiHost") {
            // core config is at least one endpoint entry (host + tokenId)
            try {
                var arr = JSON.parse(multiHostsJson || "[]")
                if (!Array.isArray(arr)) return false
                for (var i = 0; i < arr.length; i++) {
                    var e = arr[i] || {}
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
    property bool configured: {
        if (connectionMode === "multiHost") {
            return secretState === "ready" && endpoints && endpoints.length > 0
        }
        return hasCoreConfig && secretState === "ready" && apiTokenSecret !== ""
    }
    property bool defaultsLoaded: false
    property bool devMode: false
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
    property var nodeList: []
    property var displayedNodeList: []
    property var pendingNodeRequests: 0
    property var tempVmData: []
    property var tempLxcData: []

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

    // ==================== UTILITY FUNCTIONS ====================


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
        tokenSecret: apiTokenSecret
        ignoreSslErrors: ignoreSsl

        onReply: function(seq, kind, node, data) {
            // Ignore late responses from older refresh cycles
            if (seq !== refreshSeq) return
            // Single-host only
            if (connectionMode !== "single") return

            if (kind === "nodes") {
                if (!displayedProxmoxData) {
                    loading = false
                }

                proxmoxData = data
                errorMessage = ""
                lastUpdate = Qt.formatDateTime(new Date(), "hh:mm:ss")
                resetRetryState()

                if (proxmoxData && proxmoxData.data && proxmoxData.data.length > 0) {
                    nodeList = proxmoxData.data.map(function(n) { return n.node })

                    tempVmData = []
                    tempLxcData = []
                    pendingNodeRequests = nodeList.length * 2
    
                    for (var i = 0; i < nodeList.length; i++) {
                        api.requestQemu(nodeList[i], refreshSeq)
                        api.requestLxc(nodeList[i], refreshSeq)
                    }
                } else {
                    displayedProxmoxData = proxmoxData
                    displayedNodeList = []
                    displayedVmData = []
                    displayedLxcData = []
                    isRefreshing = false
                    loading = false
                }
            } else if (kind === "qemu") {
                if (data && data.data) {
                    for (var j = 0; j < data.data.length; j++) {
                            data.data[j].node = node
                        tempVmData.push(data.data[j])
                    }
                }
                pendingNodeRequests--
                checkRequestsComplete()
            } else if (kind === "lxc") {
                if (data && data.data) {
                    for (var k = 0; k < data.data.length; k++) {
                        data.data[k].node = node
                        tempLxcData.push(data.data[k])
                    }
                }
                pendingNodeRequests--
                checkRequestsComplete()
            }
        }

        onError: function(seq, kind, node, message) {
            if (seq !== refreshSeq) return
            if (connectionMode !== "single") return

            logDebug("api error: " + kind + " " + node + " - " + message)
            errorMessage = message || "Connection failed"
            pendingNodeRequests = 0
            isRefreshing = false
            loading = false

            scheduleRetry(errorMessage)
        }

        onReplyFor: function(seq, sessionKey, kind, node, data) {
            if (seq !== refreshSeq) return
            if (connectionMode !== "multiHost") return
            handleMultiReply(sessionKey, kind, node, data)
        }

        onErrorFor: function(seq, sessionKey, kind, node, message) {
            if (seq !== refreshSeq) return
            if (connectionMode !== "multiHost") return
            handleMultiError(sessionKey, kind, node, message)
        }

        onActionReply: function(seq, actionKind, node, vmid, action, data) {
            logDebug("onActionReply: " + actionKind + " " + node + " " + vmid + " " + action)
            // any action completion clears busy state
            var key = node + ":" + actionKind + ":" + vmid
            var newBusy = Object.assign({}, actionBusy)
            delete newBusy[key]
            actionBusy = newBusy

            var upid = ""
            try {
                if (data && data.data && typeof data.data === "string") {
                    upid = data.data
                }
            } catch (e) { upid = "" }

            // UPID tail can include user@realm!tokenid (sensitive). Redact both user@realm and tokenid.
            function sanitizeUpid(u) {
                u = String(u || "")
                // Example tail: "...:user@realm!TOKENID:"
                // 1) Replace "user@realm" with "REDACTED@realm"
                u = u.replace(/:([^:@]+)@/g, ":REDACTED@")
                // 2) Redact everything between "!" and the next ":".
                u = u.replace(/!([^:]*):/g, "!REDACTED:")
                return u
            }

            var upidSafe = sanitizeUpid(upid)

            if (devMode && upid) {
                console.log("[Proxmox] Action UPID: " + upid)
            }

            sendNotification(
                (actionKind === "qemu" ? "VM" : "Container") + " action",
                (actionKind === "qemu" ? "VM" : "CT") + " " + vmid + " " + action + " OK" + (upidSafe ? (" (task " + upidSafe + ")") : ""),
                "dialog-information",
                "action:" + actionKind + ":" + node + ":" + vmid + ":" + action + ":ok"
            )
            fetchData()
        }

        onActionError: function(seq, actionKind, node, vmid, action, message) {
            logDebug("onActionError: " + actionKind + " " + node + " " + vmid + " " + action + " - " + (message || ""))
            var key = node + ":" + actionKind + ":" + vmid
            var newBusy = Object.assign({}, actionBusy)
            delete newBusy[key]
            actionBusy = newBusy

            errorMessage = message || "Action failed"

            // Detect common permission failures and show a one-time actionable hint.
            var m = (message || "").toLowerCase()
            if (!actionPermHintShown && (m.indexOf("http 401") !== -1 || m.indexOf("http 403") !== -1 || m.indexOf("authentication failed") !== -1 || m.indexOf("permission") !== -1 || m.indexOf("forbidden") !== -1)) {
                actionPermHintShown = true
                actionPermHint = "Power actions require Proxmox permission: VM.PowerMgmt (scope /vms or /vms/{vmid})."
                sendNotification(
                    "Missing permissions for actions",
                    actionPermHint,
                    "dialog-warning",
                    "permhint:actions"
                )
            }

            sendNotification(
                (actionKind === "qemu" ? "VM" : "Container") + " action failed",
                (actionKind === "qemu" ? "VM" : "CT") + " " + vmid + " " + action + ": " + (message || ""),
                "dialog-error",
                "action:" + actionKind + ":" + node + ":" + vmid + ":" + action + ":err"
            )
        }
    }


    // Debug logging (actions always log; devMode gates noisy logs elsewhere)
    function logDebug(message) {
        var now = new Date()
        var timestamp = now.getFullYear() + "-" +
            (now.getMonth() + 1).toString().padStart(2, '0') + "-" +
            now.getDate().toString().padStart(2, '0') + " " +
            now.getHours().toString().padStart(2, '0') + ":" +
            now.getMinutes().toString().padStart(2, '0') + ":" +
            now.getSeconds().toString().padStart(2, '0') + "." +
            now.getMilliseconds().toString().padStart(3, '0')
        console.log("[Proxmox " + timestamp + "] " + message)
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
            lxcCount: displayedLxcData.length
        }
        return JSON.stringify(info, null, 2)
    }

    function copyDebugInfo() {
        // SECURITY: avoid shelling out from QML.
        sendNotification("Debug info", "Copy-to-clipboard is disabled for security (no shell execution).", "dialog-information")
    }

    // ==================== NOTIFICATION FUNCTIONS ====================

    // Escape regex special chars except "*" (wildcard)
    function escapeRegexPattern(str) {
        if (!str) return ""
        // Escape everything that has meaning in a regex
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
                var escaped = escapeRegexPattern(filter).replace(/\\\*/g, ".*")
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
            logDebug("Notification suppressed (disabled): " + title + " - " + message)
            return
        }

        if (rateLimitKey && shouldRateLimitNotify(rateLimitKey)) {
            logDebug("Notification suppressed (rate-limited): " + rateLimitKey)
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

        // SECURITY: do not shell out from QML (no notify-send fallback).
        // If the native notifier fails, silently drop the notification.
        if (notifier.notify(title, message, iconName || "proxmox-monitor", 5000)) {
            if (rateLimitKey) markNotifySent(rateLimitKey)
        }
    }

    // Test notifications function (dev mode)
    function testNotifications() {
        logDebug("Testing notifications...")
        sendNotification("VM Stopped", "test-vm (100) on pve1 is now stopped", "dialog-warning", "test:vmStopped")
    }

    // Check for state changes and send notifications
    function checkStateChanges() {
        if (!initialLoadComplete) {
            logDebug("checkStateChanges: Initial load, recording states")

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
            logDebug("checkStateChanges: Recorded " + Object.keys(previousNodeStates).length + " node states, " +
                     Object.keys(previousVmStates).length + " VM states, " +
                     Object.keys(previousLxcStates).length + " LXC states")
            return
        }

        // Check nodes for state changes
        if (notifyOnNodeChange && displayedProxmoxData && displayedProxmoxData.data) {
            for (var ni = 0; ni < displayedProxmoxData.data.length; ni++) {
                var nodeData = displayedProxmoxData.data[ni]
                var prevNodeState = previousNodeStates[nodeData.node]

                if (prevNodeState !== undefined && prevNodeState !== nodeData.status) {
                    logDebug("checkStateChanges: Node " + nodeData.node + " changed from " + prevNodeState + " to " + nodeData.status)

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
                        sendNotification(
                            "VM Stopped",
                            vmItem.name + " (" + vmItem.vmid + ") on " + vmItem.node + " is now " + vmItem.status,
                            "dialog-warning",
                            "vm:" + vmItem.node + ":" + vmItem.vmid + ":stopped"
                        )
                    } else if (notifyOnStart && prevVmState !== "running" && vmItem.status === "running") {
                        sendNotification(
                            "VM Started",
                            vmItem.name + " (" + vmItem.vmid + ") on " + vmItem.node + " is now running",
                            "dialog-information",
                            "vm:" + vmItem.node + ":" + vmItem.vmid + ":running"
                        )
                    }
                } else {
                    logDebug("checkStateChanges: Notification filtered for VM " + vmItem.name)
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
                        sendNotification(
                            "Container Stopped",
                            lxcItem.name + " (" + lxcItem.vmid + ") on " + lxcItem.node + " is now " + lxcItem.status,
                            "dialog-warning",
                            "lxc:" + lxcItem.node + ":" + lxcItem.vmid + ":stopped"
                        )
                    } else if (notifyOnStart && prevLxcState !== "running" && lxcItem.status === "running") {
                        sendNotification(
                            "Container Started",
                            lxcItem.name + " (" + lxcItem.vmid + ") on " + lxcItem.node + " is now running",
                            "dialog-information",
                            "lxc:" + lxcItem.node + ":" + lxcItem.vmid + ":running"
                        )
                    }
                } else {
                    logDebug("checkStateChanges: Notification filtered for LXC " + lxcItem.name)
                }
            }
            previousLxcStates[lxcStateKey] = lxcItem.status
        }

        logDebug("checkStateChanges: State check complete")
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

    function actionKey(nodeName, kind, vmid) {
        return nodeName + ":" + kind + ":" + vmid
    }

    function isActionBusy(nodeName, kind, vmid) {
        return actionBusy[actionKey(nodeName, kind, vmid)] === true
    }

    function setActionBusy(nodeName, kind, vmid, busy) {
        var key = actionKey(nodeName, kind, vmid)
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
            // confirmed
            armedActionKey = ""
            armedTimer.stop()
            setActionBusy(nodeName, kind, vmid, true)
            api.requestAction(kind, nodeName, vmid, action, ++actionSeq)
            return
        }

        // arm
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
            console.log("[Proxmox] Developer mode: " + (devMode ? "ENABLED" : "DISABLED"))
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
    function checkRequestsComplete() {
        logDebug("checkRequestsComplete: Pending requests: " + pendingNodeRequests)

        if (pendingNodeRequests <= 0) {
            refreshWatchdog.stop()

            logDebug("checkRequestsComplete: All requests complete")
            logDebug("checkRequestsComplete: Nodes: " + nodeList.length + ", VMs: " + tempVmData.length + ", LXCs: " + tempLxcData.length)

            // Atomically update all displayed data at once
            displayedProxmoxData = proxmoxData
            displayedNodeList = nodeList.slice()
            displayedVmData = tempVmData.slice()
            displayedLxcData = tempLxcData.slice()

            // Update raw data
            vmData = tempVmData.slice()
            lxcData = tempLxcData.slice()

            // Clear temp data
            tempVmData = []
            tempLxcData = []

            // Mark refresh complete
            isRefreshing = false
            loading = false

            logDebug("checkRequestsComplete: Display data updated")

            // Check for state changes and send notifications
            checkStateChanges()
        }
    }

    // ==================== API FUNCTIONS ====================

    // Sequencing for refreshes so we can ignore late responses from older refresh cycles
    property int refreshSeq: 0

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
                logDebug("refreshWatchdog: Timed out, pending requests: " + pendingNodeRequests)
                // Cancel in-flight requests to avoid late reply storms.
                api.cancelAll()
                errorMessage = "Request timed out"
                pendingNodeRequests = 0
                isRefreshing = false
                loading = false
                scheduleRetry("Request timed out")
            }
        }
    }

    Timer {
        id: retryTimer
        repeat: false
        onTriggered: {
            retryStatusText = ""
            fetchData()
        }
    }

    function scheduleRetry(reason) {
        if (!autoRetry) return
        if (!configured) return
        if (retryTimer.running) return

        retryAttempt += 1

        // Exponential backoff starting at retryStartMs, capped at retryMaxMs
        var delay = retryStartMs * Math.pow(2, retryAttempt - 1)
        delay = Math.min(delay, retryMaxMs)
        delay = Math.round(delay)

        retryNextDelayMs = delay
        retryStatusText = "Retrying in " + Math.round(delay / 1000) + "s…"

        logDebug("autoRetry: attempt " + retryAttempt + ", delay " + delay + "ms, reason: " + (reason || ""))
        retryTimer.interval = delay
        retryTimer.restart()
    }

    function resetRetryState() {
        retryAttempt = 0
        retryNextDelayMs = 0
        retryStatusText = ""
        retryTimer.stop()
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
        resetRetryState()
        errorMessage = ""
        retryStatusText = ""
        armedActionKey = ""
        armedLabel = ""
        // If secrets need re-resolving (e.g. token changed), resolveSecretIfNeeded() handlers will do it.
        // Only refresh if we are configured.
        if (!configured) return
        configRefreshDebounce.restart()
    }

    function fetchData() {
        if (!configured) {
            logDebug("fetchData: Not configured, skipping")
            return
        }

        // Stop any previous in-flight requests before starting a new refresh.
        api.cancelAll()

        refreshSeq++

        var isInitial = false
        if (connectionMode === "multiHost") {
            isInitial = displayedEndpoints.length === 0
        } else {
            isInitial = !displayedProxmoxData
        }

        if (isInitial) {
            loading = true
            logDebug("fetchData: Initial load started")
        } else {
            isRefreshing = true
            logDebug("fetchData: Refresh started")
        }

        // Reset temp state for this refresh cycle
        pendingNodeRequests = 0
        tempVmData = []
        tempLxcData = []
        errorMessage = ""

        resetMultiTempData()

        refreshWatchdog.restart()

        if (connectionMode === "multiHost") {
            // One pending for each /nodes call; node child calls added when nodes replies arrive
            pendingNodeRequests = endpoints.length
            for (var i = 0; i < endpoints.length; i++) {
                var e = endpoints[i]
                logDebug("fetchData(multi): /nodes from " + e.host + ":" + e.port + " (" + (e.label || e.sessionKey) + ")")
                api.requestNodesFor(e.sessionKey, e.host, e.port, e.tokenId, e.secret, e.ignoreSsl, refreshSeq)
            }
            return
        }

        logDebug("fetchData: Requesting /nodes from " + proxmoxHost + ":" + proxmoxPort)
        api.requestNodes(refreshSeq)
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

    function normalizedHost(h) {
        return (h || "").trim().toLowerCase()
    }

    function normalizedTokenId(t) {
        return (t || "").trim()
    }

    function keyFor(host, port, tokenId) {
        return "apiTokenSecret:" + normalizedTokenId(tokenId) + "@" + normalizedHost(host) + ":" + String(port)
    }

    function endpointNodeKey(sessionKey, nodeName) {
        return String(sessionKey) + "::" + String(nodeName || "")
    }

    // ---------- Multi-host: parse config + resolve secrets (sequential queue) ----------

    property var secretQueue: []
    property int secretQueueIndex: 0
    property var tempEndpoints: []

    function parseMultiHosts() {
        try {
            var arr = JSON.parse(multiHostsJson || "[]")
            if (!Array.isArray(arr)) return []
            return arr.slice(0, 5)
        } catch (e) {
            return []
        }
    }

    function buildSecretQueue() {
        var raw = parseMultiHosts()
        var q = []
        for (var i = 0; i < raw.length; i++) {
            var e = raw[i] || {}
            var host = (e.host || "").trim()
            var tokenId = (e.tokenId || "").trim()
            if (!host || !tokenId) continue
            var port = (e.port !== undefined && e.port !== null) ? Number(e.port) : 8006
            if (!port) port = 8006
            var label = (e.name || "").trim()
            var sessionKey = keyFor(host, port, tokenId)
            q.push({ sessionKey: sessionKey, label: label, host: host, port: port, tokenId: tokenId })
        }
        return q
    }


    function startMultiSecretResolution() {
        secretsResolved = 0
        tempEndpoints = []
        secretQueue = buildSecretQueue()
        secretsTotal = secretQueue.length
        secretQueueIndex = 0

        if (secretsTotal === 0) {
            endpoints = []
            secretState = hasCoreConfig ? "missing" : "idle"
            return
        }

        secretState = "loading"
        readNextMultiSecret()
    }

    function readNextMultiSecret() {
        if (secretQueueIndex >= secretQueue.length) {
            // done
            endpoints = tempEndpoints.slice()
            secretState = (endpoints.length > 0) ? "ready" : "missing"
            return
        }

        var item = secretQueue[secretQueueIndex]
        secretStore.key = item.sessionKey
        secretStore.readSecret()
    }

    // ---------- Multi-host: fetching / aggregation ----------

    property var tempEndpointsData: ({})

    function resetMultiTempData() {
        tempEndpointsData = ({})
    }

    function ensureEndpointBucket(sessionKey) {
        var b = tempEndpointsData[sessionKey]
        if (b) return b
        // find meta
        var meta = null
        for (var i = 0; i < endpoints.length; i++) {
            if (endpoints[i].sessionKey === sessionKey) {
                meta = endpoints[i]
                break
            }
        }
        b = {
            sessionKey: sessionKey,
            label: meta ? meta.label : "",
            host: meta ? meta.host : "",
            port: meta ? meta.port : 8006,
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
        var keys = Object.keys(map || {})
        // stable order: by label then host
        keys.sort(function(a, b) {
            var aa = map[a] || {}
            var bb = map[b] || {}
            var la = (aa.label || aa.host || aa.sessionKey || "")
            var lb = (bb.label || bb.host || bb.sessionKey || "")
            return String(la).localeCompare(String(lb))
        })
        for (var i = 0; i < keys.length; i++) {
            arr.push(map[keys[i]])
        }
        return arr
    }

    function handleMultiReply(sessionKey, kind, node, data) {
        if (!sessionKey) return
        if (kind === "nodes") {
            var bucket = ensureEndpointBucket(sessionKey)
            var list = (data && data.data) ? data.data.slice() : []
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
        pendingNodeRequests = 0
        isRefreshing = false
        loading = false
        scheduleRetry(errorMessage)
    }

    function endpointBySession(sessionKey) {
        for (var i = 0; i < endpoints.length; i++) {
            if (endpoints[i].sessionKey === sessionKey) return endpoints[i]
        }
        return null
    }

    function checkMultiRequestsComplete() {
        if (pendingNodeRequests > 0) return

        refreshWatchdog.stop()

        displayedEndpoints = bucketsToArray(tempEndpointsData)

        // Single-host legacy view state cleared
        displayedProxmoxData = null
        displayedNodeList = []
        displayedVmData = []
        displayedLxcData = []

        // Derive last update and reset retry
        errorMessage = ""
        lastUpdate = Qt.formatDateTime(new Date(), "hh:mm:ss")
        resetRetryState()

        isRefreshing = false
        loading = false

        // TODO: state change notifications across endpoints (future); for now, reuse existing logic only for single-host.
    }

    // Try multiple keys for backwards compatibility (older formatting / pre-normalization).
    property var secretKeyCandidates: []
    property int secretKeyCandidateIndex: 0

    function startSecretReadCandidates() {
        if (!hasCoreConfig) return

        var candidates = []
        // New canonical key (normalized)
        candidates.push(keyFor(proxmoxHost, proxmoxPort, apiTokenId))
        // Legacy exact key (as previously constructed)
        candidates.push("apiTokenSecret:" + apiTokenId + "@" + proxmoxHost + ":" + proxmoxPort)
        // Legacy trimmed-only variants (common user input issues)
        candidates.push("apiTokenSecret:" + normalizedTokenId(apiTokenId) + "@" + proxmoxHost + ":" + proxmoxPort)
        candidates.push("apiTokenSecret:" + apiTokenId + "@" + normalizedHost(proxmoxHost) + ":" + proxmoxPort)

        // de-dup, preserve order
        var seen = {}
        var uniq = []
        for (var i = 0; i < candidates.length; i++) {
            var k = candidates[i]
            if (!k || seen[k]) continue
            seen[k] = true
            uniq.push(k)
        }

        secretKeyCandidates = uniq
        secretKeyCandidateIndex = 0
        secretStore.key = secretKeyCandidates[0]
        secretStore.readSecret()
    }

    ProxMon.SecretStore {
        id: secretStore
        service: "ProxMon"
        // key is set dynamically via startSecretReadCandidates() / startMultiSecretResolution()
        key: keyFor(proxmoxHost, proxmoxPort, apiTokenId)

        onSecretReady: function(secret) {
            // Multi-host path (queue-driven)
            if (connectionMode === "multiHost" && secretState === "loading" && secretQueue && secretQueue.length > 0) {
                var item = secretQueue[secretQueueIndex]
                var sessionKey = item ? item.sessionKey : ""

                if (secret && secret.length > 0) {
                    tempEndpoints.push({
                        sessionKey: sessionKey,
                        label: item.label,
                        host: item.host,
                        port: item.port,
                        tokenId: item.tokenId,
                        secret: secret,
                        ignoreSsl: ignoreSsl
                    })
                    secretsResolved += 1
                    secretQueueIndex += 1
                    readNextMultiSecret()
                    return
                }

                // No keyring entry; skip this endpoint (KCM no longer stashes plaintext secrets).
                secretsResolved += 1
                secretQueueIndex += 1
                readNextMultiSecret()
                return
            }

            // Single-host path (legacy candidates)
            if (secret && secret.length > 0) {
                // If we loaded from a legacy key, migrate into canonical normalized key.
                var canonicalKey = keyFor(proxmoxHost, proxmoxPort, apiTokenId)
                if (secretStore.key !== canonicalKey) {
                    logDebug("secretStore: Migrating secret to canonical key")
                    var oldKey = secretStore.key
                    secretStore.key = canonicalKey
                    secretStore.writeSecret(secret)
                    secretStore.key = oldKey
                }

                logDebug("secretStore: Secret loaded from keyring")
                apiTokenSecret = secret
                secretState = "ready"
                return
            }

            // Try next candidate key if available
            if (secretKeyCandidates && (secretKeyCandidateIndex + 1) < secretKeyCandidates.length) {
                secretKeyCandidateIndex += 1
                secretStore.key = secretKeyCandidates[secretKeyCandidateIndex]
                logDebug("secretStore: Secret not found, trying next key candidate: " + secretStore.key)
                secretStore.readSecret()
                return
            }

            // No keyring entry. If we still have a legacy plaintext secret in config,
            // migrate it into the keyring and immediately clear the plaintext value.
            if (Plasmoid.configuration.apiTokenSecret && Plasmoid.configuration.apiTokenSecret.length > 0) {
                logDebug("secretStore: Migrating legacy plaintext secret into keyring")
                secretStore.key = keyFor(proxmoxHost, proxmoxPort, apiTokenId)
                secretStore.writeSecret(Plasmoid.configuration.apiTokenSecret)
                apiTokenSecret = Plasmoid.configuration.apiTokenSecret
                Plasmoid.configuration.apiTokenSecret = ""
                secretState = "ready"
                return
            }

            secretState = "missing"
            logDebug("secretStore: No keyring secret found (and no legacy secret)")
        }

        onWriteFinished: function(ok, error) {
            if (!ok) {
                logDebug("secretStore: write failed: " + error)
                // Still treat secret as ready if we already set apiTokenSecret from legacy config;
                // failing to write just means it won't persist.
            }
        }

        onError: function(message) {
            secretState = "error"
            logDebug("secretStore: " + message)
        }
    }

    function resolveSecretIfNeeded() {
        if (!hasCoreConfig) {
            endpoints = []
            secretState = "idle"
            return
        }

        if (connectionMode === "multiHost") {
            startMultiSecretResolution()
            return
        }

        // Single-host legacy:
        // If we already have a secret from legacy config binding, consider it ready.
        // (We still attempt keyring read to migrate/ensure correct secret, but avoid UI flicker.)
        if (apiTokenSecret && apiTokenSecret.length > 0 && secretState !== "ready") {
            secretState = "ready"
        }
        if (secretState === "loading") return
        secretState = "loading"
        startSecretReadCandidates()
    }

    onProxmoxHostChanged: {
        if (connectionMode === "single") resolveSecretIfNeeded()
        triggerRefreshFromConfigChange("proxmoxHost")
    }
    onProxmoxPortChanged: {
        if (connectionMode === "single") resolveSecretIfNeeded()
        triggerRefreshFromConfigChange("proxmoxPort")
    }
    onApiTokenIdChanged: {
        if (connectionMode === "single") resolveSecretIfNeeded()
        triggerRefreshFromConfigChange("apiTokenId")
    }

    // If the secret is entered via the config UI (legacy plaintext field), it updates
    // Plasmoid.configuration.apiTokenSecret but may not change apiTokenId/host/port.
    // React to it so the widget transitions out of "Not Configured" immediately.
    onApiTokenSecretChanged: {
        if (connectionMode === "single") resolveSecretIfNeeded()
        triggerRefreshFromConfigChange("apiTokenSecret")
    }
    onMultiHostsJsonChanged: {
        if (connectionMode === "multiHost") resolveSecretIfNeeded()
        triggerRefreshFromConfigChange("multiHostsJson")
    }
    onConnectionModeChanged: {
        resolveSecretIfNeeded()
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
    }

    // ==================== DATA SOURCES ====================

    // SECURITY: no "executable" datasources in QML (no shell execution).

    // ==================== COMPACT REPRESENTATION ====================

    compactRepresentation: Item {
        implicitWidth: compactRow.implicitWidth + 4 + 8
        implicitHeight: compactRow.implicitHeight

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -2
            spacing: 4

            Kirigami.Icon {
                id: proxmoxIcon
                source: "proxmox-monitor"
                implicitWidth: 22
                implicitHeight: 22

                SequentialAnimation {
                    id: heartbeatAnimation
                    running: loading || isRefreshing
                    loops: Animation.Infinite

                    PropertyAnimation {
                        target: proxmoxIcon
                        property: "scale"
                        from: 1.0
                        to: 1.2
                        duration: 150
                        easing.type: Easing.OutQuad
                    }
                    PropertyAnimation {
                        target: proxmoxIcon
                        property: "scale"
                        from: 1.2
                        to: 1.0
                        duration: 150
                        easing.type: Easing.InQuad
                    }
                    PropertyAnimation {
                        target: proxmoxIcon
                        property: "scale"
                        from: 1.0
                        to: 1.15
                        duration: 120
                        easing.type: Easing.OutQuad
                    }
                    PropertyAnimation {
                        target: proxmoxIcon
                        property: "scale"
                        from: 1.15
                        to: 1.0
                        duration: 120
                        easing.type: Easing.InQuad
                    }
                    PauseAnimation {
                        duration: 400
                    }
                }

                Connections {
                    target: root
                    function onLoadingChanged() {
                        if (!loading && !isRefreshing) {
                            proxmoxIcon.scale = 1.0
                        }
                    }
                    function onIsRefreshingChanged() {
                        if (!loading && !isRefreshing) {
                            proxmoxIcon.scale = 1.0
                        }
                    }
                }
            }

            PlasmaComponents.Label {
                text: {
                    // Avoid "Not configured" flicker while secrets load.
                    if (!hasCoreConfig) return "⚙"
                    if (secretState === "loading") return "..."
                    if (secretState === "missing" || secretState === "error") return "!"
                    if (!configured) return "⚙"
                    if (loading) return "..."

                    switch (compactMode) {
                        case "running":
                            var running = runningVMs + runningLXC
                            var total = displayedVmData.length + displayedLxcData.length
                            return running + "/" + total

                        case "lastUpdate":
                            return lastUpdate ? lastUpdate : "-"

                        case "error":
                            if (errorMessage) return "!"
                            // fallthrough to cpu style
                            break

                        case "cpu":
                        default:
                            break
                    }

                    if (errorMessage) return "!"

                    if (displayedProxmoxData && displayedProxmoxData.data && displayedProxmoxData.data[0]) {
                        var totalCpu = 0
                        for (var i = 0; i < displayedProxmoxData.data.length; i++) {
                            totalCpu += displayedProxmoxData.data[i].cpu
                        }
                        return Math.round((totalCpu / displayedProxmoxData.data.length) * 100) + "%"
                    }
                    return "-"
                }
                font.pixelSize: 13
                rightPadding: 6
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    // ==================== FULL REPRESENTATION ====================

    fullRepresentation: ColumnLayout {
        id: fullRep
        Layout.preferredWidth: 380
        Layout.preferredHeight: Math.min(calculatedHeight, 500)
        Layout.minimumWidth: 350
        Layout.minimumHeight: 200
        Layout.maximumHeight: 600
        spacing: 2

        // Header
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            Layout.topMargin: 8
            Layout.bottomMargin: 4
            Layout.preferredHeight: 36

            PlasmaComponents.Label {
                text: configured ? "Proxmox - " + anonymizeHost(proxmoxHost) : "Proxmox Monitor"
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
            Layout.fillWidth: true
            Layout.fillHeight: true
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
                    if (secretState === "loading") return "Loading Credentials…"
                    if (secretState === "missing") return "Missing Token Secret"
                    if (secretState === "error") return "Credentials Error"
                    return "Not Configured"
                }
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            PlasmaComponents.Label {
                text: {
                    if (!hasCoreConfig) return "Right-click → Configure Widget"
                    if (secretState === "loading") return "Reading API token secret from keyring…"
                    if (secretState === "missing") return "Open settings and re-enter the API Token Secret."
                    if (secretState === "error") return "Keyring access failed. Check logs (journalctl --user -f)."
                    return "Right-click → Configure Widget"
                }
                opacity: 0.7
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 320
            }

            Item { Layout.fillHeight: true }
        }

        // Loading indicator (only on initial load)
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: loading ? 50 : 0
            visible: loading

            PlasmaComponents.BusyIndicator {
                anchors.centerIn: parent
                running: loading
            }
        }

        function friendlyErrorHint(msg) {
            msg = msg || ""
            var m = msg.toLowerCase()

            if (m.indexOf("authentication failed") !== -1 || m.indexOf("http 401") !== -1 || m.indexOf("http 403") !== -1) {
                return "Check API Token ID/Secret and that the token has Sys.Audit + VM.Audit permissions."
            }
            if (m.indexOf("ssl") !== -1 || m.indexOf("tls") !== -1 || m.indexOf("certificate") !== -1) {
                return "SSL/TLS error. If you use a self-signed cert, enable “Ignore SSL certificate errors”."
            }
            if (m.indexOf("timed out") !== -1 || m.indexOf("timeout") !== -1) {
                return "Request timed out. Check host/port reachability, firewall, and DNS."
            }
            if (m.indexOf("not configured") !== -1) {
                return "Open the widget settings and enter Host + Token ID + Token Secret."
            }
            return ""
        }

        // Error message
        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: 10
            visible: errorMessage !== "" && configured
            spacing: 8

            RowLayout {
                spacing: 8
                Layout.alignment: Qt.AlignHCenter

                Kirigami.Icon {
                    source: "dialog-error"
                    implicitWidth: 22
                    implicitHeight: 22
                }

                PlasmaComponents.Label {
                    text: "Connection Error"
                    font.bold: true
                    color: Kirigami.Theme.negativeTextColor
                }
            }

            PlasmaComponents.Label {
                text: errorMessage
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            PlasmaComponents.Label {
                text: friendlyErrorHint(errorMessage)
                visible: text !== ""
                opacity: 0.85
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            PlasmaComponents.Label {
                text: retryStatusText
                visible: retryStatusText !== ""
                opacity: 0.85
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            PlasmaComponents.Label {
                text: armedLabel
                visible: armedLabel !== ""
                opacity: 0.9
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            PlasmaComponents.Label {
                text: actionPermHint
                visible: actionPermHintShown && actionPermHint !== ""
                opacity: 0.9
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            PlasmaComponents.Button {
                text: "Retry"
                icon.name: "view-refresh"
                Layout.alignment: Qt.AlignHCenter
                onClicked: fetchData()
            }
        }

        // Scrollable Main Content
        QQC2.ScrollView {
            id: scrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            visible: configured && !loading && errorMessage === ""
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

                    delegate: ColumnLayout {
                        id: nodeDelegate
                        Layout.fillWidth: true
                        spacing: 4

                        // Per Qt docs, Repeater delegates get `index` and (for array/object-list models) `modelData`.
                        // Plasma should follow this; using captured outer arrays can lead to all delegates showing the same element.
                        required property int index
                        required property var modelData

                        readonly property int nodeIndex: index
                        readonly property var nodeModel: modelData

                        property string nodeName: nodeModel ? nodeModel.node : ""
                        property var nodeVms: getVmsForNode(nodeName)
                        property var nodeLxc: getLxcForNode(nodeName)
                        property bool isCollapsed: isNodeCollapsed(nodeName)

                        // Force relayout on collapse/expand (prevents footer "float" glitches)
                        onIsCollapsedChanged: {
                            scrollView.forceLayout()
                            fullRep.forceLayout()
                        }

                        // Node card
                        Rectangle {
                            Layout.fillWidth: true
                            // Keep scrollbar gutter + align with VM/CT rows
                            Layout.leftMargin: 12
                            Layout.rightMargin: scrollView.__scrollbarReserve
                            Layout.preferredHeight: 70
                            radius: 6
                            color: Kirigami.Theme.backgroundColor
                            border.color: Kirigami.Theme.disabledTextColor
                            border.width: 1

                            MouseArea {
                                anchors.fill: parent
                                onClicked: toggleNodeCollapsed(nodeName)
                                cursorShape: Qt.PointingHandCursor
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 4

                                RowLayout {
                                    spacing: 8

                                    Kirigami.Icon {
                                        source: isCollapsed ? "arrow-right" : "arrow-down"
                                        implicitWidth: 14
                                        implicitHeight: 14
                                    }

                                    Kirigami.Icon {
                                        source: "computer"
                                        implicitWidth: 18
                                        implicitHeight: 18
                                    }

                                    PlasmaComponents.Label {
                                        text: anonymizeNodeName(nodeModel.node, nodeIndex)
                                        font.bold: true
                                    }

                                    Rectangle {
                                        implicitWidth: 52
                                        implicitHeight: 16
                                        radius: 8
                                        color: nodeModel.status === "online" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor

                                        PlasmaComponents.Label {
                                            anchors.centerIn: parent
                                            text: nodeModel.status
                                            color: "white"
                                            font.pixelSize: 9
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Collapsed summary
                                    RowLayout {
                                        spacing: 4
                                        visible: isCollapsed

                                        Kirigami.Icon {
                                            source: "computer-symbolic"
                                            implicitWidth: 12
                                            implicitHeight: 12
                                            opacity: 0.7
                                        }

                                        PlasmaComponents.Label {
                                            text: getRunningVmsForNode(nodeName) + "/" + getTotalVmsForNode(nodeName)
                                            font.pixelSize: 10
                                            opacity: 0.7
                                        }

                                        Item { implicitWidth: 4 }

                                        Kirigami.Icon {
                                            source: "lxc"
                                            implicitWidth: 12
                                            implicitHeight: 12
                                            opacity: 0.7
                                        }

                                        PlasmaComponents.Label {
                                            text: getRunningLxcForNode(nodeName) + "/" + getTotalLxcForNode(nodeName)
                                            font.pixelSize: 10
                                            opacity: 0.7
                                        }
                                    }
                                }

                                RowLayout {
                                    spacing: 12

                                    PlasmaComponents.Label {
                                        text: "CPU: " + safeCpuPercent(nodeModel.cpu).toFixed(1) + "%"
                                        font.pixelSize: 12
                                    }

                                    PlasmaComponents.Label {
                                        text: "Mem: " + (nodeModel.mem / 1073741824).toFixed(1) + "/" + (nodeModel.maxmem / 1073741824).toFixed(1) + "G"
                                        font.pixelSize: 12
                                    }

                                    Item { Layout.fillWidth: true }

                                    PlasmaComponents.Label {
                                        text: Math.floor(nodeModel.uptime / 86400) + "d " + Math.floor((nodeModel.uptime % 86400) / 3600) + "h"
                                        font.pixelSize: 11
                                        opacity: 0.7
                                    }
                                }
                            }
                        }

                        // Expanded content (VMs and LXCs)
                        ColumnLayout {
                            Layout.fillWidth: true
                            // Match node card edges
                            Layout.leftMargin: 12
                            Layout.rightMargin: scrollView.__scrollbarReserve
                            visible: !isCollapsed
                            spacing: 4

                            // VMs section
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: nodeVms.length > 0
                                spacing: 2

                                RowLayout {
                                    Layout.preferredHeight: 22
                                    spacing: 6

                                    Kirigami.Icon {
                                        source: "computer-symbolic"
                                        implicitWidth: 14
                                        implicitHeight: 14
                                    }

                                    PlasmaComponents.Label {
                                        text: "VMs (" + getRunningVmsForNode(nodeName) + "/" + nodeVms.length + ")"
                                        font.bold: true
                                        font.pixelSize: 11
                                    }
                                }

                                Repeater {
                                    model: nodeVms

                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 28
                                        radius: 4

                                        required property int index
                                        required property var modelData

                                        readonly property int vmIndex: index
                                        readonly property var vmModel: modelData

                                        color: vmModel && vmModel.status === "running"
                                            ? Qt.rgba(Kirigami.Theme.positiveTextColor.r, Kirigami.Theme.positiveTextColor.g, Kirigami.Theme.positiveTextColor.b, 0.15)
                                            : Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, 0.1)

                                        property bool busy: vmModel ? isActionBusy(nodeName, "qemu", vmModel.vmid) : false

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 6

                                            Rectangle {
                                                implicitWidth: 8
                                                implicitHeight: 8
                                                radius: 4
                                                color: vmModel && vmModel.status === "running" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                                            }

                                            PlasmaComponents.Label {
                                                text: vmModel
                                                    ? (anonymizeVmId(vmModel.vmid, vmIndex) + ": " + anonymizeVmName(vmModel.name, vmIndex))
                                                    : ""
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                font.pixelSize: 11
                                            }

                                            Item { Layout.fillWidth: true }

                                            // Fixed-width stats group: keep CPU|Mem adjacent but align "|" and values across rows
                                            // (CPU/Mem labels are fixed-width; the displayed text stays adjacent because widths are tight)
                                            RowLayout {
                                                // Tighter CPU|Mem grouping (still aligned across rows)
                                                // Keep CPU and Mem the same width.
                                                Layout.preferredWidth: 68
                                                Layout.minimumWidth: 68
                                                Layout.maximumWidth: 68
                                                Layout.alignment: Qt.AlignVCenter
                                                spacing: 1

                                                PlasmaComponents.Label {
                                                    text: vmModel
                                                        ? (vmModel.status === "running"
                                                           ? (vmModel.cpu * 100).toFixed(0) + "%"
                                                           : vmModel.status)
                                                        : ""
                                                    font.pixelSize: 10
                                                    opacity: 0.7
                                                    horizontalAlignment: Text.AlignRight
                                                    Layout.preferredWidth: 32
                                                    Layout.minimumWidth: 32
                                                    Layout.maximumWidth: 32
                                                }

                                                PlasmaComponents.Label {
                                                    text: vmModel && vmModel.status === "running" ? "|" : ""
                                                    font.pixelSize: 10
                                                    opacity: 0.7
                                                    horizontalAlignment: Text.AlignHCenter
                                                    Layout.preferredWidth: 4
                                                    Layout.minimumWidth: 4
                                                    Layout.maximumWidth: 4
                                                    Layout.leftMargin: 2
                                                    Layout.rightMargin: 2
                                                }

                                                PlasmaComponents.Label {
                                                    text: vmModel && vmModel.status === "running"
                                                        ? (vmModel.mem / 1073741824).toFixed(1) + "G"
                                                        : ""
                                                    font.pixelSize: 10
                                                    opacity: 0.7
                                                    horizontalAlignment: Text.AlignLeft
                                                    Layout.preferredWidth: 32
                                                    Layout.minimumWidth: 32
                                                    Layout.maximumWidth: 32
                                                    Layout.leftMargin: 2
                                                }
                                            }

                                            // Fixed-width actions strip pinned to the far right.
                                            // Use ToolButtons (icon-only) + tooltips + subtle hover background.
                                            // NOTE: ScrollView has an overlay scrollbar; reserve right gutter below so it won't cover these buttons.
                                            RowLayout {
                                                spacing: PlasmaCore.Units.smallSpacing
                                                Layout.preferredWidth: 70
                                                Layout.minimumWidth: 70
                                                Layout.maximumWidth: 70
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                                Layout.preferredHeight: 28
                                                Layout.minimumHeight: 28
                                                Layout.maximumHeight: 28

                                                PlasmaComponents.BusyIndicator {
                                                    visible: busy
                                                    running: busy
                                                    implicitWidth: 16
                                                    implicitHeight: 16
                                                }

                                                PlasmaComponents.ToolButton {
                                                    flat: true
                                                    icon.name: (armedActionKey === ("qemu:" + nodeName + ":" + vmModel.vmid + ":start") && armedTimer.running)
                                                        ? "dialog-ok"
                                                        : "media-playback-start"
                                                    implicitWidth: 22
                                                    implicitHeight: 22
                                                    visible: vmModel && !busy && vmModel.status !== "running"

                                                    PlasmaComponents.ToolTip {
                                                        text: "Start"
                                                    }

                                                    background: Rectangle {
                                                        radius: 4
                                                        color: parent.hovered
                                                            ? Qt.rgba(PlasmaCore.Theme.highlightColor.r, PlasmaCore.Theme.highlightColor.g, PlasmaCore.Theme.highlightColor.b, 0.18)
                                                            : "transparent"
                                                    }

                                                    onClicked: confirmAndRunAction("qemu", nodeName, vmModel.vmid, vmModel.name, "start")
                                                }
                                                Item { implicitWidth: 22; implicitHeight: 22; visible: !vmModel || busy || vmModel.status === "running" }

                                                PlasmaComponents.ToolButton {
                                                    flat: true
                                                    icon.name: (armedActionKey === ("qemu:" + nodeName + ":" + vmModel.vmid + ":shutdown") && armedTimer.running)
                                                        ? "dialog-ok"
                                                        : "system-shutdown"
                                                    implicitWidth: 22
                                                    implicitHeight: 22
                                                    visible: vmModel && !busy && vmModel.status === "running"

                                                    PlasmaComponents.ToolTip {
                                                        text: "Shutdown"
                                                    }

                                                    background: Rectangle {
                                                        radius: 4
                                                        color: parent.hovered
                                                            ? Qt.rgba(PlasmaCore.Theme.highlightColor.r, PlasmaCore.Theme.highlightColor.g, PlasmaCore.Theme.highlightColor.b, 0.18)
                                                            : "transparent"
                                                    }

                                                    onClicked: confirmAndRunAction("qemu", nodeName, vmModel.vmid, vmModel.name, "shutdown")
                                                }
                                                Item { implicitWidth: 22; implicitHeight: 22; visible: !vmModel || busy || vmModel.status !== "running" }

                                                PlasmaComponents.ToolButton {
                                                    flat: true
                                                    icon.name: (armedActionKey === ("qemu:" + nodeName + ":" + vmModel.vmid + ":reboot") && armedTimer.running)
                                                        ? "dialog-ok"
                                                        : "system-reboot"
                                                    implicitWidth: 22
                                                    implicitHeight: 22
                                                    visible: vmModel && !busy && vmModel.status === "running"

                                                    PlasmaComponents.ToolTip {
                                                        text: "Reboot"
                                                    }

                                                    background: Rectangle {
                                                        radius: 4
                                                        color: parent.hovered
                                                            ? Qt.rgba(PlasmaCore.Theme.highlightColor.r, PlasmaCore.Theme.highlightColor.g, PlasmaCore.Theme.highlightColor.b, 0.18)
                                                            : "transparent"
                                                    }

                                                    onClicked: confirmAndRunAction("qemu", nodeName, vmModel.vmid, vmModel.name, "reboot")
                                                }
                                                Item { implicitWidth: 22; implicitHeight: 22; visible: !vmModel || busy || vmModel.status !== "running" }
                                            }

                                            // Reserve space so overlay scrollbar doesn't cover action buttons.
                                            // Since buttons are pinned to far right, this MUST exist to keep them clickable.
                                            Item {
                                                Layout.preferredWidth: scrollView.__scrollbarReserve
                                                Layout.minimumWidth: scrollView.__scrollbarReserve
                                            }
                                        }
                                    }
                                }
                            }

                            // LXC section
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: nodeLxc.length > 0
                                spacing: 2

                                RowLayout {
                                    Layout.preferredHeight: 22
                                    spacing: 6

                                    Kirigami.Icon {
                                        source: "lxc"
                                        implicitWidth: 14
                                        implicitHeight: 14
                                    }

                                    PlasmaComponents.Label {
                                        text: "Containers (" + getRunningLxcForNode(nodeName) + "/" + nodeLxc.length + ")"
                                        font.bold: true
                                        font.pixelSize: 11
                                    }
                                }

                                Repeater {
                                    model: nodeLxc

                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 28
                                        radius: 4

                                        required property int index
                                        required property var modelData

                                        readonly property int ctIndex: index
                                        readonly property var ctModel: modelData

                                        color: ctModel && ctModel.status === "running"
                                            ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
                                            : Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, 0.1)

                                        property bool busy: ctModel ? isActionBusy(nodeName, "lxc", ctModel.vmid) : false

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 6

                                            Rectangle {
                                                implicitWidth: 8
                                                implicitHeight: 8
                                                radius: 4
                                                color: ctModel && ctModel.status === "running" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                                            }

                                            PlasmaComponents.Label {
                                                text: ctModel
                                                    ? (anonymizeVmId(ctModel.vmid, ctIndex) + ": " + anonymizeLxcName(ctModel.name, ctIndex))
                                                    : ""
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                font.pixelSize: 11
                                            }

                                            Item { Layout.fillWidth: true }

                                            // Fixed-width stats group: keep CPU|Mem adjacent but align "|" and values across rows
                                            // (CPU/Mem labels are fixed-width; the displayed text stays adjacent because widths are tight)
                                            RowLayout {
                                                // Tighter CPU|Mem grouping (still aligned across rows)
                                                // Keep CPU and Mem the same width.
                                                Layout.preferredWidth: 68
                                                Layout.minimumWidth: 68
                                                Layout.maximumWidth: 68
                                                Layout.alignment: Qt.AlignVCenter
                                                spacing: 1

                                                PlasmaComponents.Label {
                                                    text: ctModel
                                                        ? (ctModel.status === "running"
                                                           ? (ctModel.cpu * 100).toFixed(0) + "%"
                                                           : ctModel.status)
                                                        : ""
                                                    font.pixelSize: 10
                                                    opacity: 0.7
                                                    horizontalAlignment: Text.AlignRight
                                                    Layout.preferredWidth: 32
                                                    Layout.minimumWidth: 32
                                                    Layout.maximumWidth: 32
                                                }

                                                PlasmaComponents.Label {
                                                    text: ctModel && ctModel.status === "running" ? "|" : ""
                                                    font.pixelSize: 10
                                                    opacity: 0.7
                                                    horizontalAlignment: Text.AlignHCenter
                                                    Layout.preferredWidth: 4
                                                    Layout.minimumWidth: 4
                                                    Layout.maximumWidth: 4
                                                    Layout.leftMargin: 2
                                                    Layout.rightMargin: 2
                                                }

                                                PlasmaComponents.Label {
                                                    text: ctModel && ctModel.status === "running"
                                                        ? (ctModel.mem / 1073741824).toFixed(1) + "G"
                                                        : ""
                                                    font.pixelSize: 10
                                                    opacity: 0.7
                                                    horizontalAlignment: Text.AlignLeft
                                                    Layout.preferredWidth: 32
                                                    Layout.minimumWidth: 32
                                                    Layout.maximumWidth: 32
                                                    Layout.leftMargin: 2
                                                }
                                            }

                                            // Fixed-width actions strip pinned to the far right.
                                            // Use ToolButtons (icon-only) + tooltips + subtle hover background.
                                            // NOTE: ScrollView has an overlay scrollbar; reserve right gutter below so it won't cover these buttons.
                                            RowLayout {
                                                spacing: PlasmaCore.Units.smallSpacing
                                                Layout.preferredWidth: 70
                                                Layout.minimumWidth: 70
                                                Layout.maximumWidth: 70
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                                Layout.preferredHeight: 28
                                                Layout.minimumHeight: 28
                                                Layout.maximumHeight: 28

                                                PlasmaComponents.BusyIndicator {
                                                    visible: busy
                                                    running: busy
                                                    implicitWidth: 16
                                                    implicitHeight: 16
                                                }

                                                PlasmaComponents.ToolButton {
                                                    flat: true
                                                    icon.name: (armedActionKey === ("lxc:" + nodeName + ":" + ctModel.vmid + ":start") && armedTimer.running)
                                                        ? "dialog-ok"
                                                        : "media-playback-start"
                                                    implicitWidth: 22
                                                    implicitHeight: 22
                                                    visible: ctModel && !busy && ctModel.status !== "running"

                                                    PlasmaComponents.ToolTip {
                                                        text: "Start"
                                                    }

                                                    background: Rectangle {
                                                        radius: 4
                                                        color: parent.hovered
                                                            ? Qt.rgba(PlasmaCore.Theme.highlightColor.r, PlasmaCore.Theme.highlightColor.g, PlasmaCore.Theme.highlightColor.b, 0.18)
                                                            : "transparent"
                                                    }

                                                    onClicked: confirmAndRunAction("lxc", nodeName, ctModel.vmid, ctModel.name, "start")
                                                }
                                                Item { implicitWidth: 22; implicitHeight: 22; visible: !ctModel || busy || ctModel.status === "running" }

                                                PlasmaComponents.ToolButton {
                                                    flat: true
                                                    icon.name: (armedActionKey === ("lxc:" + nodeName + ":" + ctModel.vmid + ":shutdown") && armedTimer.running)
                                                        ? "dialog-ok"
                                                        : "system-shutdown"
                                                    implicitWidth: 22
                                                    implicitHeight: 22
                                                    visible: ctModel && !busy && ctModel.status === "running"

                                                    PlasmaComponents.ToolTip {
                                                        text: "Shutdown"
                                                    }

                                                    background: Rectangle {
                                                        radius: 4
                                                        color: parent.hovered
                                                            ? Qt.rgba(PlasmaCore.Theme.highlightColor.r, PlasmaCore.Theme.highlightColor.g, PlasmaCore.Theme.highlightColor.b, 0.18)
                                                            : "transparent"
                                                    }

                                                    onClicked: confirmAndRunAction("lxc", nodeName, ctModel.vmid, ctModel.name, "shutdown")
                                                }
                                                Item { implicitWidth: 22; implicitHeight: 22; visible: !ctModel || busy || ctModel.status !== "running" }

                                                PlasmaComponents.ToolButton {
                                                    flat: true
                                                    icon.name: (armedActionKey === ("lxc:" + nodeName + ":" + ctModel.vmid + ":reboot") && armedTimer.running)
                                                        ? "dialog-ok"
                                                        : "system-reboot"
                                                    implicitWidth: 22
                                                    implicitHeight: 22
                                                    visible: ctModel && !busy && ctModel.status === "running"

                                                    PlasmaComponents.ToolTip {
                                                        text: "Reboot"
                                                    }

                                                    background: Rectangle {
                                                        radius: 4
                                                        color: parent.hovered
                                                            ? Qt.rgba(PlasmaCore.Theme.highlightColor.r, PlasmaCore.Theme.highlightColor.g, PlasmaCore.Theme.highlightColor.b, 0.18)
                                                            : "transparent"
                                                    }

                                                    onClicked: confirmAndRunAction("lxc", nodeName, ctModel.vmid, ctModel.name, "reboot")
                                                }
                                                Item { implicitWidth: 22; implicitHeight: 22; visible: !ctModel || busy || ctModel.status !== "running" }
                                            }

                                            // Keep the row background aligned with node cards, but reserve space on the
                                            // far right so the overlay scrollbar doesn't cover the action buttons.
                                            Item {
                                                Layout.preferredWidth: scrollView.__scrollbarReserve
                                                Layout.minimumWidth: scrollView.__scrollbarReserve
                                            }
                                        }
                                    }
                                }
                            }

                            // Empty state
                            PlasmaComponents.Label {
                                text: "No VMs or Containers"
                                visible: nodeVms.length === 0 && nodeLxc.length === 0
                                opacity: 0.5
                                font.pixelSize: 10
                                Layout.leftMargin: 4
                            }
                        }

                        // Node separator
                        Rectangle {
                            Layout.fillWidth: true
                            // Keep a gutter so the separator line doesn't run under the overlay scrollbar
                            Layout.rightMargin: scrollView.__scrollbarReserve
                            Layout.preferredHeight: 1
                            color: Kirigami.Theme.disabledTextColor
                            opacity: 0.3
                            visible: nodeIndex < (root.displayedProxmoxData.data.length - 1)
                            Layout.topMargin: 4
                        }
                    }
                }

                // Multi-host view (group by endpoint)
                Repeater {
                    visible: connectionMode === "multiHost"
                    model: displayedEndpoints

                    delegate: ColumnLayout {
                        id: endpointDelegate
                        Layout.fillWidth: true
                        spacing: 8

                        required property int index
                        required property var modelData

                        readonly property var endpoint: modelData
                        readonly property string sessionKey: endpoint ? endpoint.sessionKey : ""
                        readonly property string endpointLabel: endpoint && endpoint.label ? endpoint.label : (endpoint ? endpoint.host : "")
                        readonly property var nodes: endpoint && endpoint.nodes ? endpoint.nodes : []

                        Rectangle {
                            Layout.fillWidth: true
                            // Keep a gutter so the right border doesn't sit under the overlay scrollbar
                            Layout.rightMargin: scrollView.__scrollbarReserve
                            Layout.preferredHeight: 34
                            radius: 6
                            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.12)
                            border.color: Kirigami.Theme.disabledTextColor
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                Kirigami.Icon {
                                    source: "server-database"
                                    implicitWidth: 16
                                    implicitHeight: 16
                                    opacity: 0.7
                                }

                                PlasmaComponents.Label {
                                    text: endpointLabel
                                    font.bold: true
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                PlasmaComponents.Label {
                                    text: endpoint ? (endpoint.host + ":" + endpoint.port) : ""
                                    opacity: 0.7
                                    font.pixelSize: 10
                                }
                            }
                        }

                        Repeater {
                            model: nodes

                            delegate: ColumnLayout {
                                id: multiNodeDelegate
                                Layout.fillWidth: true
                                spacing: 4

                                required property int index
                                required property var modelData

                                readonly property var nodeModel: modelData
                                readonly property string nodeName: nodeModel ? nodeModel.node : ""
                                readonly property var nodeVms: getVmsForNodeMulti(sessionKey, nodeName)
                                readonly property var nodeLxc: getLxcForNodeMulti(sessionKey, nodeName)
                                property bool isCollapsed: isNodeCollapsed(nodeName, sessionKey)

                                onIsCollapsedChanged: {
                                    scrollView.forceLayout()
                                    fullRep.forceLayout()
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 70
                                    radius: 6
                                    color: Kirigami.Theme.backgroundColor
                                    border.color: Kirigami.Theme.disabledTextColor
                                    border.width: 1

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: toggleNodeCollapsed(nodeName, sessionKey)
                                        cursorShape: Qt.PointingHandCursor
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 4

                                        RowLayout {
                                            spacing: 8

                                            Kirigami.Icon {
                                                source: isCollapsed ? "arrow-right" : "arrow-down"
                                                implicitWidth: 14
                                                implicitHeight: 14
                                            }

                                            Kirigami.Icon {
                                                source: "computer"
                                                implicitWidth: 18
                                                implicitHeight: 18
                                            }

                                            PlasmaComponents.Label {
                                                text: anonymizeNodeName(nodeName, index)
                                                font.bold: true
                                            }

                                            Rectangle {
                                                implicitWidth: 52
                                                implicitHeight: 16
                                                radius: 8
                                                color: nodeModel && nodeModel.status === "online" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor

                                                PlasmaComponents.Label {
                                                    anchors.centerIn: parent
                                                    text: nodeModel ? nodeModel.status : ""
                                                    color: "white"
                                                    font.pixelSize: 9
                                                }
                                            }

                                            Item { Layout.fillWidth: true }

                                            RowLayout {
                                                spacing: 4
                                                visible: isCollapsed

                                                Kirigami.Icon {
                                                    source: "computer-symbolic"
                                                    implicitWidth: 12
                                                    implicitHeight: 12
                                                    opacity: 0.7
                                                }

                                                PlasmaComponents.Label {
                                                    text: getRunningVmsForNodeMulti(sessionKey, nodeName) + "/" + getTotalVmsForNodeMulti(sessionKey, nodeName)
                                                    font.pixelSize: 10
                                                    opacity: 0.7
                                                }

                                                Item { implicitWidth: 4 }

                                                Kirigami.Icon {
                                                    source: "lxc"
                                                    implicitWidth: 12
                                                    implicitHeight: 12
                                                    opacity: 0.7
                                                }

                                                PlasmaComponents.Label {
                                                    text: getRunningLxcForNodeMulti(sessionKey, nodeName) + "/" + getTotalLxcForNodeMulti(sessionKey, nodeName)
                                                    font.pixelSize: 10
                                                    opacity: 0.7
                                                }
                                            }
                                        }

                                        RowLayout {
                                            spacing: 12

                                            PlasmaComponents.Label {
                                                text: nodeModel ? ("CPU: " + safeCpuPercent(nodeModel.cpu).toFixed(1) + "%") : ""
                                                font.pixelSize: 12
                                            }

                                            PlasmaComponents.Label {
                                                text: nodeModel ? ("Mem: " + (nodeModel.mem / 1073741824).toFixed(1) + "/" + (nodeModel.maxmem / 1073741824).toFixed(1) + "G") : ""
                                                font.pixelSize: 12
                                            }

                                            Item { Layout.fillWidth: true }

                                            PlasmaComponents.Label {
                                                text: nodeModel ? (Math.floor(nodeModel.uptime / 86400) + "d " + Math.floor((nodeModel.uptime % 86400) / 3600) + "h") : ""
                                                font.pixelSize: 11
                                                opacity: 0.7
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 12
                                    visible: !isCollapsed
                                    spacing: 4

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        visible: nodeVms.length > 0
                                        spacing: 2

                                        RowLayout {
                                            Layout.preferredHeight: 22
                                            spacing: 6

                                            Kirigami.Icon {
                                                source: "computer-symbolic"
                                                implicitWidth: 14
                                                implicitHeight: 14
                                            }

                                            PlasmaComponents.Label {
                                                text: "VMs (" + getRunningVmsForNodeMulti(sessionKey, nodeName) + "/" + nodeVms.length + ")"
                                                font.bold: true
                                                font.pixelSize: 11
                                            }
                                        }

                                        Repeater {
                                            model: nodeVms

                                            delegate: Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 28
                                                radius: 4

                                                required property int index
                                                required property var modelData

                                                readonly property var vmModel: modelData

                                                color: vmModel && vmModel.status === "running"
                                                    ? Qt.rgba(Kirigami.Theme.positiveTextColor.r, Kirigami.Theme.positiveTextColor.g, Kirigami.Theme.positiveTextColor.b, 0.15)
                                                    : Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, 0.1)

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    spacing: 6

                                                    Rectangle {
                                                        implicitWidth: 8
                                                        implicitHeight: 8
                                                        radius: 4
                                                        color: vmModel && vmModel.status === "running" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                                                    }

                                                    PlasmaComponents.Label {
                                                        text: vmModel ? (anonymizeVmId(vmModel.vmid, index) + ": " + anonymizeVmName(vmModel.name, index)) : ""
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                        font.pixelSize: 11
                                                    }

                                                    // Actions disabled in multi-host mode for now
                                                    PlasmaComponents.Label {
                                                        text: ""
                                                        Layout.preferredWidth: 70
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        visible: nodeLxc.length > 0
                                        spacing: 2

                                        RowLayout {
                                            Layout.preferredHeight: 22
                                            spacing: 6

                                            Kirigami.Icon {
                                                source: "lxc"
                                                implicitWidth: 14
                                                implicitHeight: 14
                                            }

                                            PlasmaComponents.Label {
                                                text: "Containers (" + getRunningLxcForNodeMulti(sessionKey, nodeName) + "/" + nodeLxc.length + ")"
                                                font.bold: true
                                                font.pixelSize: 11
                                            }
                                        }

                                        Repeater {
                                            model: nodeLxc

                                            delegate: Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 28
                                                radius: 4

                                                required property int index
                                                required property var modelData

                                                readonly property var ctModel: modelData

                                                color: ctModel && ctModel.status === "running"
                                                    ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
                                                    : Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, 0.1)

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    spacing: 6

                                                    Rectangle {
                                                        implicitWidth: 8
                                                        implicitHeight: 8
                                                        radius: 4
                                                        color: ctModel && ctModel.status === "running" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                                                    }

                                                    PlasmaComponents.Label {
                                                        text: ctModel ? (anonymizeVmId(ctModel.vmid, index) + ": " + anonymizeLxcName(ctModel.name, index)) : ""
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                        font.pixelSize: 11
                                                    }

                                                    // Actions disabled in multi-host mode for now
                                                    PlasmaComponents.Label {
                                                        text: ""
                                                        Layout.preferredWidth: 70
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    PlasmaComponents.Label {
                                        text: "No VMs or Containers"
                                        visible: nodeVms.length === 0 && nodeLxc.length === 0
                                        opacity: 0.5
                                        font.pixelSize: 10
                                        Layout.leftMargin: 4
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: Kirigami.Theme.disabledTextColor
                                    opacity: 0.3
                                    visible: index < (nodes.length - 1)
                                    Layout.topMargin: 4
                                }
                            }
                        }
                    }
                }

                // Empty state
                PlasmaComponents.Label {
                    text: "No nodes found"
                    visible: (connectionMode === "single")
                        ? (!displayedProxmoxData || !displayedProxmoxData.data || displayedProxmoxData.data.length === 0)
                        : (displayedEndpoints.length === 0)
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

        // Footer (keep it pinned to the bottom of the panel; prevent "floating" during ScrollView relayout)
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            Layout.topMargin: 4
            Layout.bottomMargin: 8
            Layout.preferredHeight: 24
            Layout.minimumHeight: 24
            Layout.maximumHeight: 24
            Layout.alignment: Qt.AlignBottom
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
