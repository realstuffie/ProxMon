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
    property var ctModel: null
    property string nodeName: ""
    property int ctIndex: 0
    property bool busy: false
    // Which power action is currently in flight ("start"/"shutdown"/"reboot"),
    // set on click so the spinner can replace the exact button that was used.
    property string activeAction: ""
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
    property var anonymizeLxcName: null
    property var anonymizeIp: null
    property var onAction: null
    property var onConsole: null
    property bool consoleEnabled: true
    property bool powerActionsEnabled: true

    Layout.fillWidth: true
    Layout.preferredHeight: contentColumn.implicitHeight
    radius: uiRadiusS

    color: ctModel && ctModel.status === "running"
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
            color: root.ctModel && root.ctModel.status === "running" ? root.uiRunningColor : root.uiStoppedColor
        }

        PlasmaComponents.Label {
            text: root.ctModel
                ? (root.anonymizeVmId(root.ctModel.vmid, root.ctIndex) + ": " + root.anonymizeLxcName(root.ctModel.name, root.ctIndex))
                : ""
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: root.uiRowHeight
            elide: Text.ElideRight
            font.pixelSize: 11
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            visible: root.ctModel && root.ctModel.status === "running"
            Layout.preferredWidth: 80
            Layout.minimumWidth: 80
            Layout.maximumWidth: 80
            Layout.fillHeight: true

            Text {
                id: ctCpuText
                anchors.right: ctStatDivider.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                text: root.ctModel && root.ctModel.status === "running"
                    ? (root.ctModel.cpu * 100).toFixed(0) + "%"
                    : ""
                font.pixelSize: 10
                font.family: "JetBrains Mono"
                color: Kirigami.Theme.textColor
                opacity: 0.7
                horizontalAlignment: Text.AlignRight
            }

            Rectangle {
                id: ctStatDivider
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 10
                opacity: 0.4
                color: Kirigami.Theme.textColor
            }

            Text {
                anchors.left: ctStatDivider.right
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                text: root.ctModel && root.ctModel.status === "running"
                    ? (root.ctModel.mem / root.bytesPerGiB).toFixed(1) + "G"
                    : ""
                font.pixelSize: 10
                font.family: "JetBrains Mono"
                color: Kirigami.Theme.textColor
                opacity: 0.7
            }
        }

        Item {
            readonly property bool hasBackup: root.ctModel && root.ctModel.backupStatus !== undefined
                                              && root.ctModel.backupStatus !== 0
                                              && root.ctModel.backupStatus !== 5 // Excluded
            readonly property bool isExcluded: root.ctModel && root.ctModel.backupStatus === 5

            Layout.fillHeight: true
            Layout.preferredWidth: (hasBackup || isExcluded) ? 50 : 0
            Layout.minimumWidth: (hasBackup || isExcluded) ? 50 : 0
            Layout.maximumWidth: (hasBackup || isExcluded) ? 50 : 0

            Rectangle {
                id: ctBackupDot
                width: 8
                height: 8
                radius: 4
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: parent.hasBackup
                color: {
                    switch (root.ctModel ? root.ctModel.backupStatus : 0) {
                    case 1: return Kirigami.Theme.positiveTextColor
                    case 2: return Kirigami.Theme.neutralTextColor
                    case 3: return Kirigami.Theme.negativeTextColor
                    case 4: return Kirigami.Theme.negativeTextColor
                    default: return "transparent"
                    }
                }
            }

            Text {
                anchors.left: ctBackupDot.right
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                verticalAlignment: Text.AlignVCenter
                text: root.ctModel ? (root.ctModel.lastBackupDisplay || "") : ""
                font.pixelSize: 10
                font.family: "JetBrains Mono"
                opacity: 0.7
                visible: parent.hasBackup
                color: root.ctModel && root.ctModel.verifyState === "failed"
                    ? Kirigami.Theme.negativeTextColor
                    : Kirigami.Theme.textColor
            }
        }

        Item {
            // Fixed-width reservation so row width stays consistent across all
            // rows regardless of running state. Width tracks which features are
            // enabled: stats needs 1 slot, power actions up to 2 (shutdown +
            // reboot). Each slot is a button plus its spacing, so the
            // reservation shrinks when a feature is toggled off instead of
            // leaving dead space. Actual buttons live in an inner RowLayout
            // anchored to the right edge so they stay flush against the console
            // button.
            readonly property int reserveSlots: (root.statsEnabled ? 1 : 0) + (root.powerActionsEnabled ? 2 : 0)
            readonly property int reservePx: reserveSlots > 0 ? reserveSlots * (root.uiActionButtonSize + 4) : 0
            Layout.preferredWidth: reservePx
            Layout.minimumWidth: reservePx
            Layout.maximumWidth: reservePx
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
                icon.name: "view-statistics"
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
                        root.onStatsToggled("lxc", root.nodeName, root.ctModel.vmid)
                    }
                }
            }

            // Power-action area: a fixed two-slot-wide box so the row never
            // shifts between running / stopped / busy. Buttons live left-aligned
            // inside it; while an action is in flight a single spinner replaces
            // them in place (centered) rather than taking an extra slot.
            Item {
                visible: root.powerActionsEnabled
                implicitWidth: 2 * root.uiActionButtonSize + 4
                implicitHeight: root.uiActionButtonSize
                Layout.alignment: Qt.AlignVCenter

                RowLayout {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    // Each action gets a fixed-width slot that holds its position
                    // whether idle or busy. The button shows when idle; a spinner
                    // takes over that same slot only for the action in flight, so
                    // the spinner replaces exactly the button that was clicked.

                    // Start slot (stopped containers)
                    Item {
                        implicitWidth: root.uiActionButtonSize
                        implicitHeight: root.uiActionButtonSize
                        visible: root.ctModel && root.ctModel.status !== "running"

                        PlasmaComponents.ToolButton {
                            anchors.fill: parent
                            flat: true
                            icon.name: (root.armedActionKey === ("lxc:" + root.nodeName + ":" + root.ctModel.vmid + ":start") && root.armedTimerRunning)
                                ? "dialog-ok"
                                : "media-playback-start"
                            visible: !root.busy

                            PlasmaComponents.ToolTip { text: "Start" }

                            background: Rectangle {
                                radius: 4
                                color: parent.hovered
                                    ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, root.uiButtonHoverOpacity)
                                    : "transparent"
                            }

                            onClicked: {
                                root.activeAction = "start"
                                if (typeof root.onAction === "function") root.onAction("lxc", root.nodeName, root.ctModel.vmid, root.ctModel.name, "start")
                            }
                        }

                        PlasmaComponents.BusyIndicator {
                            anchors.centerIn: parent
                            visible: root.busy && root.activeAction === "start"
                            running: visible
                            implicitWidth: root.uiBusyIndicatorSize
                            implicitHeight: root.uiBusyIndicatorSize
                        }
                    }

                    // Shutdown slot (running containers)
                    Item {
                        implicitWidth: root.uiActionButtonSize
                        implicitHeight: root.uiActionButtonSize
                        visible: root.ctModel && root.ctModel.status === "running"

                        PlasmaComponents.ToolButton {
                            anchors.fill: parent
                            flat: true
                            icon.name: (root.armedActionKey === ("lxc:" + root.nodeName + ":" + root.ctModel.vmid + ":shutdown") && root.armedTimerRunning)
                                ? "dialog-ok"
                                : "system-shutdown"
                            visible: !root.busy

                            PlasmaComponents.ToolTip { text: "Shutdown" }

                            background: Rectangle {
                                radius: 4
                                color: parent.hovered
                                    ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, root.uiButtonHoverDangerOpacity)
                                    : "transparent"
                            }

                            onClicked: {
                                root.activeAction = "shutdown"
                                if (typeof root.onAction === "function") root.onAction("lxc", root.nodeName, root.ctModel.vmid, root.ctModel.name, "shutdown")
                            }
                        }

                        PlasmaComponents.BusyIndicator {
                            anchors.centerIn: parent
                            visible: root.busy && root.activeAction === "shutdown"
                            running: visible
                            implicitWidth: root.uiBusyIndicatorSize
                            implicitHeight: root.uiBusyIndicatorSize
                        }
                    }

                    // Reboot slot (running containers)
                    Item {
                        implicitWidth: root.uiActionButtonSize
                        implicitHeight: root.uiActionButtonSize
                        visible: root.ctModel && root.ctModel.status === "running"

                        PlasmaComponents.ToolButton {
                            anchors.fill: parent
                            flat: true
                            icon.name: (root.armedActionKey === ("lxc:" + root.nodeName + ":" + root.ctModel.vmid + ":reboot") && root.armedTimerRunning)
                                ? "dialog-ok"
                                : "system-reboot"
                            visible: !root.busy

                            PlasmaComponents.ToolTip { text: "Reboot" }

                            background: Rectangle {
                                radius: 4
                                color: parent.hovered
                                    ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, root.uiButtonHoverDangerOpacity)
                                    : "transparent"
                            }

                            onClicked: {
                                root.activeAction = "reboot"
                                if (typeof root.onAction === "function") root.onAction("lxc", root.nodeName, root.ctModel.vmid, root.ctModel.name, "reboot")
                            }
                        }

                        PlasmaComponents.BusyIndicator {
                            anchors.centerIn: parent
                            visible: root.busy && root.activeAction === "reboot"
                            running: visible
                            implicitWidth: root.uiBusyIndicatorSize
                            implicitHeight: root.uiBusyIndicatorSize
                        }
                    }
                }
            }
            }
        }

        PlasmaComponents.ToolButton {
                flat: true
                icon.name: "utilities-terminal"
                implicitWidth: root.uiActionButtonSize
                implicitHeight: root.uiActionButtonSize
                visible: root.consoleEnabled && root.ctModel && root.ctModel.status === "running"

                PlasmaComponents.ToolTip { text: "Open Console" }

                background: Rectangle {
                    radius: 4
                    color: parent.hovered
                        ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, root.uiButtonHoverOpacity)
                        : "transparent"
                }

                onClicked: if (typeof root.onConsole === "function") root.onConsole("lxc", root.nodeName, root.ctModel.vmid, root.ctModel.name)
            }
            Item { implicitWidth: root.uiActionButtonSize; implicitHeight: root.uiActionButtonSize; visible: root.consoleEnabled && (!root.ctModel || root.ctModel.status !== "running") }

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

        readonly property var statsData: root.ctModel && root.getStatsData ? root.getStatsData(root.ctModel.vmid) : null
        readonly property bool loading: root.ctModel && root.isStatsLoading ? root.isStatsLoading(root.ctModel.vmid) : false
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
