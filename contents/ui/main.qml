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
    property var proxmoxData: null
    property var vmData: []
    property var lxcData: []
    property bool loading: false
    property string errorMessage: ""
    property string lastUpdate: ""
    property bool configured: proxmoxHost !== "" && apiTokenSecret !== ""
    property bool defaultsLoaded: false
    property string currentNode: ""
    property var sortedVmData: sortByStatus(vmData)
    property var sortedLxcData: sortByStatus(lxcData)
    property bool devMode: false
    property int footerClickCount: 0
    property var footerClickTimer: null

    // Anonymization data
    readonly property var anonNodeNames: ["server-01", "server-02", "server-03", "pve-node", "cluster-main"]
    readonly property var anonVmNames: ["web-server", "database", "backup-srv", "dev-env", "test-vm", "mail-server", "proxy", "monitoring", "gitlab", "nextcloud"]
    readonly property var anonLxcNames: ["nginx-proxy", "pihole", "postgres-db", "redis-cache", "mqtt-broker", "homeassistant", "grafana", "prometheus", "traefik", "portainer"]

    // Calculate total height needed
    readonly property int nodeCount: proxmoxData && proxmoxData.data ? proxmoxData.data.length : 0
    readonly property int vmCount: vmData.length
    readonly property int lxcCount: lxcData.length
    readonly property int calculatedHeight: {
        var h = 50
        if (!configured) return 200
        if (proxmoxData && proxmoxData.data) h += proxmoxData.data.length * 90
        if (vmCount > 0) h += 28 + (vmCount * 36)
        if (lxcCount > 0) h += 28 + (lxcCount * 36)
        h += 40
        h += 20
        return Math.max(200, Math.min(h, 600))
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
        // Reset counter after 1 second
        if (footerClickTimer) footerClickTimer.destroy()
        footerClickTimer = Qt.createQmlObject('import QtQuick; Timer { interval: 1000; onTriggered: footerClickCount = 0 }', root)
        footerClickTimer.start()
    }

    function sortByStatus(data) {
        if (!data || data.length === 0) return []
        return data.slice().sort(function(a, b) {
            switch (defaultSorting) {
                case "status":
                    var aRunning = (a.status === "running") ? 0 : 1;
                    var bRunning = (b.status === "running") ? 0 : 1;
                    if (aRunning !== bRunning) {
                        return aRunning - bRunning;
                    }
                    return a.name.localeCompare(b.name);
                case "name":
                    return a.name.localeCompare(b.name);
                case "nameDesc":
                    return b.name.localeCompare(a.name);
                case "id":
                    return a.vmid - b.vmid;
                case "idDesc":
                    return b.vmid - a.vmid;
                default:
                    var aRun = (a.status === "running") ? 0 : 1;
                    var bRun = (b.status === "running") ? 0 : 1;
                    if (aRun !== bRun) return aRun - bRun;
                    return a.name.localeCompare(b.name);
            }
        });
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
                loading = false
                if (exitCode === 0 && stdout) {
                    try {
                        proxmoxData = JSON.parse(stdout)
                        errorMessage = ""
                        lastUpdate = Qt.formatDateTime(new Date(), "hh:mm:ss")
                        if (proxmoxData.data && proxmoxData.data.length > 0) {
                            currentNode = proxmoxData.data[0].node
                            fetchVMs()
                            fetchLXC()
                        }
                    } catch (e) {
                        errorMessage = "Parse error"
                    }
                } else {
                    errorMessage = data["stderr"] || "Connection failed"
                }
            } else if (source.indexOf("/qemu") !== -1) {
                if (exitCode === 0 && stdout) {
                    try {
                        var result = JSON.parse(stdout)
                        vmData = result.data || []
                    } catch (e) {
                        console.log("VM parse error")
                    }
                }
            } else if (source.indexOf("/lxc") !== -1) {
                if (exitCode === 0 && stdout) {
                    try {
                        var result = JSON.parse(stdout)
                        lxcData = result.data || []
                    } catch (e) {
                        console.log("LXC parse error")
                    }
                }
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
        loading = true
        errorMessage = ""
        executable.connectSource(curlCmd("/nodes"))
    }

    function fetchVMs() {
        if (!currentNode) return
        executable.connectSource(curlCmd("/nodes/" + currentNode + "/qemu"))
    }

    function fetchLXC() {
        if (!currentNode) return
        executable.connectSource(curlCmd("/nodes/" + currentNode + "/lxc"))
    }

    property int runningVMs: {
        var count = 0
        for (var i = 0; i < vmData.length; i++) {
            if (vmData[i].status === "running") count++
        }
        return count
    }

    property int runningLXC: {
        var count = 0
        for (var i = 0; i < lxcData.length; i++) {
            if (lxcData[i].status === "running") count++
        }
        return count
    }

    compactRepresentation: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        RowLayout {
            id: row
            anchors.fill: parent
            spacing: 4

            Kirigami.Icon {
                source: "proxmox-monitor"
                implicitWidth: 16
                implicitHeight: 16
            }

            PlasmaComponents.Label {
                text: {
                    if (!configured) return "⚙️"
                    if (loading) return "..."
                    if (errorMessage) return "!"
                    if (proxmoxData && proxmoxData.data && proxmoxData.data[0]) {
                        return Math.round(proxmoxData.data[0].cpu * 100) + "%"
                    }
                    return "-"
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
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

        // Header (fixed at top)
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

            // Dev mode indicator
            PlasmaComponents.Label {
                text: "🔧"
                visible: devMode
                font.pixelSize: 14
            }

            PlasmaComponents.Button {
                icon.name: "view-refresh"
                onClicked: fetchData()
                visible: configured
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

        // Loading
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

            Flickable {
                contentWidth: availableWidth
                contentHeight: mainContentColumn.implicitHeight

                ColumnLayout {
                    id: mainContentColumn
                    width: parent.width
                    spacing: 6

                    // Node Info
                    Repeater {
                        model: proxmoxData && proxmoxData.data ? proxmoxData.data : []

                        delegate: Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 82
                            radius: 6
                            color: Kirigami.Theme.backgroundColor
                            border.color: Kirigami.Theme.disabledTextColor
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6

                                RowLayout {
                                    spacing: 8

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
                                }

                                PlasmaComponents.Label {
                                    text: "Uptime: " + Math.floor(modelData.uptime / 86400) + "d " + Math.floor((modelData.uptime % 86400) / 3600) + "h"
                                    font.pixelSize: 11
                                    opacity: 0.7
                                }
                            }
                        }
                    }

                    // VMs Section
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: vmData.length > 0
                        spacing: 4

                        RowLayout {
                            Layout.preferredHeight: 24
                            spacing: 6

                            Kirigami.Icon {
                                source: "computer-symbolic"
                                implicitWidth: 16
                                implicitHeight: 16
                            }

                            PlasmaComponents.Label {
                                text: "Virtual Machines (" + runningVMs + "/" + vmData.length + ")"
                                font.bold: true
                                font.pixelSize: 12
                            }
                        }

                        Repeater {
                            model: sortedVmData

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                radius: 4
                                color: modelData.status === "running" ? Qt.rgba(0, 0.5, 0, 0.15) : Qt.rgba(0.5, 0.5, 0.5, 0.1)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

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
                                        font.pixelSize: 12
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

                    // LXC Section
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: lxcData.length > 0
                        spacing: 4

                        RowLayout {
                            Layout.preferredHeight: 24
                            spacing: 6

                            Kirigami.Icon {
                                source: "lxc"
                                implicitWidth: 16
                                implicitHeight: 16
                            }

                            PlasmaComponents.Label {
                                text: "Containers (" + runningLXC + "/" + lxcData.length + ")"
                                font.bold: true
                                font.pixelSize: 12
                            }
                        }

                        Repeater {
                            model: sortedLxcData

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                radius: 4
                                color: modelData.status === "running" ? Qt.rgba(0, 0.3, 0.6, 0.15) : Qt.rgba(0.5, 0.5, 0.5, 0.1)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

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
                                        font.pixelSize: 12
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

                    // No VMs/LXC
                    PlasmaComponents.Label {
                        text: "No VMs or Containers found"
                        visible: vmData.length === 0 && lxcData.length === 0 && proxmoxData !== null
                        opacity: 0.6
                        Layout.alignment: Qt.AlignHCenter
                    }

                    // Bottom spacer for scroll padding
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 4
                    }
                }
            }
        }

        // Footer (fixed at bottom)
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
                        source: "computer-symbolic"
                        implicitWidth: 12
                        implicitHeight: 12
                        opacity: 0.6
                    }

                    PlasmaComponents.Label {
                        text: runningVMs + "/" + vmData.length
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
                        text: runningLXC + "/" + lxcData.length
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
