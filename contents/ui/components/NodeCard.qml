pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

/**
 * Header card for one Proxmox node, shared by the single-host and multi-host
 * views so the two can't drift apart.
 *
 * Guest counts appear only while the node is collapsed. Expanded, the section
 * headers below the card already carry them, and the footer carries them
 * again — three simultaneous copies of the same two numbers was the single
 * largest redundancy in the old panel.
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

    function loadColorFor(fraction) {
        if (fraction >= 0.90) return Kirigami.Theme.negativeTextColor
        if (fraction >= 0.75) return Kirigami.Theme.neutralTextColor
        return card.uiCpuColor
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
        anchors.margins: 9
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 7

            Kirigami.Icon {
                source: card.isCollapsed ? "arrow-right" : "arrow-down"
                implicitWidth: 12
                implicitHeight: 12
                opacity: 0.8
            }

            Kirigami.Icon {
                source: "computer"
                implicitWidth: 16
                implicitHeight: 16
            }

            PlasmaComponents.Label {
                text: card.anonymizeNodeName
                ? card.anonymizeNodeName(card.nodeName, card.nodeIndex)
                : card.nodeName
                font.bold: true
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // Only while collapsed: with the sections hidden this is the one
            // place the guest counts can live.
            RowLayout {
                spacing: 4
                visible: card.isCollapsed

                Kirigami.Icon {
                    source: "vm"
                    implicitWidth: 12
                    implicitHeight: 12
                    opacity: 0.7
                }

                PlasmaComponents.Label {
                    text: (card.vmsModel ? card.vmsModel.runningCount : 0)
                    + "/" + (card.vmsModel ? card.vmsModel.count : 0)
                    font.pixelSize: 10
                    font.family: "JetBrains Mono"
                    opacity: 0.7
                }

                Item { implicitWidth: 2 }

                Kirigami.Icon {
                    source: "lxc"
                    implicitWidth: 12
                    implicitHeight: 12
                    opacity: 0.7
                }

                PlasmaComponents.Label {
                    text: (card.lxcsModel ? card.lxcsModel.runningCount : 0)
                    + "/" + (card.lxcsModel ? card.lxcsModel.count : 0)
                    font.pixelSize: 10
                    font.family: "JetBrains Mono"
                    opacity: 0.7
                }
            }

            RowLayout {
                visible: !card.isCollapsed
                spacing: 3
                opacity: 0.6

                Kirigami.Icon {
                    source: "chronometer"
                    implicitWidth: 12
                    implicitHeight: 12
                }

                PlasmaComponents.Label {
                    text: card.nodeModel
                    ? (Math.floor(card.nodeModel.uptime / 86400) + "d "
                    + Math.floor((card.nodeModel.uptime % 86400) / 3600) + "h")
                    : ""
                    font.pixelSize: 10
                    font.family: "JetBrains Mono"
                }
            }

            // Tinted chip rather than a solid fill with hardcoded white text,
            // which only happened to be legible on dark themes.
            Rectangle {
                implicitHeight: 16
                implicitWidth: statusLabel.implicitWidth + 14
                radius: 8
                color: {
                    const c = card.isOnline ? card.uiRunningColor : card.uiStoppedColor
                    return Qt.rgba(c.r, c.g, c.b, 0.12)
                }
                border.width: 0
                border.color: {
                    const c = card.isOnline ? card.uiRunningColor : card.uiStoppedColor
                    return Qt.rgba(c.r, c.g, c.b, 0.45)
                }

                PlasmaComponents.Label {
                    id: statusLabel
                    anchors.centerIn: parent
                    text: card.nodeModel ? card.nodeModel.status : ""
                    color: card.isOnline ? card.uiRunningColor : card.uiStoppedColor
                    font.pixelSize: 9
                    font.bold: true
                }
            }
        }

        // Two columns: CPU over memory on the left, the storage bars on the
        // right, so a node with several stores grows downwards, not sideways.
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                spacing: 5

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        PlasmaComponents.Label {
                            text: "CPU"
                            font.pixelSize: 9
                            opacity: 0.6
                        }

                        PlasmaComponents.Label {
                            text: card.nodeModel && card.safeCpuPercent
                            ? card.safeCpuPercent(card.nodeModel.cpu).toFixed(1) + "%" : "–"
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignLeft
                            font.pixelSize: 10
                            font.family: "JetBrains Mono"
                        }
                    }

                    UsageMeter {
                        Layout.fillWidth: true
                        implicitHeight: 3
                        value: card.cpuFraction
                        barColor: card.loadColorFor(card.cpuFraction)
                        trackOpacity: 0.10
                    }
                }

                ColumnLayout {
                    id: memColumn
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 5

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        PlasmaComponents.Label {
                            text: "MEM"
                            font.pixelSize: 9
                            opacity: 0.6
                        }

                        PlasmaComponents.Label {
                            text: card.memTotal > 0
                            ? (card.memUsed / card.bytesPerGiB).toFixed(1) + " / "
                            + (card.memTotal / card.bytesPerGiB).toFixed(1) + "G"
                            : "–"
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignLeft
                            font.pixelSize: 10
                            font.family: "JetBrains Mono"
                            elide: Text.ElideRight
                        }
                    }

                    UsageMeter {
                        Layout.fillWidth: true
                        implicitHeight: 3
                        value: card.memFraction
                        barColor: card.memFraction >= 0.90
                        ? Kirigami.Theme.negativeTextColor
                        : (card.memFraction >= 0.75 ? Kirigami.Theme.neutralTextColor : card.uiMemColor)
                        trackOpacity: 0.10
                    }
                }

            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                spacing: 5
                visible: card.hasStorage

                Repeater {
                    model: card.storageBars

                    ColumnLayout {
                        id: storageRow
                        required property int index
                        required property var modelData
                        readonly property real fraction: {
                            const v = Number(storageRow.modelData.fraction)
                            return isFinite(v) && v > 0 ? Math.min(1, v) : 0
                        }

                        Layout.fillWidth: true
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            PlasmaComponents.Label {
                                // The label belongs to the column, not the row.
                                text: storageRow.index === 0 ? "DISK" : ""
                                font.pixelSize: 9
                                opacity: 0.6
                            }

                            PlasmaComponents.Label {
                                text: storageRow.modelData.name + " "
                                + Math.round(storageRow.fraction * 100) + "%"
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignLeft
                                font.pixelSize: 10
                                font.family: "JetBrains Mono"
                                elide: Text.ElideRight
                            }
                        }

                        UsageMeter {
                            Layout.fillWidth: true
                            implicitHeight: 3
                            value: storageRow.fraction
                            barColor: storageRow.fraction >= 0.90
                            ? Kirigami.Theme.negativeTextColor
                            : (storageRow.fraction >= 0.75 ? Kirigami.Theme.neutralTextColor : card.uiDiskColor)
                            trackOpacity: 0.10
                        }
                    }
                }

                HoverHandler { id: storageHover }
                PlasmaComponents.ToolTip.visible: storageHover.hovered && card.storageDetail !== ""
                PlasmaComponents.ToolTip.text: card.storageDetail
            }
        }
    }
}
