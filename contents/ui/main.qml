import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    // Connection properties
    property string proxmoxHost: Plasmoid.configuration.proxmoxHost || ""
    property int proxmoxPort: Plasmoid.configuration.proxmoxPort || 8006
    property string apiTokenId: Plasmoid.configuration.apiTokenId || ""
    property string apiTokenSecret: Plasmoid.configuration.apiTokenSecret || ""
    property int refreshInterval: (Plasmoid.configuration.refreshInterval || 30) * 1000
    property bool ignoreSsl: Plasmoid.configuration.ignoreSsl !== false
    property string defaultSorting: Plasmoid.configuration.defaultSorting || "status"

    // Notification properties
    property bool enableNotifications: Plasmoid.configuration.enableNotifications !== false
    property string notifyMode: Plasmoid.configuration.notifyMode || "all"
    property string notifyFilter: Plasmoid.configuration.notifyFilter || ""
    property bool notifyOnStop: Plasmoid.configuration.notifyOnStop !== false
    property bool notifyOnStart: Plasmoid.configuration.notifyOnStart !== false
    property bool notifyOnNodeChange: Plasmoid.configuration.notifyOnNodeChange !== false

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
    property bool configured: proxmoxHost !== "" && apiTokenSecret !== ""
    property bool defaultsLoaded: false
    property bool devMode: false
    property int footerClickCount: 0

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

    // Verbose logging function
    function logDebug(message) {
        if (devMode) {
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

    // Send desktop notification
    function sendNotification(title, message, iconName) {
        if (!enableNotifications) {
            logDebug("Notification suppressed (disabled): " + title + " - " + message)
            return
        }

        // Prevent newlines from breaking the shell command
        title = (title || "").replace(/[\r\n]+/g, " ")
        message = (message || "").replace(/[\r\n]+/g, " ")

        logDebug("Notification: " + title + " - " + message)

        var safeIcon = escapeShell(iconName || "proxmox-monitor")
        var safeTitle = escapeShell(title)
        var safeMessage = escapeShell(message)

        var notifyCmd = "notify-send -i '" + safeIcon + "' -a 'Proxmox Monitor' '" + safeTitle + "' '" + safeMessage + "'"
        executable.connectSource(notifyCmd)
    }

    // Test notifications function (dev mode)
    function testNotifications() {
        logDebug("Testing notifications...")
        sendNotification("VM Stopped", "test-vm (100) on pve1 is now stopped", "dialog-warning")
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
                            "dialog-error"
                        )
                    } else if (prevNodeState !== "online" && nodeData.status === "online") {
                        sendNotification(
                            "Node Online",
                            nodeData.node + " is back online",
                            "dialog-information"
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
                            "dialog-warning"
                        )
                    } else if (notifyOnStart && prevVmState !== "running" && vmItem.status === "running") {
                        sendNotification(
                            "VM Started",
                            vmItem.name + " (" + vmItem.vmid + ") on " + vmItem.node + " is now running",
                            "dialog-information"
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
                            "dialog-warning"
                        )
                    } else if (notifyOnStart && prevLxcState !== "running" && lxcItem.status === "running") {
                        sendNotification(
                            "Container Started",
                            lxcItem.name + " (" + lxcItem.vmid + ") on " + lxcItem.node + " is now running",
                            "dialog-information"
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

        return data.slice().sort(function(a, b) {
            switch (defaultSorting) {
                case "status":
                    var aRunning = (a.status === "running") ? 0 : 1
                    var bRunning = (b.status === "running") ? 0 : 1
                    if (aRunning !== bRunning) {
                        return aRunning - bRunning
                    }
                    return a.name.localeCompare(b.name)

                case "name":
                    return a.name.localeCompare(b.name)

                case "nameDesc":
                    return b.name.localeCompare(a.name)

                case "id":
                    return a.vmid - b.vmid

                case "idDesc":
                    return b.vmid - a.vmid

                default:
                    var aRun = (a.status === "running") ? 0 : 1
                    var bRun = (b.status === "running") ? 0 : 1
                    if (aRun !== bRun) return aRun - bRun
                    return a.name.localeCompare(b.name)
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

    function curlCmd(endpoint, seq) {
        var safeHost = escapeShell(proxmoxHost)
        var safeTokenId = escapeShell(apiTokenId)
        var safeTokenSecret = escapeShell(apiTokenSecret)
        var safeEndpoint = escapeShell(endpoint)
        var safeSeq = Number(seq || 0)

        // Note: the #seq=... suffix is only to tag DataSource "source" strings.
        // It is not part of the URL (because it's after the shell command).
        var cmd = "curl " + (ignoreSsl ? "-k " : "") +
            "-s --connect-timeout 10 'https://" + safeHost + ":" + proxmoxPort +
            "/api2/json" + safeEndpoint + "' -H 'Authorization: PVEAPIToken=" +
            safeTokenId + "=" + safeTokenSecret + "' #seq=" + safeSeq

        logDebug("curlCmd: " + endpoint + " (seq=" + safeSeq + ")")
        return cmd
    }

    // Sequencing for refreshes so we can ignore late responses from older refresh cycles
    property int refreshSeq: 0

    Timer {
        id: refreshWatchdog
        interval: 15000
        repeat: false
        onTriggered: {
            if (pendingNodeRequests > 0) {
                logDebug("refreshWatchdog: Timed out, pending requests: " + pendingNodeRequests)
                errorMessage = "Request timed out"
                pendingNodeRequests = 0
                isRefreshing = false
                loading = false
            }
        }
    }

    function fetchData() {
        if (!configured) {
            logDebug("fetchData: Not configured, skipping")
            return
        }

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
        executable.connectSource(curlCmd("/nodes", refreshSeq))
    }

    function fetchVMs(nodeName) {
        if (!nodeName) return
        logDebug("fetchVMs: Requesting VMs for node: " + nodeName)
        executable.connectSource(curlCmd("/nodes/" + nodeName + "/qemu", refreshSeq))
    }

    function fetchLXC(nodeName) {
        if (!nodeName) return
        logDebug("fetchLXC: Requesting LXCs for node: " + nodeName)
        executable.connectSource(curlCmd("/nodes/" + nodeName + "/lxc", refreshSeq))
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

    Component.onCompleted: {
        logDebug("Component.onCompleted: Plasmoid initialized")
        if (!configured) {
            logDebug("Component.onCompleted: Not configured, loading defaults")
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
                    if (s.tokenSecret) Plasmoid.configuration.apiTokenSecret = s.tokenSecret
                    if (s.refreshInterval) Plasmoid.configuration.refreshInterval = s.refreshInterval
                    if (s.ignoreSsl !== undefined) Plasmoid.configuration.ignoreSsl = s.ignoreSsl
                    if (s.enableNotifications !== undefined) Plasmoid.configuration.enableNotifications = s.enableNotifications

                    proxmoxHost = s.host || ""
                    proxmoxPort = s.port || 8006
                    apiTokenId = s.tokenId || ""
                    apiTokenSecret = s.tokenSecret || ""
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

    // DataSource for API calls
    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            var stdout = data["stdout"]
            var exitCode = data["exit code"]

            // Skip notification command responses
            if (source.indexOf("notify-send") !== -1) {
                disconnectSource(source)
                return
            }

            // Ignore late responses from older refresh cycles
            var seqMatch = source.match(/#seq=(\d+)/)
            var seq = seqMatch ? Number(seqMatch[1]) : 0
            if (seq !== refreshSeq) {
                logDebug("executable: Ignoring stale response (seq=" + seq + ", current=" + refreshSeq + ")")
                disconnectSource(source)
                return
            }

            logDebug("executable: Received response, exit code: " + exitCode)

            if (source.indexOf("/nodes\"") !== -1 || source.indexOf("/nodes'") !== -1) {
                logDebug("executable: Processing /nodes response")

                if (!displayedProxmoxData) {
                    loading = false
                }

                if (exitCode === 0 && stdout) {
                    try {
                        proxmoxData = JSON.parse(stdout)
                        errorMessage = ""
                        lastUpdate = Qt.formatDateTime(new Date(), "hh:mm:ss")

                        if (proxmoxData.data && proxmoxData.data.length > 0) {
                            logDebug("executable: Found " + proxmoxData.data.length + " nodes")

                            nodeList = proxmoxData.data.map(function(node) {
                                logDebug("executable: Node: " + node.node + " (status: " + node.status + ", cpu: " + (node.cpu * 100).toFixed(1) + "%)")
                                return node.node
                            })

                            tempVmData = []
                            tempLxcData = []
                            pendingNodeRequests = nodeList.length * 2

                            logDebug("executable: Starting " + pendingNodeRequests + " requests for VMs/LXCs")

                            for (var i = 0; i < nodeList.length; i++) {
                                fetchVMs(nodeList[i])
                                fetchLXC(nodeList[i])
                            }
                        } else {
                            logDebug("executable: No nodes found in response")
                            displayedProxmoxData = proxmoxData
                            displayedNodeList = []
                            displayedVmData = []
                            displayedLxcData = []
                            isRefreshing = false
                            loading = false
                        }
                    } catch (e) {
                        logDebug("executable: Parse error - " + e)
                        errorMessage = "Parse error"
                        isRefreshing = false
                        loading = false
                    }
                } else {
                    logDebug("executable: Request failed - " + (data["stderr"] || "Unknown error"))
                    errorMessage = data["stderr"] || "Connection failed"
                    isRefreshing = false
                    loading = false
                }
            } else if (source.indexOf("/qemu") !== -1) {
                var nodeNameQemu = getNodeFromSource(source)
                logDebug("executable: Processing /qemu response for node: " + nodeNameQemu)

                if (exitCode === 0 && stdout) {
                    try {
                        var resultQemu = JSON.parse(stdout)
                        if (resultQemu.data) {
                            logDebug("executable: Found " + resultQemu.data.length + " VMs on " + nodeNameQemu)

                            for (var j = 0; j < resultQemu.data.length; j++) {
                                resultQemu.data[j].node = nodeNameQemu
                                logDebug("executable: VM " + resultQemu.data[j].vmid + ": " + resultQemu.data[j].name + " (" + resultQemu.data[j].status + ")")
                                tempVmData.push(resultQemu.data[j])
                            }
                        }
                    } catch (e) {
                        logDebug("executable: VM parse error for " + nodeNameQemu + " - " + e)
                    }
                } else {
                    logDebug("executable: VM request failed for " + nodeNameQemu)
                }

                pendingNodeRequests--
                checkRequestsComplete()

            } else if (source.indexOf("/lxc") !== -1) {
                var nodeNameLxc = getNodeFromSource(source)
                logDebug("executable: Processing /lxc response for node: " + nodeNameLxc)

                if (exitCode === 0 && stdout) {
                    try {
                        var resultLxc = JSON.parse(stdout)
                        if (resultLxc.data) {
                            logDebug("executable: Found " + resultLxc.data.length + " LXCs on " + nodeNameLxc)

                            for (var k = 0; k < resultLxc.data.length; k++) {
                                resultLxc.data[k].node = nodeNameLxc
                                logDebug("executable: LXC " + resultLxc.data[k].vmid + ": " + resultLxc.data[k].name + " (" + resultLxc.data[k].status + ")")
                                tempLxcData.push(resultLxc.data[k])
                            }
                        }
                    } catch (e) {
                        logDebug("executable: LXC parse error for " + nodeNameLxc + " - " + e)
                    }
                } else {
                    logDebug("executable: LXC request failed for " + nodeNameLxc)
                }

                pendingNodeRequests--
                checkRequestsComplete()
            }

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
                    if (!configured) return "⚙"
                    if (loading) return "..."
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

        // Not configured message
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
                text: "Not Configured"
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            PlasmaComponents.Label {
                text: "Right-click → Configure Widget"
                opacity: 0.7
                Layout.alignment: Qt.AlignHCenter
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

                        property string nodeName: modelData.node
                        property var nodeVms: getVmsForNode(nodeName)
                        property var nodeLxc: getLxcForNode(nodeName)
                        property bool isCollapsed: isNodeCollapsed(nodeName)

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
                                        text: anonymizeNodeName(modelData.node, index)
                                        font.bold: true
                                    }

                                    Rectangle {
                                        width: 52
                                        height: 16
                                        radius: 8
                                        color: modelData.status === "online" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor

                                        PlasmaComponents.Label {
                                            anchors.centerIn: parent
                                            text: modelData.status
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

                                        Item { width: 4 }

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
                                        text: "CPU: " + (modelData.cpu * 100).toFixed(1) + "%"
                                        font.pixelSize: 12
                                    }

                                    PlasmaComponents.Label {
                                        text: "Mem: " + (modelData.mem / 1073741824).toFixed(1) + "/" + (modelData.maxmem / 1073741824).toFixed(1) + "G"
                                        font.pixelSize: 12
                                    }

                                    Item { Layout.fillWidth: true }

                                    PlasmaComponents.Label {
                                        text: Math.floor(modelData.uptime / 86400) + "d " + Math.floor((modelData.uptime % 86400) / 3600) + "h"
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
                                        color: modelData.status === "running"
                                            ? Qt.rgba(Kirigami.Theme.positiveTextColor.r, Kirigami.Theme.positiveTextColor.g, Kirigami.Theme.positiveTextColor.b, 0.15)
                                            : Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, 0.1)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 6

                                            Rectangle {
                                                width: 8
                                                height: 8
                                                radius: 4
                                                color: modelData.status === "running" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                                            }

                                            PlasmaComponents.Label {
                                                text: anonymizeVmId(modelData.vmid, index) + ": " + anonymizeVmName(modelData.name, index)
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                font.pixelSize: 11
                                            }

                                            PlasmaComponents.Label {
                                                text: modelData.status === "running"
                                                    ? (modelData.cpu * 100).toFixed(0) + "% | " + (modelData.mem / 1073741824).toFixed(1) + "G"
                                                    : modelData.status
                                                font.pixelSize: 10
                                                opacity: 0.7
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
                                        color: modelData.status === "running"
                                            ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
                                            : Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, 0.1)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 6

                                            Rectangle {
                                                width: 8
                                                height: 8
                                                radius: 4
                                                color: modelData.status === "running" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                                            }

                                            PlasmaComponents.Label {
                                                text: anonymizeVmId(modelData.vmid, index) + ": " + anonymizeLxcName(modelData.name, index)
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                font.pixelSize: 11
                                            }

                                            PlasmaComponents.Label {
                                                text: modelData.status === "running"
                                                    ? (modelData.cpu * 100).toFixed(0) + "% | " + (modelData.mem / 1073741824).toFixed(1) + "G"
                                                    : modelData.status
                                                font.pixelSize: 10
                                                opacity: 0.7
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
                            visible: index < (displayedProxmoxData.data.length - 1)
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

        // Footer
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            Layout.topMargin: 4
            Layout.bottomMargin: 8
            Layout.preferredHeight: 24
            visible: configured

            MouseArea {
                Layout.fillWidth: true
                Layout.fillHeight: true
                onClicked: handleFooterClick()

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
                        text: displayedNodeList.length + (displayedNodeList.length === 1 ? " node" : " nodes")
                        font.pixelSize: 10
                        opacity: 0.6
                    }

                    Item { width: 8 }

                    Kirigami.Icon {
                        source: "computer-symbolic"
                        implicitWidth: 12
                        implicitHeight: 12
                        opacity: 0.6
                    }

                    PlasmaComponents.Label {
                        text: runningVMs + "/" + displayedVmData.length
                        font.pixelSize: 10
                        opacity: 0.6
                    }

                    Item { width: 8 }

                    Kirigami.Icon {
                        source: "lxc"
                        implicitWidth: 12
                        implicitHeight: 12
                        opacity: 0.6
                    }

                    PlasmaComponents.Label {
                        text: runningLXC + "/" + displayedLxcData.length
                        font.pixelSize: 10
                        opacity: 0.6
                    }

                    Item { Layout.fillWidth: true }

                    PlasmaComponents.Label {
                        text: lastUpdate ? "Updated: " + lastUpdate : ""
                        font.pixelSize: 10
                        opacity: 0.6
                    }
                }
            }
        }
    }

    // ==================== REFRESH TIMER ====================

    Timer {
        interval: refreshInterval > 0 ? refreshInterval : 30000
        running: configured
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchData()
    }
}
