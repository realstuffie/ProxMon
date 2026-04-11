import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Item {
    id: compactRoot

    property bool hasCoreConfig: false
    property string secretState: "idle"
    property bool configured: false
    property bool loading: false
    property bool isRefreshing: false
    property string compactMode: "cpu"
    property int runningVMs: 0
    property int runningLXC: 0
    property var displayedVmData: []
    property var displayedLxcData: []
    property string lastUpdate: ""
    property string errorMessage: ""
    property string connectionMode: "single"
    property var displayedEndpoints: []
    property var displayedProxmoxData: null
    property var safeCpuPercent: null
    property var onToggleExpanded: null

    implicitWidth: compactLayout.implicitWidth
    implicitHeight: compactLayout.implicitHeight

    function averageCpuText() {
        if (typeof safeCpuPercent !== "function") return "-"

        if (connectionMode === "multiHost") {
            if (!displayedEndpoints || displayedEndpoints.length === 0) return "-"
            var totalCpu = 0
            var onlineCount = 0
            for (var ei = 0; ei < displayedEndpoints.length; ei++) {
                var endpoint = displayedEndpoints[ei]
                if (!endpoint || !endpoint.nodes) continue
                for (var ni = 0; ni < endpoint.nodes.length; ni++) {
                    var node = endpoint.nodes[ni]
                    if (node && node.status === "online") {
                        totalCpu += safeCpuPercent(node.cpu)
                        onlineCount++
                    }
                }
            }
            if (onlineCount === 0) return "!"
            return Math.round(totalCpu / onlineCount) + "%"
        }

        if (displayedProxmoxData && displayedProxmoxData.data && displayedProxmoxData.data[0]) {
            var totalCpu2 = 0
            var onlineCount2 = 0
            for (var i = 0; i < displayedProxmoxData.data.length; i++) {
                if (displayedProxmoxData.data[i].status === "online") {
                    totalCpu2 += safeCpuPercent(displayedProxmoxData.data[i].cpu)
                    onlineCount2++
                }
            }
            if (onlineCount2 === 0) return "!"
            return Math.round(totalCpu2 / onlineCount2) + "%"
        }

        return "-"
    }

    RowLayout {
        id: compactLayout
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: 0
        spacing: 4

        property bool hovered: compactMouseArea.containsMouse || iconMouseArea.containsMouse

        Kirigami.Icon {
            id: proxmoxIcon
            source: Qt.resolvedUrl("../../icons/proxmox-monitor.svg")
            implicitWidth: 22
            implicitHeight: 22

            MouseArea {
                id: iconMouseArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: if (typeof compactRoot.onToggleExpanded === "function") compactRoot.onToggleExpanded()
            }

            SequentialAnimation {
                id: heartbeatAnimation
                running: compactRoot.loading || compactRoot.isRefreshing
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
                PauseAnimation {
                    duration: 400
                }
            }

            Connections {
                target: compactRoot
                function onLoadingChanged() {
                    if (!compactRoot.loading && !compactRoot.isRefreshing) {
                        proxmoxIcon.scale = 1.0
                    }
                }
                function onIsRefreshingChanged() {
                    if (!compactRoot.loading && !compactRoot.isRefreshing) {
                        proxmoxIcon.scale = 1.0
                    }
                }
            }
        }

        PlasmaComponents.Label {
            text: {
                if (!compactRoot.hasCoreConfig) return "⚙"
                if (compactRoot.secretState === "loading") return "..."
                if (compactRoot.secretState === "missing" || compactRoot.secretState === "error") return "!"
                if (!compactRoot.configured) return "⚙"
                if (compactRoot.loading) return "..."

                switch (compactRoot.compactMode) {
                    case "running":
                        var running = compactRoot.runningVMs + compactRoot.runningLXC
                        var total = compactRoot.displayedVmData.length + compactRoot.displayedLxcData.length
                        return running + "/" + total
                    case "lastUpdate":
                        if (!compactRoot.lastUpdate) return "-"
                        return compactRoot.lastUpdate.replace(/^(\d\d:\d\d):\d\d(.*)$/, "$1$2")
                    case "error":
                        if (compactRoot.errorMessage) return "!"
                        break
                    case "cpu":
                    default:
                        break
                }

                if (compactRoot.errorMessage) return "!"
                return averageCpuText()
            }
            font.pixelSize: 13
            rightPadding: 20
            color: compactLayout.hovered ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
        }
    }

    MouseArea {
        id: compactMouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: if (typeof compactRoot.onToggleExpanded === "function") compactRoot.onToggleExpanded()
    }
}
