import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root
    property string proxmoxHost: Plasmoid.configuration.proxmoxHost || ""
    property int proxmoxPort: Plasmoid.configuration.proxmoxPort || 8006
    property string apiTokenId: Plasmoid.configuration.apiTokenId || ""
    property string apiTokenSecret: Plasmoid.configuration.apiTokenSecret || ""
    property int refreshInterval: (Plasmoid.configuration.refreshInterval || 30) * 1000
    property bool ignoreSsl: Plasmoid.configuration.ignoreSsl !== false
    property string defaultSorting: Plasmoid.configuration.defaultSorting || "status"
    
    // Raw data (updated during fetch)
    property var proxmoxData: null
    property var vmData: []
    property var lxcData: []
    
    // Displayed data (only updated when all requests complete)
    property var displayedProxmoxData: null
    property var displayedVmData: []
    property var displayedLxcData: []
    
    property bool loading: false
    property bool isRefreshing: false
    property string errorMessage: ""
    property string lastUpdate: ""
    property bool configured: proxmoxHost !== "" && apiTokenSecret !== ""
    property bool defaultsLoaded: false
    property bool devMode: false
    property int footerClickCount: 0
    property var footerClickTimer: null

    // Multi-node support
    property var nodeList: []
    property var displayedNodeList: []
    property var pendingNodeRequests: 0
    property var tempVmData: []
    property var tempLxcData: []

    // Collapsed state tracking for nodes
    property var collapsedNodes: ({})

    // Anonymization data
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
        var newCollapsed = Object.assign({}, collapsedNodes)
        newCollapsed[nodeName] = newState
        collapsedNodes = newCollapsed
    }

    // Check if node is collapsed
    function isNodeCollapsed(nodeName) {
        return collapsedNodes[nodeName] === true
    }

    // Anonymization functions
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

    function handleFooterClick() {
        footerClickCount++
        if (footerClickCount >= 3) {
            devMode = !devMode
            footerClickCount = 0
            console.log("Developer mode: " + (devMode ? "ENABLED" : "DISABLED"))
        }
        if (footerClickTimer) footerClickTimer.destroy()
        footerClickTimer = Qt.createQmlObject('import QtQuick; Timer { interval: 1000; onTriggered: footerClickCount = 0 }', root)
        footerClickTimer.start()
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
        if (pendingNodeRequests <= 0) {
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
        }
    }

    Component.onCompleted: {
        if (!configured) {
            loadDefaults.connectSource("cat ~/.config/proxmox-plasmoid/settings.json 2>/dev/null")
        }
    }

    Plasma5Support.DataSource {
        id: loadDefaults
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            if (data["exit code"] === 0 && data["stdout"] && !defaultsLoaded) {
                try {
                    var s = JSON.parse(data["stdout"])
                    if (s.host) Plasmoid.configuration.proxmoxHost = s.host
                    if (s.port) Plasmoid.configuration.proxmoxPort = s.port
                    if (s.tokenId) Plasmoid.configuration.apiTokenId = s.tokenId
                    if (s.tokenSecret) Plasmoid.configuration.apiTokenSecret = s.tokenSecret
                    if (s.refreshInterval) Plasmoid.configuration.refreshInterval = s.refreshInterval
                    if (s.ignoreSsl !== undefined) Plasmoid.configuration.ignoreSsl = s.ignoreSsl
                    proxmoxHost = s.host || ""
                    proxmoxPort = s.port || 8006
                    apiTokenId = s.tokenId || ""
                    apiTokenSecret = s.tokenSecret || ""
                    refreshInterval = (s.refreshInterval || 30) * 1000
                    ignoreSsl = s.ignoreSsl !== false
                    defaultsLoaded = true
                } catch (e) {
                    console.log("No defaults found")
                }
            }
            disconnectSource(source)
        }
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            var stdout = data["stdout"]
            var exitCode = data["exit code"]

            if (source.indexOf("/nodes\"") !== -1 || source.indexOf("/nodes'") !== -1) {
                // Only set loading false on initial load, not refresh
                if (!displayedProxmoxData) {
                    loading = false
                }
                
                if (exitCode === 0 && stdout) {
                    try {
                        proxmoxData = JSON.parse(stdout)
                        errorMessage = ""
                        lastUpdate = Qt.formatDateTime(new Date(), "hh:mm:ss")

                        if (proxmoxData.data && proxmoxData.data.length > 0) {
                            nodeList = proxmoxData.data.map(function(node) {
                                return node.node
                            })

                            tempVmData = []
                            tempLxcData = []
                            pendingNodeRequests = nodeList.length * 2

                            for (var i = 0; i < nodeList.length; i++) {
                                fetchVMs(nodeList[i])
                                fetchLXC(nodeList[i])
                            }
                        } else {
                            // No nodes, update displayed data immediately
                            displayedProxmoxData = proxmoxData
                            displayedNodeList = []
                            displayedVmData = []
                            displayedLxcData = []
                            isRefreshing = false
                            loading = false
                        }
                    } catch (e) {
                        errorMessage = "Parse error"
                        isRefreshing = false
                        loading = false
                    }
                } else {
                    errorMessage = data["stderr"] || "Connection failed"
                    isRefreshing = false
                    loading = false
                }
            } else if (source.indexOf("/qemu") !== -1) {
                var nodeNameQemu = getNodeFromSource(source)
                if (exitCode === 0 && stdout) {
                    try {
                        var resultQemu = JSON.parse(stdout)
                        if (resultQemu.data) {
                            for (var j = 0; j < resultQemu.data.length; j++) {
                                resultQemu.data[j].node = nodeNameQemu
                                tempVmData.push(resultQemu.data[j])
                            }
                        }
                    } catch (e) {
                        console.log("VM parse error for node: " + nodeNameQemu)
                    }
                }
                pendingNodeRequests--
                checkRequestsComplete()
            } else if (source.indexOf("/lxc") !== -1) {
                var nodeNameLxc = getNodeFromSource(source)
                if (exitCode === 0 && stdout) {
                    try {
                        var resultLxc = JSON.parse(stdout)
                        if (resultLxc.data) {
                            for (var k = 0; k < resultLxc.data.length; k++) {
                                resultLxc.data[k].node = nodeNameLxc
                                tempLxcData.push(resultLxc.data[k])
                            }
                        }
                    } catch (e) {
                        console.log("LXC parse error for node: " + nodeNameLxc)
                    }
                }
                pendingNodeRequests--
                checkRequestsComplete()
            }
            disconnectSource(source)
        }
    }

    function curlCmd(endpoint) {
        return "curl " + (ignoreSsl ? "-k " : "") + "-s --connect-timeout 10 'https://" +
               proxmoxHost + ":" + proxmoxPort + "/api2/json" + endpoint +
               "' -H 'Authorization: PVEAPIToken=" + apiTokenId + "=" + apiTokenSecret + "'"
    }

    function fetchData() {
        if (!configured) return
        
        // Only show loading spinner on initial load
        if (!displayedProxmoxData) {
            loading = true
        } else {
            isRefreshing = true
        }
        
        errorMessage = ""
        executable.connectSource(curlCmd("/nodes"))
    }

    function fetchVMs(nodeName) {
        if (!nodeName) return
        executable.connectSource(curlCmd("/nodes/" + nodeName + "/qemu"))
    }

    function fetchLXC(nodeName) {
        if (!nodeName) return
        executable.connectSource(curlCmd("/nodes/" + nodeName + "/lxc"))
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

    compactRepresentation: Item {
    implicitWidth: row.implicitWidth + 8  // Added horizontal padding
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Kirigami.Icon {
            source: "proxmox-monitor"
            implicitWidth: 16
            implicitHeight: 16
        }

        compactRepresentation: Item {
    implicitWidth: row.implicitWidth + 8
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Kirigami.Icon {
            id: proxmoxIcon
            source: "proxmox-monitor"
            implicitWidth: 22
            implicitHeight: 22

            // Heartbeat animation
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

            // Reset scale when animation stops
            onScaleChanged: {
                if (!heartbeatAnimation.running && scale !== 1.0) {
                    scale = 1.0
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
                if (!configured) return "⚙️"
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
        }

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

            // Refresh indicator
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

        // Not configured
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !configured
            spacing: 8

            Item { Layout.fillHeight: true }
            PlasmaComponents.Label {
                text: "Not Configured"
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }
            PlasmaComponents.Label {
                text: "Right-click → Configure"
                Layout.alignment: Qt.AlignHCenter
            }
            Item { Layout.fillHeight: true }
        }

        // Loading (only on initial load)
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: loading ? 50 : 0
            visible: loading

            PlasmaComponents.BusyIndicator {
                anchors.centerIn: parent
                running: loading
            }
        }

        // Error
        PlasmaComponents.Label {
            text: errorMessage
            color: Kirigami.Theme.negativeTextColor
            visible: errorMessage !== "" && configured
            Layout.alignment: Qt.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.margins: 10
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

                // Nodes with their VMs and LXCs (use displayedProxmoxData)
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

                        // Node Header (clickable to collapse/expand)
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

                                    // VM/LXC count summary (visible when collapsed)
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

                        // Node content (VMs and LXCs) - collapsible
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                            visible: !isCollapsed
                            spacing: 4

                            // VMs for this node
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
                                        color: modelData.status === "running" ? Qt.rgba(0, 0.5, 0, 0.15) : Qt.rgba(0.5, 0.5, 0.5, 0.1)

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
                                                text: modelData.status === "running" ?
                                                      (modelData.cpu * 100).toFixed(0) + "% | " + (modelData.mem / 1073741824).toFixed(1) + "G" :
                                                      modelData.status
                                                font.pixelSize: 10
                                                opacity: 0.7
                                            }
                                        }
                                    }
                                }
                            }

                            // LXCs for this node
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
                                        color: modelData.status === "running" ? Qt.rgba(0, 0.3, 0.6, 0.15) : Qt.rgba(0.5, 0.5, 0.5, 0.1)

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
                                                text: modelData.status === "running" ?
                                                      (modelData.cpu * 100).toFixed(0) + "% | " + (modelData.mem / 1073741824).toFixed(1) + "G" :
                                                      modelData.status
                                                font.pixelSize: 10
                                                opacity: 0.7
                                            }
                                        }
                                    }
                                }
                            }

                            // No VMs/LXC for this node
                            PlasmaComponents.Label {
                                text: "No VMs or Containers"
                                visible: nodeVms.length === 0 && nodeLxc.length === 0
                                opacity: 0.5
                                font.pixelSize: 10
                                Layout.leftMargin: 4
                            }
                        }

                        // Separator between nodes
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

                // No nodes found
                PlasmaComponents.Label {
                    text: "No nodes found"
                    visible: !displayedProxmoxData || !displayedProxmoxData.data || displayedProxmoxData.data.length === 0
                    opacity: 0.6
                    Layout.alignment: Qt.AlignHCenter
                }

                // Bottom spacer
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

    Timer {
        interval: refreshInterval > 0 ? refreshInterval : 30000
        running: configured
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchData()
    }
}
