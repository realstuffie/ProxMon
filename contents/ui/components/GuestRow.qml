pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

/**
 * One guest (VM or container) in the expanded panel.
 *
 * Replaces the former VmRow/LxcRow pair, which had drifted into two copies of
 * the same 490 lines differing only in identifier names. `kind` selects the
 * Proxmox resource type ("qemu" or "lxc") and is what every callback and armed
 * action key is built from, so the two guest types can never drift again.
 *
 * Layout contract: every column keeps its reserved width whether or not it has
 * content, so the right-hand action cluster sits at the same x on every row
 * regardless of running state, backup state or which features are enabled.
 */
Rectangle {
    id: root

    // ---- identity -------------------------------------------------------
    property string kind: "qemu"
    property var guestModel: null
    property string nodeName: ""
    property int guestIndex: 0

    // ---- interaction state ----------------------------------------------
    property bool busy: false
    // Which power action is in flight ("start"/"shutdown"/"reboot"), set on
    // click so the spinner replaces the exact button that was used.
    property string activeAction: ""
    property string armedActionKey: ""
    property bool armedTimerRunning: false
    property bool statsExpanded: false

    // ---- theming --------------------------------------------------------
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
    property color uiCpuColor: "#5cb3fa"
    property color uiMemColor: "#f5a742"
    // Actions stay in the layout at all times but recede until the row is
    // hovered, so a list of twenty guests reads as data rather than as a wall
    // of buttons.
    property real uiActionIdleOpacity: 0.5

    // ---- callbacks (repo convention: plain function properties) ----------
    property var anonymizeVmId: null
    property var anonymizeName: null
    property var anonymizeIp: null
    property var onAction: null
    property var onConsole: null
    property var onStatsToggled: null
    property var getStatsData: null
    property var isStatsLoading: null

    // ---- feature toggles -------------------------------------------------
    property bool statsEnabled: false
    property bool consoleEnabled: true
    property bool powerActionsEnabled: true

    readonly property real bytesPerGiB: 1073741824.0
    readonly property bool isRunning: !!(guestModel && guestModel.status === "running")
    readonly property int vmid: guestModel ? guestModel.vmid : 0
    readonly property string displayName: guestModel ? guestModel.name : ""

    // Key prefix for this row's armed-confirmation state. Built from kind so
    // a VM and a container sharing a vmid can never arm each other.
    readonly property string actionKeyPrefix: root.kind + ":" + root.nodeName + ":" + root.vmid
    readonly property bool armed: root.armedTimerRunning
        && root.armedActionKey.indexOf(root.actionKeyPrefix + ":") === 0

    function isArmedFor(action) {
        return root.armedTimerRunning && root.armedActionKey === (root.actionKeyPrefix + ":" + action)
    }

    // Numeric metrics, defensively coerced. A missing or non-finite value
    // reads as "no data" and draws nothing rather than a misleading zero bar.
    readonly property real cpuFraction: {
        if (!root.isRunning || !root.guestModel) return 0
        const v = Number(root.guestModel.cpu)
        return (isFinite(v) && v > 0) ? Math.min(1, v) : 0
    }
    readonly property real memBytes: {
        if (!root.guestModel) return 0
        const v = Number(root.guestModel.mem)
        return isFinite(v) && v > 0 ? v : 0
    }

    readonly property color loadColor: {
        if (root.cpuFraction >= 0.85) return Kirigami.Theme.negativeTextColor
        if (root.cpuFraction >= 0.60) return Kirigami.Theme.neutralTextColor
        return root.uiCpuColor
    }

    Layout.fillWidth: true
    Layout.preferredHeight: contentColumn.implicitHeight
    radius: uiRadiusS
    border.width: 1
    border.color: {
        const c = root.armed ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.highlightColor
        return Qt.rgba(c.r, c.g, c.b,
                       root.armed ? 0.5 : (rowHover.hovered || root.statsExpanded ? 0.25 : 0))
    }

    color: {
        const base = root.isRunning ? root.uiRunningColor : root.uiStoppedColor
        const alpha = (root.isRunning ? root.uiSurfaceRunningOpacity : root.uiSurfaceAltOpacity)
            * root.uiWindowOpacity * 0.45
        return Qt.rgba(base.r, base.g, base.b, alpha + (rowHover.hovered ? 0.06 : 0))
    }

    Behavior on color {
        ColorAnimation { duration: 100 }
    }

    HoverHandler {
        id: rowHover
    }

    ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        // Main row lives inside a plain Item so the CPU hairline can anchor to
        // its bottom edge without becoming a layout child.
        Item {
            id: rowSlot
            Layout.fillWidth: true
            Layout.preferredHeight: root.uiRowHeight

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 7
                anchors.rightMargin: 4
                spacing: 4

                // Status dot. Deliberately a circle, and the only circle in
                // the row, so it can't be confused with the backup marker.
                Rectangle {
                    implicitWidth: 6
                    implicitHeight: 6
                    radius: 4
                    color: root.isRunning ? root.uiRunningColor : root.uiStoppedColor
                }

                PlasmaComponents.Label {
                    text: root.guestModel
                        ? (root.anonymizeVmId ? root.anonymizeVmId(root.vmid, root.guestIndex) : root.vmid)
                        : ""
                    Layout.preferredWidth: Math.max(25, implicitWidth)
                    font.pixelSize: 10
                    font.family: "JetBrains Mono"
                    opacity: root.isRunning ? 0.55 : 0.4
                }

                PlasmaComponents.Label {
                    id: nameLabel
                    text: root.guestModel
                        ? (root.anonymizeName ? root.anonymizeName(root.displayName, root.guestIndex) : root.displayName)
                        : ""
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    elide: Text.ElideRight
                    font.pixelSize: 11
                    verticalAlignment: Text.AlignVCenter
                    opacity: root.isRunning ? 1.0 : 0.65

                    QQC2.ToolTip.visible: nameHover.hovered && nameLabel.truncated
                    QQC2.ToolTip.text: nameLabel.text
                    HoverHandler { id: nameHover }
                }

                // CPU / memory readout. Reserved at a fixed width and filled
                // with a placeholder when stopped, so the columns to its right
                // never shift between running and stopped rows.
                Item {
                    id: metrics
                    Layout.preferredWidth: 62
                    Layout.minimumWidth: 62
                    Layout.maximumWidth: 62
                    Layout.fillHeight: true

                    QQC2.ToolTip.visible: metricsHover.hovered && root.isRunning
                    QQC2.ToolTip.text: root.isRunning
                        ? ("CPU " + (root.cpuFraction * 100).toFixed(1) + "%  ·  Memory "
                           + (root.memBytes / root.bytesPerGiB).toFixed(2) + " GiB")
                        : ""

                    HoverHandler { id: metricsHover }

                    Text {
                        anchors.right: statDivider.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        text: root.isRunning ? (root.cpuFraction * 100).toFixed(0) + "%" : "–"
                        font.pixelSize: 10
                        font.family: "JetBrains Mono"
                        color: Kirigami.Theme.textColor
                        opacity: root.isRunning ? 0.85 : 0.35
                        horizontalAlignment: Text.AlignRight
                    }

                    Rectangle {
                        id: statDivider
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.horizontalCenterOffset: -4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: 10
                        opacity: root.isRunning ? 0.18 : 0.1
                        color: Kirigami.Theme.textColor
                    }

                    Text {
                        anchors.left: statDivider.right
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.isRunning
                            ? (root.memBytes / root.bytesPerGiB).toFixed(1) + "G"
                            : "–"
                        font.pixelSize: 10
                        font.family: "JetBrains Mono"
                        color: Kirigami.Theme.textColor
                        opacity: root.isRunning ? 0.85 : 0.35
                    }
                }

                // Backup state. The marker is a rounded bar rather than a dot
                // so it is never mistaken for the status circle at the far
                // left of the same row.
                Item {
                    id: backup

                    readonly property int backupStatus: root.guestModel
                        && root.guestModel.backupStatus !== undefined
                        ? root.guestModel.backupStatus : 0
                    readonly property bool hasBackup: backupStatus !== 0 && backupStatus !== 5
                    readonly property bool isExcluded: backupStatus === 5

                    Layout.preferredWidth: 46
                    Layout.minimumWidth: 46
                    Layout.maximumWidth: 46
                    Layout.fillHeight: true

                    QQC2.ToolTip.visible: backupHover.hovered && backup.hasBackup
                    QQC2.ToolTip.text: {
                        if (!backup.hasBackup) return ""
                        const when = root.guestModel ? (root.guestModel.lastBackupDisplay || "unknown") : "unknown"
                        const verify = root.guestModel && root.guestModel.verifyState === "failed"
                            ? "  ·  verification failed" : ""
                        return "Last backup: " + when + verify
                    }

                    HoverHandler { id: backupHover }

                    Rectangle {
                        id: backupMark
                        width: 10
                        height: 4
                        radius: 2
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: backup.hasBackup
                        color: {
                            switch (backup.backupStatus) {
                            case 1: return Kirigami.Theme.positiveTextColor
                            case 2: return Kirigami.Theme.neutralTextColor
                            case 3:
                            case 4: return Kirigami.Theme.negativeTextColor
                            default: return "transparent"
                            }
                        }
                    }

                    Text {
                        anchors.left: backupMark.right
                        anchors.leftMargin: 4
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        // Trimmed to the leading magnitude ("1d", "8h"); the
                        // full phrasing lives in the tooltip.
                        text: {
                            if (!backup.hasBackup || !root.guestModel) return ""
                            const full = root.guestModel.lastBackupDisplay || ""
                            const m = full.match(/^\s*(\d+\s*[a-zA-Z]+)/)
                            return m ? m[1].replace(/\s+/g, "") : full
                        }
                        font.pixelSize: 10
                        font.family: "JetBrains Mono"
                        opacity: backup.backupStatus === 1 ? 0.7 : 1.0
                        visible: backup.hasBackup
                        color: (root.guestModel && root.guestModel.verifyState === "failed")
                            || backup.backupStatus === 3 || backup.backupStatus === 4
                                ? Kirigami.Theme.negativeTextColor
                                : (backup.backupStatus === 2 ? Kirigami.Theme.neutralTextColor
                                                           : Kirigami.Theme.textColor)
                    }
                }

                // Stats + power actions. Fixed reservation that tracks which
                // features are enabled: stats takes one slot, power actions up
                // to two (shutdown + reboot). Buttons are right-anchored inside
                // it so they stay flush against the console button.
                FocusScope {
                    id: actions
                    readonly property int reserveSlots: (root.statsEnabled ? 1 : 0)
                        + (root.powerActionsEnabled ? 2 : 0)
                    readonly property int reservePx: reserveSlots > 0
                        ? reserveSlots * (root.uiActionButtonSize + 4) : 0

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

                    opacity: (rowHover.hovered || root.busy || root.armed || root.statsExpanded || actions.activeFocus)
                        ? 1.0 : root.uiActionIdleOpacity
                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    RowLayout {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        RowActionButton {
                            icon.name: "view-statistics"
                            implicitWidth: root.uiActionButtonSize
                            implicitHeight: root.uiActionButtonSize
                            visible: root.statsEnabled
                            checked: root.statsExpanded

                            PlasmaComponents.ToolTip { text: "Resource history" }

                            onClicked: {
                                root.statsExpanded = !root.statsExpanded
                                if (root.statsExpanded && typeof root.onStatsToggled === "function") {
                                    root.onStatsToggled(root.kind, root.nodeName, root.vmid)
                                }
                            }
                        }

                        // Fixed two-slot box so the row never reflows between
                        // running / stopped / busy. Each action owns a slot
                        // that holds its position whether idle or busy.
                        Item {
                            visible: root.powerActionsEnabled
                            implicitWidth: 2 * root.uiActionButtonSize + 4
                            implicitHeight: root.uiActionButtonSize
                            Layout.alignment: Qt.AlignVCenter

                            RowLayout {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                // Start slot (stopped guests)
                                Item {
                                    implicitWidth: root.uiActionButtonSize
                                    implicitHeight: root.uiActionButtonSize
                                    visible: !root.isRunning

                                    RowActionButton {
                                        anchors.fill: parent
                                        icon.name: root.isArmedFor("start")
                                            ? "dialog-ok" : "media-playback-start"
                                        // media-playback-start is a solid glyph
                                        // where the other action icons are
                                        // outlines; trimming it keeps the
                                        // optical weight of the row even.
                                        iconSize: root.isArmedFor("start") ? 16 : 13
                                        visible: !root.busy

                                        PlasmaComponents.ToolTip { text: "Start" }

                                        onClicked: {
                                            root.activeAction = "start"
                                            if (typeof root.onAction === "function")
                                                root.onAction(root.kind, root.nodeName, root.vmid,
                                                              root.displayName, "start")
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

                                // Shutdown slot (running guests)
                                Item {
                                    implicitWidth: root.uiActionButtonSize
                                    implicitHeight: root.uiActionButtonSize
                                    visible: root.isRunning

                                    RowActionButton {
                                        anchors.fill: parent
                                        danger: true
                                        icon.name: root.isArmedFor("shutdown")
                                            ? "dialog-ok" : "system-shutdown"
                                        visible: !root.busy

                                        PlasmaComponents.ToolTip { text: "Shutdown" }

                                        onClicked: {
                                            root.activeAction = "shutdown"
                                            if (typeof root.onAction === "function")
                                                root.onAction(root.kind, root.nodeName, root.vmid,
                                                              root.displayName, "shutdown")
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

                                // Reboot slot (running guests)
                                Item {
                                    implicitWidth: root.uiActionButtonSize
                                    implicitHeight: root.uiActionButtonSize
                                    visible: root.isRunning

                                    RowActionButton {
                                        anchors.fill: parent
                                        danger: true
                                        icon.name: root.isArmedFor("reboot")
                                            ? "dialog-ok" : "system-reboot"
                                        visible: !root.busy

                                        PlasmaComponents.ToolTip { text: "Reboot" }

                                        onClicked: {
                                            root.activeAction = "reboot"
                                            if (typeof root.onAction === "function")
                                                root.onAction(root.kind, root.nodeName, root.vmid,
                                                              root.displayName, "reboot")
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

                RowActionButton {
                    id: consoleButton
                    icon.name: "utilities-terminal"
                    implicitWidth: root.uiActionButtonSize
                    implicitHeight: root.uiActionButtonSize
                    visible: root.consoleEnabled && root.isRunning
                    opacity: rowHover.hovered || consoleButton.activeFocus ? 1.0 : root.uiActionIdleOpacity
                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    PlasmaComponents.ToolTip { text: "Open console" }

                    onClicked: if (typeof root.onConsole === "function")
                        root.onConsole(root.kind, root.nodeName, root.vmid, root.displayName)
                }

                // Holds the console column open on stopped rows.
                Item {
                    implicitWidth: root.uiActionButtonSize
                    implicitHeight: root.uiActionButtonSize
                    visible: root.consoleEnabled && !root.isRunning
                }

                Item {
                    Layout.preferredWidth: 2
                    Layout.minimumWidth: 2
                }
            }

            // CPU load as a hairline along the bottom edge of the row. Costs no
            // vertical space and turns the list into a load profile you can
            // read in one pass; colour crosses to neutral at 60% and negative
            // at 85%.
            Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: root.uiRadiusS
                height: 2
                radius: 1
                width: Math.round((parent.width - 2 * root.uiRadiusS) * root.cpuFraction)
                visible: root.isRunning && root.cpuFraction > 0
                color: root.loadColor
                opacity: 0.35

                Behavior on width {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
            }
        }

        // Resource history. Loaded on demand: keeping a Canvas alive for every
        // guest cost one scene-graph node per row for nothing.
        Loader {
            id: statsLoader
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 8
            Layout.topMargin: 2
            Layout.bottomMargin: 6
            active: root.statsExpanded
            visible: active
            sourceComponent: statsComponent
        }
    }

    Component {
        id: statsComponent

        ColumnLayout {
            id: statsPanel
            spacing: 2

            readonly property var statsData: root.guestModel && root.getStatsData
                ? root.getStatsData(root.vmid) : null
            readonly property bool loading: root.guestModel && root.isStatsLoading
                ? root.isStatsLoading(root.vmid) : false
            readonly property bool hasGraph: !loading && statsData && !statsData.error

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: {
                        if (statsPanel.loading) return "Loading stats…"
                        if (!statsPanel.statsData) return ""
                        if (statsPanel.statsData.error) return "Error: " + statsPanel.statsData.error
                        const ip = statsPanel.statsData.ip
                        if (!ip) {
                            // A stopped guest can't report an IP; say so rather
                            // than blaming the agent/interfaces endpoint.
                            if (!root.isRunning) {
                                return "IP: N/A (" + (root.kind === "qemu" ? "VM" : "container") + " not running)"
                            }
                            switch (statsPanel.statsData.ipStatus) {
                            case "agentUnavailable": return "IP: N/A (QEMU guest agent not available)"
                            case "forbidden":        return "IP: N/A (permission denied)"
                            case "unavailable":      return "IP: N/A (container interfaces unavailable)"
                            case "noAddress":        return "IP: N/A (no IPv4 address reported)"
                            default:                 return "IP: N/A"
                            }
                        }
                        return "IP: " + (root.anonymizeIp ? root.anonymizeIp(ip) : ip)
                    }
                    font.pixelSize: 10
                    font.family: "JetBrains Mono"
                    color: Kirigami.Theme.textColor
                    opacity: 0.85
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 10; height: 3; radius: 1.5
                    color: root.uiCpuColor
                    visible: statsPanel.hasGraph
                }
                Text { text: "CPU"; font.pixelSize: 9; opacity: 0.7; visible: statsPanel.hasGraph }
                Rectangle {
                    width: 10; height: 3; radius: 1.5
                    color: root.uiMemColor
                    visible: statsPanel.hasGraph
                }
                Text { text: "Mem"; font.pixelSize: 9; opacity: 0.7; visible: statsPanel.hasGraph }
            }

            Canvas {
                id: statsCanvas
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                visible: statsPanel.hasGraph
                property var rrd: statsPanel.statsData && statsPanel.statsData.rrd
                    ? statsPanel.statsData.rrd : []
                onRrdChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    // Faint background grid: 6 columns = 10-minute blocks across
                    // the hour-long timeframe we fetch; 6 rows to match.
                    ctx.strokeStyle = Qt.rgba(Kirigami.Theme.textColor.r,
                                              Kirigami.Theme.textColor.g,
                                              Kirigami.Theme.textColor.b, 0.12)
                    ctx.lineWidth = 1
                    ctx.beginPath()
                    for (let gy = 0; gy <= 6; gy++) {
                        const gridY = Math.round((gy / 6) * height) + 0.5
                        ctx.moveTo(0, gridY)
                        ctx.lineTo(width, gridY)
                    }
                    for (let gx = 0; gx <= 6; gx++) {
                        const gridX = Math.round((gx / 6) * width) + 0.5
                        ctx.moveTo(gridX, 0)
                        ctx.lineTo(gridX, height)
                    }
                    ctx.stroke()

                    if (!rrd || rrd.length < 2) {
                        ctx.fillStyle = Qt.rgba(Kirigami.Theme.textColor.r,
                                                Kirigami.Theme.textColor.g,
                                                Kirigami.Theme.textColor.b, 0.4)
                        ctx.font = "10px sans-serif"
                        ctx.fillText("No history yet", 4, height / 2)
                        return
                    }
                    function drawSeries(getValue, color) {
                        ctx.strokeStyle = color
                        ctx.lineWidth = 1.5
                        ctx.beginPath()
                        let started = false
                        for (let i = 0; i < rrd.length; i++) {
                            const v = getValue(rrd[i])
                            if (v === null || v === undefined) continue
                            const x = (i / (rrd.length - 1)) * width
                            const y = height - (Math.max(0, Math.min(100, v)) / 100) * height
                            if (!started) { ctx.moveTo(x, y); started = true }
                            else { ctx.lineTo(x, y) }
                        }
                        ctx.stroke()
                    }
                    drawSeries(function(p) {
                        return (p.cpu !== undefined && p.cpu !== null) ? p.cpu * 100 : null
                    }, root.uiCpuColor)
                    drawSeries(function(p) {
                        return (p.mem !== undefined && p.mem !== null && p.maxmem)
                            ? (p.mem / p.maxmem * 100) : null
                    }, root.uiMemColor)
                }
            }
        }
    }
}
