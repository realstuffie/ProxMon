pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "../lib/proxmox" as ProxMon

PlasmoidItem {
    id: root

    // Connection properties
    property string proxmoxHost: Plasmoid.configuration.proxmoxHost || ""
    property int proxmoxPort: Plasmoid.configuration.proxmoxPort || 8006
    property string apiTokenId: Plasmoid.configuration.apiTokenId || ""
    // Secret is stored in the system keyring via SecretStore (QtKeychain).
    // Keep Plasmoid.configuration.apiTokenSecret as a backward-compatible fallback only.
    property string apiTokenSecret: Plasmoid.configuration.apiTokenSecret || ""
    // Tracks keyring resolution state to avoid a "Not Configured" flicker while loading.
    // Values: "idle" | "loading" | "ready" | "missing" | "error"
    property string secretState: "idle"
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

    // Notification rate limiting (seconds)
    property bool notifyRateLimitEnabled: Plasmoid.configuration.notifyRateLimitEnabled !== false
    property int notifyRateLimitSeconds: Math.max(0, Plasmoid.configuration.notifyRateLimitSeconds || 120)
    // key => epoch ms
    property var notifyLastSent: ({})

    // Compact label mode: "cpu" (default), "running", "error", "lastUpdate"
    property string compactMode: Plasmoid.configuration.compactMode || "cpu"

    // Raw data (updated during fetch)
    property var proxmoxData: null
    property var vmData: []
    property var lxcData: []

    // Displayed data (only updated when all requests complete)
    property var displayedProxmoxData: null
    property var displayedVmData: []
    property var displayedLxcData: []

    // State properties
    property bool loading: false
    property bool isRefreshing: false
    property string errorMessage: ""
    property string lastUpdate: ""

    // One-time hint to guide users when action permissions are missing
    property bool actionPermHintShown: false
    property string actionPermHint: ""
    property bool hasCoreConfig: proxmoxHost !== "" && apiTokenId !== ""
    // "configured" means we have host+tokenId and the secret is ready (from keyring or migrated legacy config).
    property bool configured: hasCoreConfig && secretState === "ready" && apiTokenSecret !== ""
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

    /*
      NOTE (Qt Quick Controls 2 docs):
      - Popup is designed to be used with a Window/ApplicationWindow.
      - Overlay.overlay-based parenting assumes a compatible QQC2 overlay layer exists.
      In Plasma plasmoids, that overlay layer may not exist / may not stack correctly,
      so we avoid Popup/Dialog confirmations and use the two-click confirmation instead.
    */

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

    // Static timer for footer click detection (replaces dynamic timer creation)
    Timer {
        id: footerClickTimer
        interval: 1000
        onTriggered: footerClickCount = 0
    }

    // ==================== UTILITY FUNCTIONS ====================

        // Shell escape function to prevent command injection
        function escapeShell(str) {
            if (!str) return ""
            return str.replace(/'/g, "'\\''")
        }
 
        ProxMon.ProxmoxClient {
        id: api
        host: proxmoxHost
        port: proxmoxPort
        tokenId: apiTokenId
        tokenSecret: apiTokenSecret
        ignoreSslErrors: ignoreSsl

        onReply: function(seq, kind, node, data) {
            // Ignore late responses from older refresh cycles
            if (seq !== refreshSeq) return

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

            logDebug("api error: " + kind + " " + node + " - " + message)
            errorMessage = message || "Connection failed"
            pendingNodeRequests = 0
            isRefreshing = false
            loading = false

            scheduleRetry(errorMessage)
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

            if (devMode && upid) {
                console.log("[Proxmox] Action UPID: " + upid)
            }

            sendNotification(
                (actionKind === "qemu" ? "VM" : "Container") + " action",
                (actionKind === "qemu" ? "VM" : "CT") + " " + vmid + " " + action + " OK" + (upid ? (" (task " + upid + ")") : ""),
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


    // Verbose logging function
    // NOTE: For action debugging we always log (actions are non-secret). Use devMode to gate high-volume logs only.
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
        var text = buildDebugInfo()

        // Copy to clipboard via wl-copy/xclip. (No secrets included.)
        var cmd = "sh -lc " + "'" +
            "if command -v wl-copy >/dev/null 2>&1; then printf %s " + escapeShell(text) + " | wl-copy; " +
            "elif command -v xclip >/dev/null 2>&1; then printf %s " + escapeShell(text) + " | xclip -selection clipboard; " +
            "else exit 1; fi" +
            "'"

        executable.connectSource(cmd)
        sendNotification("Debug info copied", "Copied widget debug info to clipboard (no secrets).", "dialog-information")
    }

    // ==================== NOTIFICATION FUNCTIONS ====================

    // Escape regex special chars except "*" (handled as wildcard)
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

        logDebug("Notification: " + title + " - " + message)

        // Prefer system notification daemon via D-Bus (works on KDE, GNOME, etc).
        // If that fails, fallback to notify-send.
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

    // Get LXCs for a specific node (use displayed data)
    function getLxcForNode(nodeName) {
        var nodeLxc = displayedLxcData.filter(function(lxc) {
            return lxc.node === nodeName
        })
        return sortByStatus(nodeLxc)
    }

    // Get running VM count for a node (use displayed data)
    function getRunningVmsForNode(nodeName) {
        var count = 0
        for (var i = 0; i < displayedVmData.length; i++) {
            if (displayedVmData[i].node === nodeName && displayedVmData[i].status === "running") count++
        }
        return count
    }

    // Get running LXC count for a node (use displayed data)
    function getRunningLxcForNode(nodeName) {
        var count = 0
        for (var i = 0; i < displayedLxcData.length; i++) {
            if (displayedLxcData[i].node === nodeName && displayedLxcData[i].status === "running") count++
        }
        return count
    }

    // Get total VM count for a node (use displayed data)
    function getTotalVmsForNode(nodeName) {
        var count = 0
        for (var i = 0; i < displayedVmData.length; i++) {
            if (displayedVmData[i].node === nodeName) count++
        }
        return count
    }

    // Get total LXC count for a node (use displayed data)
    function getTotalLxcForNode(nodeName) {
        var count = 0
        for (var i = 0; i < displayedLxcData.length; i++) {
            if (displayedLxcData[i].node === nodeName) count++
        }
        return count
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
    function toggleNodeCollapsed(nodeName) {
        var newState = !isNodeCollapsed(nodeName)
        logDebug("toggleNodeCollapsed: " + nodeName + " -> " + (newState ? "collapsed" : "expanded"))
        var newCollapsed = Object.assign({}, collapsedNodes)
        newCollapsed[nodeName] = newState
        collapsedNodes = newCollapsed
    }

    // Check if node is collapsed
    function isNodeCollapsed(nodeName) {
        return collapsedNodes[nodeName] === true
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

    // Check if all node requests are complete - update displayed data atomically
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

    // NOTE: QQC2.Popup/Overlay-based confirmations do not render reliably in some Plasma widget environments.
    // We keep the code path as "two-click to confirm" instead (see confirmAndRunAction()).

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

    function fetchData() {
        if (!configured) {
            logDebug("fetchData: Not configured, skipping")
            return
        }

        // Stop any previous in-flight requests before starting a new refresh.
        api.cancelAll()

        refreshSeq++

        if (!displayedProxmoxData) {
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

        refreshWatchdog.restart()

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
        // key is set dynamically via startSecretReadCandidates()
        key: keyFor(proxmoxHost, proxmoxPort, apiTokenId)

        onSecretReady: function(secret) {
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
            secretState = "idle"
            return
        }
        // If we already have a secret from legacy config binding, consider it ready.
        // (We still attempt keyring read to migrate/ensure correct secret, but avoid UI flicker.)
        if (apiTokenSecret && apiTokenSecret.length > 0 && secretState !== "ready") {
            secretState = "ready"
        }
        if (secretState === "loading") return
        secretState = "loading"
        startSecretReadCandidates()
    }

    onProxmoxHostChanged: resolveSecretIfNeeded()
    onProxmoxPortChanged: resolveSecretIfNeeded()
    onApiTokenIdChanged: resolveSecretIfNeeded()

    Component.onCompleted: {
        logDebug("Component.onCompleted: Plasmoid initialized")
        resolveSecretIfNeeded()

        if (!hasCoreConfig) {
            logDebug("Component.onCompleted: Missing core config, loading defaults")
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
                    // Legacy: keep for migration; will be moved into keyring on first load.
                    if (s.tokenSecret) Plasmoid.configuration.apiTokenSecret = s.tokenSecret
                    if (s.refreshInterval) Plasmoid.configuration.refreshInterval = s.refreshInterval
                    if (s.ignoreSsl !== undefined) Plasmoid.configuration.ignoreSsl = s.ignoreSsl
                    if (s.enableNotifications !== undefined) Plasmoid.configuration.enableNotifications = s.enableNotifications

                    proxmoxHost = s.host || ""
                    proxmoxPort = s.port || 8006
                    apiTokenId = s.tokenId || ""
                    apiTokenSecret = s.tokenSecret || ""
                    if (apiTokenSecret && apiTokenSecret.length > 0) {
                        secretState = "ready"
                    }
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
                    // Distinguish states in compact mode to avoid confusing "Not configured" flicker.
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

            ColumnLayout {
                id: mainContentColumn
                width: scrollView.availableWidth
                spacing: 8

                Repeater {
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

                        // Force relayout when collapsing/expanding nodes so the footer doesn't "float" visually
                        // (ScrollView/ColumnLayout can otherwise keep a stale implicit height briefly).
                        onIsCollapsedChanged: {
                            scrollView.forceLayout()
                            fullRep.forceLayout()
                        }

                        // Node card
                        Rectangle {
                            Layout.fillWidth: true
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
                                        text: "CPU: " + (nodeModel.cpu * 100).toFixed(1) + "%"
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
                            Layout.leftMargin: 12
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

                                            // Fixed-width stats group: keep CPU|Mem adjacent but align "|" and values across rows
                                            // (CPU/Mem labels are fixed-width; the displayed text stays adjacent because widths are tight)
                                            RowLayout {
                                                // Tighter CPU|Mem grouping (still aligned across rows)
                                                Layout.preferredWidth: 62
                                                Layout.minimumWidth: 62
                                                Layout.maximumWidth: 62
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
                                                    Layout.preferredWidth: 24
                                                    Layout.minimumWidth: 24
                                                    Layout.maximumWidth: 24
                                                }

                                                PlasmaComponents.Label {
                                                    text: vmModel && vmModel.status === "running" ? "|" : ""
                                                    font.pixelSize: 10
                                                    opacity: 0.7
                                                    horizontalAlignment: Text.AlignHCenter
                                                    Layout.preferredWidth: 4
                                                    Layout.minimumWidth: 4
                                                    Layout.maximumWidth: 4
                                                }

                                                PlasmaComponents.Label {
                                                    text: vmModel && vmModel.status === "running"
                                                        ? (vmModel.mem / 1073741824).toFixed(1) + "G"
                                                        : ""
                                                    font.pixelSize: 10
                                                    opacity: 0.7
                                                    horizontalAlignment: Text.AlignRight
                                                    Layout.preferredWidth: 32
                                                    Layout.minimumWidth: 32
                                                    Layout.maximumWidth: 32
                                                }
                                            }

                                            // Fixed-width actions strip (moved to far right, after stats column)
                                            RowLayout {
                                                spacing: 2
                                                Layout.preferredWidth: 70
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredHeight: 28
                                                Layout.minimumHeight: 28
                                                Layout.maximumHeight: 28

                                                PlasmaComponents.BusyIndicator {
                                                    visible: busy
                                                    running: busy
                                                    implicitWidth: 16
                                                    implicitHeight: 16
                                                }

                                                PlasmaComponents.Button {
                                                    flat: true
                                                    icon.name: (armedActionKey === ("qemu:" + nodeName + ":" + vmModel.vmid + ":start") && armedTimer.running)
                                                        ? "dialog-ok"
                                                        : "media-playback-start"
                                                    implicitWidth: 22
                                                    implicitHeight: 22
                                                    visible: vmModel && !busy && vmModel.status !== "running"
                                                    onClicked: confirmAndRunAction("qemu", nodeName, vmModel.vmid, vmModel.name, "start")
                                                }
                                                Item { implicitWidth: 22; implicitHeight: 22; visible: !vmModel || busy || vmModel.status === "running" }

                                                PlasmaComponents.Button {
                                                    flat: true
                                                    icon.name: (armedActionKey === ("qemu:" + nodeName + ":" + vmModel.vmid + ":shutdown") && armedTimer.running)
                                                        ? "dialog-ok"
                                                        : "system-shutdown"
                                                    implicitWidth: 22
                                                    implicitHeight: 22
                                                    visible: vmModel && !busy && vmModel.status === "running"
                                                    onClicked: confirmAndRunAction("qemu", nodeName, vmModel.vmid, vmModel.name, "shutdown")
                                                }
                                                Item { implicitWidth: 22; implicitHeight: 22; visible: !vmModel || busy || vmModel.status !== "running" }

                                                PlasmaComponents.Button {
                                                    flat: true
                                                    icon.name: (armedActionKey === ("qemu:" + nodeName + ":" + vmModel.vmid + ":reboot") && armedTimer.running)
                                                        ? "dialog-ok"
                                                        : "system-reboot"
                                                    implicitWidth: 22
                                                    implicitHeight: 22
                                                    visible: vmModel && !busy && vmModel.status === "running"
                                                    onClicked: confirmAndRunAction("qemu", nodeName, vmModel.vmid, vmModel.name, "reboot")
                                                }
                                                Item { implicitWidth: 22; implicitHeight: 22; visible: !vmModel || busy || vmModel.status !== "running" }
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

                                            // Fixed-width stats group: keep CPU|Mem adjacent but align "|" and values across rows
                                            // (CPU/Mem labels are fixed-width; the displayed text stays adjacent because widths are tight)
                                            RowLayout {
                                                // Tighter CPU|Mem grouping (still aligned across rows)
                                                Layout.preferredWidth: 62
                                                Layout.minimumWidth: 62
                                                Layout.maximumWidth: 62
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
                                                    Layout.preferredWidth: 24
                                                    Layout.minimumWidth: 24
                                                    Layout.maximumWidth: 24
                                                }

                                                PlasmaComponents.Label {
                                                    text: ctModel && ctModel.status === "running" ? "|" : ""
                                                    font.pixelSize: 10
                                                    opacity: 0.7
                                                    horizontalAlignment: Text.AlignHCenter
                                                    Layout.preferredWidth: 4
                                                    Layout.minimumWidth: 4
                                                    Layout.maximumWidth: 4
                                                }

                                                PlasmaComponents.Label {
                                                    text: ctModel && ctModel.status === "running"
                                                        ? (ctModel.mem / 1073741824).toFixed(1) + "G"
                                                        : ""
                                                    font.pixelSize: 10
                                                    opacity: 0.7
                                                    horizontalAlignment: Text.AlignRight
                                                    Layout.preferredWidth: 32
                                                    Layout.minimumWidth: 32
                                                    Layout.maximumWidth: 32
                                                }
                                            }

                                            // Fixed-width actions strip (moved to far right, after stats column)
                                            RowLayout {
                                                spacing: 2
                                                Layout.preferredWidth: 70
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredHeight: 28
                                                Layout.minimumHeight: 28
                                                Layout.maximumHeight: 28

                                                PlasmaComponents.BusyIndicator {
                                                    visible: busy
                                                    running: busy
                                                    implicitWidth: 16
                                                    implicitHeight: 16
                                                }

                                                PlasmaComponents.Button {
                                                    flat: true
                                                    icon.name: (armedActionKey === ("lxc:" + nodeName + ":" + ctModel.vmid + ":start") && armedTimer.running)
                                                        ? "dialog-ok"
                                                        : "media-playback-start"
                                                    implicitWidth: 22
                                                    implicitHeight: 22
                                                    visible: ctModel && !busy && ctModel.status !== "running"
                                                    onClicked: confirmAndRunAction("lxc", nodeName, ctModel.vmid, ctModel.name, "start")
                                                }
                                                Item { implicitWidth: 22; implicitHeight: 22; visible: !ctModel || busy || ctModel.status === "running" }

                                                PlasmaComponents.Button {
                                                    flat: true
                                                    icon.name: (armedActionKey === ("lxc:" + nodeName + ":" + ctModel.vmid + ":shutdown") && armedTimer.running)
                                                        ? "dialog-ok"
                                                        : "system-shutdown"
                                                    implicitWidth: 22
                                                    implicitHeight: 22
                                                    visible: ctModel && !busy && ctModel.status === "running"
                                                    onClicked: confirmAndRunAction("lxc", nodeName, ctModel.vmid, ctModel.name, "shutdown")
                                                }
                                                Item { implicitWidth: 22; implicitHeight: 22; visible: !ctModel || busy || ctModel.status !== "running" }

                                                PlasmaComponents.Button {
                                                    flat: true
                                                    icon.name: (armedActionKey === ("lxc:" + nodeName + ":" + ctModel.vmid + ":reboot") && armedTimer.running)
                                                        ? "dialog-ok"
                                                        : "system-reboot"
                                                    implicitWidth: 22
                                                    implicitHeight: 22
                                                    visible: ctModel && !busy && ctModel.status === "running"
                                                    onClicked: confirmAndRunAction("lxc", nodeName, ctModel.vmid, ctModel.name, "reboot")
                                                }
                                                Item { implicitWidth: 22; implicitHeight: 22; visible: !ctModel || busy || ctModel.status !== "running" }
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
                            Layout.preferredHeight: 1
                            color: Kirigami.Theme.disabledTextColor
                            opacity: 0.3
                            visible: nodeIndex < (root.displayedProxmoxData.data.length - 1)
                            Layout.topMargin: 4
                        }
                    }
                }

                // Empty state
                PlasmaComponents.Label {
                    text: "No nodes found"
                    visible: !displayedProxmoxData || !displayedProxmoxData.data || displayedProxmoxData.data.length === 0
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
