pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

/**
 * Header card for one Proxmox node, shared by the single-host and multi-host
 * views so the two can't drift apart.
 *
 * The header is centered: a status dot and the node name, then one line of
 * facts (cores, uptime, guest counts) that shrinks to fit a narrow panel. Below
 * a divider, CPU, memory and storage sit in one row when they fit side by side
 * and wrap to two rows when they don't.
 */
Rectangle {
    id: card

    required property var nodeModel
    required property int nodeIndex
    property string nodeName: nodeModel ? nodeModel.node : ""
    property bool isCollapsed: false
    property var vmsModel: null
    property var lxcsModel: null

    property int uiRadiusL: 8
    property real uiBorderOpacity: 0.22
    property real uiNodeCardOpacity: 0.98
    property real uiWindowOpacity: 1.0
    property color uiNodeColor: Kirigami.Theme.backgroundColor
    property color uiRunningColor: Kirigami.Theme.positiveTextColor
    property color uiStoppedColor: Kirigami.Theme.disabledTextColor
    property color uiCpuColor: "#5cb3fa"
    property color uiMemColor: "#f5a742"
    property color uiDiskColor: "#9d8cf5"

    property var safeCpuPercent: null
    property var anonymizeNodeName: null
    property var onToggleCollapsed: null

    readonly property real bytesPerGiB: 1073741824.0
    readonly property bool isOnline: !!(nodeModel && nodeModel.status === "online")

    // One entry per fact on the detail line. Each is empty when its data is
    // missing, and an empty one is not drawn.
    readonly property int coreCount: {
        const n = Number(card.nodeModel ? card.nodeModel.maxcpu : 0)
        return isFinite(n) && n > 0 ? n : 0
    }
    readonly property string coreText: card.coreCount > 0
    ? card.coreCount + (card.coreCount === 1 ? " core" : " cores") : ""
    readonly property string uptimeText: {
        if (!card.nodeModel || !card.isOnline) return ""
        const up = Number(card.nodeModel.uptime)
        if (!isFinite(up) || up <= 0) return ""
        return "up " + Math.floor(up / 86400) + "d " + Math.floor((up % 86400) / 3600) + "h"
    }
    readonly property string vmText: card.vmsModel
    ? card.vmsModel.runningCount + "/" + card.vmsModel.count + " VMs" : ""
    readonly property string ctText: card.lxcsModel
    ? card.lxcsModel.runningCount + "/" + card.lxcsModel.count + " CTs" : ""

    readonly property real cpuFraction: {
        if (!card.nodeModel || !card.safeCpuPercent) return 0
        const pct = Number(card.safeCpuPercent(card.nodeModel.cpu))
        return isFinite(pct) && pct > 0 ? Math.min(1, pct / 100) : 0
    }
    readonly property real memUsed: {
        if (!card.nodeModel) return 0
        const v = Number(card.nodeModel.mem)
        return isFinite(v) && v > 0 ? v : 0
    }
    readonly property real memTotal: {
        if (!card.nodeModel) return 0
        const v = Number(card.nodeModel.maxmem)
        return isFinite(v) && v > 0 ? v : 0
    }
    readonly property real memFraction: card.memTotal > 0
    ? Math.min(1, card.memUsed / card.memTotal) : 0

    // Storage fields are absent when the node has no usable store, or when
    // the token cannot read /nodes/<node>/storage. The column hides itself
    // rather than drawing an empty bar.
    readonly property string storageName: card.nodeModel && card.nodeModel.storageName
    ? card.nodeModel.storageName : ""
    readonly property real storageFraction: {
        if (!card.nodeModel) return 0
        const v = Number(card.nodeModel.storageFraction)
        return isFinite(v) && v > 0 ? Math.min(1, v) : 0
    }
    readonly property bool hasStorage: card.storageName !== ""
    // One row per monitored store when stores are named in settings,
    // otherwise a single row for the fullest one.
    readonly property var storageBars: card.nodeModel && card.nodeModel.storageBars
    ? card.nodeModel.storageBars : []
    readonly property string storageDetail: card.nodeModel && card.nodeModel.storageDetail
    ? card.nodeModel.storageDetail : ""

    // The bar keeps its own color until the resource gets tight, then goes
    // amber and red.
    function toneFor(fraction, base) {
        if (fraction >= 0.90) return Kirigami.Theme.negativeTextColor
        if (fraction >= 0.75) return Kirigami.Theme.neutralTextColor
        return base
    }

    // The size every icon on the detail line is drawn at. Icon art is drawn for
    // a fixed grid and is only crisp at that size or an even multiple of it, so
    // this is the theme's standard small size and the icons in ui/icons are
    // drawn on a 16 x 16 grid.
    readonly property int statIconSize: 16

    // One fact on the detail line: an icon and a short text. The core count
    // gets a chip drawn on the same 16 x 16 grid, because there is no matching
    // icon. Every edge sits on a whole pixel.
    component DetailStat: RowLayout {
        id: stat

        property url iconUrl: ""
        property bool chip: false
        property string text: ""
        // False when the line has no room left for this fact.
        property bool allowed: true

        visible: stat.text !== "" && stat.allowed
        spacing: 4

        Kirigami.Icon {
            visible: !stat.chip
            source: stat.iconUrl
            implicitWidth: card.statIconSize
            implicitHeight: card.statIconSize
            opacity: 0.7
        }

        Item {
            visible: stat.chip
            implicitWidth: card.statIconSize
            implicitHeight: card.statIconSize
            opacity: 0.7

            Rectangle {
                x: 3
                y: 3
                width: 10
                height: 10
                radius: 1
                color: "transparent"
                border.width: 1
                border.color: Kirigami.Theme.textColor
            }

            Rectangle {
                x: 6
                y: 6
                width: 4
                height: 4
                color: Kirigami.Theme.textColor
            }

            // Two pins on each side, placed so the set is centered on the grid.
            Repeater {
                model: {
                    const pins = []
                    for (const p of [5, 10]) {
                        pins.push({ x: p, y: 1, w: 1, h: 2 }, { x: p, y: 13, w: 1, h: 2 },
                                  { x: 1, y: p, w: 2, h: 1 }, { x: 13, y: p, w: 2, h: 1 })
                    }
                    return pins
                }

                Rectangle {
                    required property var modelData
                    x: modelData.x
                    y: modelData.y
                    width: modelData.w
                    height: modelData.h
                    color: Kirigami.Theme.textColor
                }
            }
        }

        PlasmaComponents.Label {
            text: stat.text
            font.pixelSize: 10
            font.family: "JetBrains Mono"
            opacity: 0.7
        }
    }

    // A label and a right-aligned value over a bar.
    component Meter: ColumnLayout {
        id: meter

        property string label: ""
        property string valueText: ""
        property real fraction: 0
        property color barColor: Kirigami.Theme.highlightColor

        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            PlasmaComponents.Label {
                text: meter.label
                font.pixelSize: 10
                font.family: "JetBrains Mono"
                opacity: 0.6
            }

            PlasmaComponents.Label {
                text: meter.valueText
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                font.pixelSize: 10
                font.family: "JetBrains Mono"
            }
        }

        UsageMeter {
            Layout.fillWidth: true
            implicitHeight: 6
            value: meter.fraction
            barColor: meter.barColor
            trackOpacity: 0.10
        }
    }

    Layout.fillWidth: true
    // Content drives the height so extra storage rows reflow the card.
    Layout.preferredHeight: Math.max(64, cardContent.implicitHeight + cardContent.anchors.margins * 2)
    radius: uiRadiusL
    color: Qt.rgba(uiNodeColor.r, uiNodeColor.g, uiNodeColor.b,
    uiNodeCardOpacity * uiWindowOpacity)
    border.color: Qt.rgba(Kirigami.Theme.disabledTextColor.r,
    Kirigami.Theme.disabledTextColor.g,
    Kirigami.Theme.disabledTextColor.b,
    cardHover.hovered ? card.uiBorderOpacity * 1.4 : card.uiBorderOpacity * 0.65)
    border.width: 1

    Behavior on border.color {
        ColorAnimation { duration: 120 }
    }

    HoverHandler {
        id: cardHover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: if (typeof card.onToggleCollapsed === "function") card.onToggleCollapsed()
    }

    ColumnLayout {
        id: cardContent
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // The whole header is centered. Clicking the card collapses or
        // expands the node, and the pointer turns into a hand to say so.
        Item {
            id: header
            Layout.fillWidth: true
            implicitHeight: headerColumn.implicitHeight

            ColumnLayout {
                id: headerColumn
                anchors.fill: parent
                spacing: 4

                RowLayout {
                    id: nameRow
                    // A layout inside a layout fills the width by default, which
                    // would pack the dot and name to the left edge. It is placed
                    // with a rounded margin, not centered by the layout, which
                    // can leave it half a pixel off and blur it.
                    readonly property int inset: Math.max(0,
                        Math.round((headerColumn.width - nameRow.implicitWidth) / 2))
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignLeft
                    Layout.leftMargin: nameRow.inset
                    Layout.maximumWidth: headerColumn.width - nameRow.inset
                    spacing: 8

                    // The dot is centered on the label's box, but lowercase
                    // text sits lower in that box, so it is nudged down to
                    // line up with the middle of the letters.
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: 3
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: 4
                        color: card.isOnline ? card.uiRunningColor : card.uiStoppedColor
                    }

                    PlasmaComponents.Label {
                        text: card.anonymizeNodeName
                        ? card.anonymizeNodeName(card.nodeName, card.nodeIndex)
                        : card.nodeName
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    // Only for a node that is not online. The dot already says
                    // "online", and a chip on every healthy node is noise.
                    // Tinted rather than a solid fill with hardcoded white
                    // text, which only happened to be legible on dark themes.
                    Rectangle {
                        visible: !card.isOnline
                        implicitHeight: 16
                        implicitWidth: statusLabel.implicitWidth + 14
                        radius: 8
                        color: Qt.rgba(card.uiStoppedColor.r, card.uiStoppedColor.g,
                                       card.uiStoppedColor.b, 0.12)

                        PlasmaComponents.Label {
                            id: statusLabel
                            anchors.centerIn: parent
                            text: card.nodeModel ? card.nodeModel.status : ""
                            color: card.uiStoppedColor
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }
                }

                // The facts line shrinks to fit, from full size down to 80%.
                // When even that is too wide, facts drop off the right end one
                // at a time, so no text is ever cut through. It is positioned
                // by hand so it stays centered after scaling.
                Item {
                    id: detailBox
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: detailRow.implicitHeight * detailBox.fit
                    visible: card.coreText !== "" || card.uptimeText !== ""
                        || card.vmText !== "" || card.ctText !== ""
                    clip: true

                    readonly property real minScale: 0.8
                    readonly property real fit: detailRow.implicitWidth > 0
                        ? Math.max(detailBox.minScale, Math.min(1, detailBox.width / detailRow.implicitWidth)) : 1

                    // The facts use a monospace font, so one measured character
                    // gives the width of any of them. The width of a fact is
                    // worked out before anything is drawn.
                    TextMetrics {
                        id: cellMetrics
                        text: "0"
                        font.pixelSize: 10
                        font.family: "JetBrains Mono"
                    }

                    function factWidth(text) {
                        return card.statIconSize + 4 + text.length * cellMetrics.advanceWidth
                    }

                    // The last fact that fits at the smallest size. The first
                    // fact is always kept.
                    readonly property int lastSlot: {
                        const texts = [card.coreText, card.uptimeText, card.vmText, card.ctText]
                        const room = detailBox.width / detailBox.minScale
                        let used = 0
                        let last = -1
                        for (let i = 0; i < texts.length; i++) {
                            if (texts[i] === "") continue
                            const next = used + (last >= 0 ? detailRow.spacing : 0) + detailBox.factWidth(texts[i])
                            if (last >= 0 && next > room) break
                            used = next
                            last = i
                        }
                        return last
                    }

                    RowLayout {
                        id: detailRow
                        spacing: 16
                        transformOrigin: Item.TopLeft
                        scale: detailBox.fit
                        x: Math.max(0, Math.round((detailBox.width - detailRow.width * detailBox.fit) / 2))

                        DetailStat { chip: true; text: card.coreText; allowed: 0 <= detailBox.lastSlot }
                        DetailStat { iconUrl: Qt.resolvedUrl("../icons/clock-16.svg"); text: card.uptimeText; allowed: 1 <= detailBox.lastSlot }
                        DetailStat { iconUrl: Qt.resolvedUrl("../icons/vm-16.svg"); text: card.vmText; allowed: 2 <= detailBox.lastSlot }
                        DetailStat { iconUrl: Qt.resolvedUrl("../icons/lxc-16.svg"); text: card.ctText; allowed: 3 <= detailBox.lastSlot }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Qt.rgba(Kirigami.Theme.textColor.r,
                           Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, 0.08)
        }

        // CPU, memory and storage in one row when their text fits side by
        // side. Otherwise storage wraps under the other two, and on a very
        // narrow panel the two meters stack.
        GridLayout {
            id: meters
            Layout.fillWidth: true
            columnSpacing: 16
            rowSpacing: 10

            readonly property real needed: cpuMeter.implicitWidth + memMeter.implicitWidth
                + (card.hasStorage ? diskColumn.implicitWidth : 0)
                + (card.hasStorage ? 2 : 1) * meters.columnSpacing
            // Compared against the card's width, which is known before this grid
            // is laid out. Its own width is not, and using it makes the grid
            // switch layouts while it is still being measured.
            readonly property bool oneRow: cardContent.width >= meters.needed

            columns: card.hasStorage ? (meters.oneRow ? 3 : 2) : (meters.oneRow ? 2 : 1)

            Meter {
                id: cpuMeter
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: cpuMeter.implicitWidth
                Layout.alignment: Qt.AlignTop
                label: "CPU"
                valueText: card.nodeModel && card.safeCpuPercent
                    ? card.safeCpuPercent(card.nodeModel.cpu).toFixed(1) + "%" : "–"
                fraction: card.cpuFraction
                barColor: card.toneFor(card.cpuFraction, card.uiCpuColor)
            }

            Meter {
                id: memMeter
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: memMeter.implicitWidth
                Layout.alignment: Qt.AlignTop
                label: "MEM"
                valueText: card.memTotal > 0
                    ? (card.memUsed / card.bytesPerGiB).toFixed(1) + " / "
                    + (card.memTotal / card.bytesPerGiB).toFixed(1) + "G · "
                    + Math.round(card.memFraction * 100) + "%"
                    : "–"
                fraction: card.memFraction
                barColor: card.toneFor(card.memFraction, card.uiMemColor)
            }

            ColumnLayout {
                id: diskColumn
                visible: card.hasStorage
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: diskColumn.implicitWidth
                Layout.columnSpan: meters.columns === 3 ? 1 : meters.columns
                Layout.alignment: Qt.AlignTop
                spacing: 6

                Repeater {
                    model: card.storageBars

                    Meter {
                        id: diskMeter
                        required property int index
                        required property var modelData
                        readonly property real clamped: {
                            const v = Number(diskMeter.modelData.fraction)
                            return isFinite(v) && v > 0 ? Math.min(1, v) : 0
                        }

                        Layout.fillWidth: true
                        // The label belongs to the column, not the row.
                        label: diskMeter.index === 0 ? "DISK" : ""
                        valueText: diskMeter.modelData.name + " " + Math.round(diskMeter.clamped * 100) + "%"
                        fraction: diskMeter.clamped
                        barColor: card.toneFor(diskMeter.clamped, card.uiDiskColor)
                    }
                }

                HoverHandler { id: storageHover }
                PlasmaComponents.ToolTip.visible: storageHover.hovered && card.storageDetail !== ""
                PlasmaComponents.ToolTip.text: card.storageDetail
            }
        }
    }
}
