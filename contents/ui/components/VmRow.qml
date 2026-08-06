import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property var onStatsToggled: null
    property bool statsEnabled: false
    property bool statsExpanded: false
    property var getStatsData: null
    property var isStatsLoading: null
    property var vmModel: null
    property string nodeName: ""
    property int vmIndex: 0
    property bool busy: false
    property string armedActionKey: ""
    property bool armedTimerRunning: false
    property int uiRowHeight: 30
    property int uiRadiusS: 4
    property real uiSurfaceRunningOpacity: 0.12
    property real uiSurfaceAltOpacity: 0.10
    property color uiRunningColor: Kirigami.Theme.positiveTextColor
    property color uiStoppedColor: Kirigami.Theme.disabledTextColor
    property real uiWindowOpacity: 1.0
    property int scrollbarReserve: 0
    property int uiActionButtonSize: 22
    property int uiBusyIndicatorSize: 16
    property real uiButtonHoverOpacity: 0.08
    property real uiButtonHoverDangerOpacity: 0.18
    readonly property real bytesPerGiB: 1073741824.0
    property var anonymizeVmId: null
    property var anonymizeVmName: null
    property var anonymizeIp: null
    property var onAction: null
    property var onConsole: null
    property bool consoleEnabled: true
    property bool powerActionsEnabled: true

    Layout.fillWidth: true
    Layout.preferredHeight: contentColumn.implicitHeight
    radius: uiRadiusS

    color: vmModel && vmModel.status === "running"
        ? Qt.rgba(root.uiRunningColor.r, root.uiRunningColor.g, root.uiRunningColor.b, uiSurfaceRunningOpacity * root.uiWindowOpacity)
        : Qt.rgba(root.uiStoppedColor.r, root.uiStoppedColor.g, root.uiStoppedColor.b, uiSurfaceAltOpacity * root.uiWindowOpacity)

    ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: root.uiRowHeight
        Layout.leftMargin: 4
        Layout.rightMargin: 2
        spacing: 4

        Rectangle {
            implicitWidth: 8
            implicitHeight: 8
            radius: 4
            color: root.vmModel && root.vmModel.status === "running" ? root.uiRunningColor : root.uiStoppedColor
        }

        PlasmaComponents.Label {
            text: root.vmModel
                ? (root.anonymizeVmId(root.vmModel.vmid, root.vmIndex) + ": " + root.anonymizeVmName(root.vmModel.name, root.vmIndex))
                : ""
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: root.uiRowHeight
            elide: Text.ElideRight
            font.pixelSize: 11
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            visible: root.vmModel && root.vmModel.status === "running"
            Layout.preferredWidth: 80
            Layout.minimumWidth: 80
            Layout.maximumWidth: 80
            Layout.fillHeight: true

            Text {
                id: vmCpuText
                anchors.right: vmStatDivider.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                text: root.vmModel && root.vmModel.status === "running"
                    ? (root.vmModel.cpu * 100).toFixed(0) + "%"
                    : ""
                font.pixelSize: 10
                font.family: "JetBrains Mono"
                color: Kirigami.Theme.textColor
                opacity: 0.7
                horizontalAlignment: Text.AlignRight
            }

            Rectangle {
                id: vmStatDivider
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 10
                opacity: 0.4
                color: Kirigami.Theme.textColor
            }

            Text {
                anchors.left: vmStatDivider.right
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                text: root.vmModel && root.vmModel.status === "running"
                    ? (root.vmModel.mem / root.bytesPerGiB).toFixed(1) + "G"
                    : ""
                font.pixelSize: 10
                font.family: "JetBrains Mono"
                color: Kirigami.Theme.textColor
                opacity: 0.7
            }
        }


        Item {
            readonly property bool hasBackup: root.vmModel && root.vmModel.backupStatus !== undefined
                                              && root.vmModel.backupStatus !== 0
                                              && root.vmModel.backupStatus !== 5 // Excluded
            readonly property bool isExcluded: root.vmModel && root.vmModel.backupStatus === 5

            Layout.fillHeight: true
            Layout.preferredWidth: (hasBackup || isExcluded) ? 50 : 0
            Layout.minimumWidth: (hasBackup || isExcluded) ? 50 : 0
            Layout.maximumWidth: (hasBackup || isExcluded) ? 50 : 0

            Rectangle {
                id: vmBackupDot
                width: 8
                height: 8
                radius: 4
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: parent.hasBackup
                color: {
                    switch (root.vmModel ? root.vmModel.backupStatus : 0) {
                    case 1: return Kirigami.Theme.positiveTextColor
                    case 2: return Kirigami.Theme.neutralTextColor
                    case 3: return Kirigami.Theme.negativeTextColor
                    case 4: return Kirigami.Theme.negativeTextColor
                    default: return "transparent"
                    }
                }
            }

            Text {
                anchors.left: vmBackupDot.right
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                verticalAlignment: Text.AlignVCenter
                text: root.vmModel ? (root.vmModel.lastBackupDisplay || "") : ""
                font.pixelSize: 10
                font.family: "JetBrains Mono"
                opacity: 0.7
                visible: parent.hasBackup
                color: root.vmModel && root.vmModel.verifyState === "failed"
                    ? Kirigami.Theme.negativeTextColor
                    : Kirigami.Theme.textColor
            }
        }

        Item {
            // Fixed-width reservation so row width stays consistent across
            // all VM rows regardless of how many icons happen to be visible
            // (stats + shutdown + reboot together need 3 * uiActionButtonSize
            // (22) + 2 * spacing (4) = 74, so 48 was too narrow). The actual
            // buttons live in an inner RowLayout anchored to the right edge
            // of this reservation, so they stay flush against the console
            // button instead of being left-packed with dead space trailing.
            Layout.preferredWidth: 80
            Layout.minimumWidth: 80
            Layout.maximumWidth: 80
            Layout.leftMargin: 6
            Layout.rightMargin: 1
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            Layout.preferredHeight: 28
            Layout.minimumHeight: 28
            Layout.maximumHeight: 28
            visible: root.powerActionsEnabled || root.statsEnabled

            RowLayout {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            PlasmaComponents.ToolButton {
                flat: true
                icon.name: "utilities-system-monitor"
                implicitWidth: root.uiActionButtonSize
                implicitHeight: root.uiActionButtonSize
                visible: root.statsEnabled

                PlasmaComponents.ToolTip { text: "Stats" }

                background: Rectangle {
                    radius: 4
                    color: parent.hovered
                        ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, root.uiButtonHoverOpacity)
                        : "transparent"
                }

                onClicked: {
                    root.statsExpanded = !root.statsExpanded
                    if (root.statsExpanded && typeof root.onStatsToggled === "function") {
                        root.onStatsToggled("qemu", root.nodeName, root.vmModel.vmid)
                    }
                }
            }

            PlasmaComponents.BusyIndicator {
                visible: root.busy
                running: root.busy
                implicitWidth: root.busy ? root.uiBusyIndicatorSize : 0
                implicitHeight: root.uiBusyIndicatorSize
            }

            PlasmaComponents.ToolButton {
                flat: true
                icon.name: (root.armedActionKey === ("qemu:" + root.nodeName + ":" + root.vmModel.vmid + ":start") && root.armedTimerRunning)
                    ? "dialog-ok"
                    : "media-playback-start"
                implicitWidth: root.uiActionButtonSize
                implicitHeight: root.uiActionButtonSize
                visible: root.vmModel && !root.busy && root.vmModel.status !== "running"

                PlasmaComponents.ToolTip { text: "Start" }

                background: Rectangle {
                    radius: 4
                    color: parent.hovered
                        ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, root.uiButtonHoverOpacity)
                        : "transparent"
                }

                onClicked: if (typeof root.onAction === "function") root.onAction("qemu", root.nodeName, root.vmModel.vmid, root.vmModel.name, "start")
            }

            PlasmaComponents.ToolButton {
                flat: true
                icon.name: (root.armedActionKey === ("qemu:" + root.nodeName + ":" + root.vmModel.vmid + ":shutdown") && root.armedTimerRunning)
                    ? "dialog-ok"
                    : "system-shutdown"
                implicitWidth: root.uiActionButtonSize
                implicitHeight: root.uiActionButtonSize
                visible: root.vmModel && !root.busy && root.vmModel.status === "running"

                PlasmaComponents.ToolTip { text: "Shutdown" }

                background: Rectangle {
                    radius: 4
                    color: parent.hovered
                        ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, root.uiButtonHoverDangerOpacity)
                        : "transparent"
                }

                onClicked: if (typeof root.onAction === "function") root.onAction("qemu", root.nodeName, root.vmModel.vmid, root.vmModel.name, "shutdown")
            }
            Item { implicitWidth: root.uiActionButtonSize; implicitHeight: root.uiActionButtonSize; visible: !root.vmModel || root.busy }

            PlasmaComponents.ToolButton {
                flat: true
                icon.name: (root.armedActionKey === ("qemu:" + root.nodeName + ":" + root.vmModel.vmid + ":reboot") && root.armedTimerRunning)
                    ? "dialog-ok"
                    : "system-reboot"
                implicitWidth: root.uiActionButtonSize
                implicitHeight: root.uiActionButtonSize
                visible: root.vmModel && !root.busy && root.vmModel.status === "running"

                PlasmaComponents.ToolTip { text: "Reboot" }

                background: Rectangle {
                    radius: 4
                    color: parent.hovered
                        ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, root.uiButtonHoverDangerOpacity)
                        : "transparent"
                }

                onClicked: if (typeof root.onAction === "function") root.onAction("qemu", root.nodeName, root.vmModel.vmid, root.vmModel.name, "reboot")
            }
            Item { implicitWidth: root.uiActionButtonSize; implicitHeight: root.uiActionButtonSize; visible: !root.vmModel || root.busy || root.vmModel.status !== "running" }
            }
        }

        PlasmaComponents.ToolButton {
                flat: true
                icon.name: "utilities-terminal"
                implicitWidth: root.uiActionButtonSize
                implicitHeight: root.uiActionButtonSize
                visible: root.consoleEnabled && root.vmModel && root.vmModel.status === "running"

                PlasmaComponents.ToolTip { text: "Open Console" }

                background: Rectangle {
                    radius: 4
                    color: parent.hovered
                        ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, root.uiButtonHoverOpacity)
                        : "transparent"
                }

                onClicked: if (typeof root.onConsole === "function") root.onConsole("qemu", root.nodeName, root.vmModel.vmid, root.vmModel.name)
            }
            Item { implicitWidth: root.uiActionButtonSize; implicitHeight: root.uiActionButtonSize; visible: root.consoleEnabled && (!root.vmModel || root.vmModel.status !== "running") }

        Item {
            Layout.preferredWidth: 2
            Layout.minimumWidth: 2
        }
    }

    ColumnLayout {
        id: statsPanel
        visible: root.statsExpanded
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 8
        Layout.topMargin: 2
        Layout.bottomMargin: 6
        spacing: 2

        readonly property var statsData: root.vmModel && root.getStatsData ? root.getStatsData(root.vmModel.vmid) : null
        readonly property bool loading: root.vmModel && root.isStatsLoading ? root.isStatsLoading(root.vmModel.vmid) : false
        readonly property bool hasGraph: !loading && statsData && !statsData.error

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: {
                    if (statsPanel.loading) return "Loading stats…"
                    if (!statsPanel.statsData) return ""
                    if (statsPanel.statsData.error) return "Error: " + statsPanel.statsData.error
                    var ip = statsPanel.statsData.ip
                    if (!ip) return "IP: N/A"
                    return "IP: " + (root.anonymizeIp ? root.anonymizeIp(ip) : ip)
                }
                font.pixelSize: 10
                font.family: "JetBrains Mono"
                color: Kirigami.Theme.textColor
                opacity: 0.85
            }

            Item { Layout.fillWidth: true }

            Rectangle { width: 8; height: 8; radius: 4; color: "#5cb3fa"; visible: statsPanel.hasGraph }
            Text { text: "CPU"; font.pixelSize: 9; opacity: 0.7; visible: statsPanel.hasGraph }
            Rectangle { width: 8; height: 8; radius: 4; color: "#f5a742"; visible: statsPanel.hasGraph }
            Text { text: "Mem"; font.pixelSize: 9; opacity: 0.7; visible: statsPanel.hasGraph }
        }

        Canvas {
            id: statsCanvas
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            visible: statsPanel.hasGraph
            property var rrd: statsPanel.statsData && statsPanel.statsData.rrd ? statsPanel.statsData.rrd : []
            onRrdChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                // Faint background grid: 6 columns = 10-minute blocks across
                // the hour-long timeframe we fetch; 6 rows to match.
                ctx.strokeStyle = Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                ctx.lineWidth = 1
                ctx.beginPath()
                for (var gy = 0; gy <= 6; gy++) {
                    var gridY = Math.round((gy / 6) * height) + 0.5
                    ctx.moveTo(0, gridY)
                    ctx.lineTo(width, gridY)
                }
                for (var gx = 0; gx <= 6; gx++) {
                    var gridX = Math.round((gx / 6) * width) + 0.5
                    ctx.moveTo(gridX, 0)
                    ctx.lineTo(gridX, height)
                }
                ctx.stroke()

                if (!rrd || rrd.length < 2) {
                    ctx.fillStyle = Qt.rgba(1, 1, 1, 0.4)
                    ctx.font = "10px sans-serif"
                    ctx.fillText("No history yet", 4, height / 2)
                    return
                }
                function drawSeries(getValue, color) {
                    ctx.strokeStyle = color
                    ctx.lineWidth = 1.5
                    ctx.beginPath()
                    var started = false
                    for (var i = 0; i < rrd.length; i++) {
                        var v = getValue(rrd[i])
                        if (v === null || v === undefined) continue
                        var x = (i / (rrd.length - 1)) * width
                        var y = height - (Math.max(0, Math.min(100, v)) / 100) * height
                        if (!started) { ctx.moveTo(x, y); started = true }
                        else { ctx.lineTo(x, y) }
                    }
                    ctx.stroke()
                }
                drawSeries(function(p) { return (p.cpu !== undefined && p.cpu !== null) ? p.cpu * 100 : null }, "#5cb3fa")
                drawSeries(function(p) { return (p.mem !== undefined && p.mem !== null && p.maxmem) ? (p.mem / p.maxmem * 100) : null }, "#f5a742")
            }
        }
    }
    }
}
