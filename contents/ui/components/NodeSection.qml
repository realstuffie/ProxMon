pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

/**
 * Single-host view of one node: the node card plus its VM and container
 * sections. The card and the rows themselves live in NodeCard/GuestSection so
 * the multi-host view renders exactly the same widgets.
 */
ColumnLayout {
    id: root

    required property int nodeIndex
    required property var nodeModel
    property string nodeName: nodeModel ? nodeModel.node : ""
    // Per-node diffing models owned by the controller (VariantListModel).
    property var vmsModel: null
    property var lxcsModel: null
    property bool isCollapsed: false
    property int uiRadiusS: 4
    property int uiRadiusL: 8
    property real uiBorderOpacity: 0.22
    property real uiSurfaceAltOpacity: 0.10
    property real uiSurfaceRunningOpacity: 0.12
    property real uiNodeCardOpacity: 0.98
    property real uiWindowOpacity: 1.0
    property color uiNodeColor: Kirigami.Theme.backgroundColor
    property color uiRunningColor: Kirigami.Theme.positiveTextColor
    property color uiStoppedColor: Kirigami.Theme.disabledTextColor
    property int uiRowHeight: 30
    property int scrollbarReserve: 0
    property var safeCpuPercent: null
    property var anonymizeNodeName: null
    property var anonymizeVmId: null
    property var anonymizeVmName: null
    property var anonymizeLxcName: null
    property var anonymizeIp: null
    property var isActionBusy: null
    property string armedActionKey: ""
    property bool armedTimerRunning: false
    property var onToggleCollapsed: null
    property var onAction: null
    property var onConsole: null
    property var onStatsToggled: null
    property var getStatsData: null
    property var isStatsLoading: null
    property string filterText: ""
    property bool statsEnabled: true
    property bool consoleEnabled: true
    property bool powerActionsEnabled: true

    function busyFor(kind, vmid) {
        return !!(root.isActionBusy && root.isActionBusy(root.nodeName, kind, vmid))
    }

    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    spacing: 4

    NodeCard {
        Layout.leftMargin: 12
        Layout.rightMargin: root.scrollbarReserve
        nodeModel: root.nodeModel
        nodeIndex: root.nodeIndex
        nodeName: root.nodeName
        isCollapsed: root.isCollapsed
        vmsModel: root.vmsModel
        lxcsModel: root.lxcsModel
        uiRadiusL: root.uiRadiusL
        uiBorderOpacity: root.uiBorderOpacity
        uiNodeCardOpacity: root.uiNodeCardOpacity
        uiWindowOpacity: root.uiWindowOpacity
        uiNodeColor: root.uiNodeColor
        uiRunningColor: root.uiRunningColor
        uiStoppedColor: root.uiStoppedColor
        safeCpuPercent: root.safeCpuPercent
        anonymizeNodeName: root.anonymizeNodeName
        onToggleCollapsed: function() {
            if (typeof root.onToggleCollapsed === "function") root.onToggleCollapsed(root.nodeName)
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: root.scrollbarReserve
        visible: !root.isCollapsed
        spacing: 5

        GuestSection {
            id: vmSection
            kind: "qemu"
            title: "VMs"
            iconName: "vm"
            guestsModel: root.vmsModel
            nodeName: root.nodeName
            filterText: root.filterText
            uiRowHeight: root.uiRowHeight
            uiRadiusS: root.uiRadiusS
            uiSurfaceRunningOpacity: root.uiSurfaceRunningOpacity
            uiSurfaceAltOpacity: root.uiSurfaceAltOpacity
            uiRunningColor: root.uiRunningColor
            uiStoppedColor: root.uiStoppedColor
            uiWindowOpacity: root.uiWindowOpacity
            scrollbarReserve: root.scrollbarReserve
            armedActionKey: root.armedActionKey
            armedTimerRunning: root.armedTimerRunning
            busyFor: root.busyFor
            anonymizeVmId: root.anonymizeVmId
            anonymizeName: root.anonymizeVmName
            anonymizeIp: root.anonymizeIp
            onAction: root.onAction
            onConsole: root.onConsole
            onStatsToggled: root.onStatsToggled
            getStatsData: root.getStatsData
            isStatsLoading: root.isStatsLoading
            statsEnabled: root.statsEnabled
            consoleEnabled: root.consoleEnabled
            powerActionsEnabled: root.powerActionsEnabled
        }

        GuestSection {
            id: lxcSection
            kind: "lxc"
            title: "Containers"
            iconName: "lxc"
            guestsModel: root.lxcsModel
            nodeName: root.nodeName
            filterText: root.filterText
            uiRowHeight: root.uiRowHeight
            uiRadiusS: root.uiRadiusS
            uiSurfaceRunningOpacity: root.uiSurfaceRunningOpacity
            uiSurfaceAltOpacity: root.uiSurfaceAltOpacity
            uiRunningColor: root.uiRunningColor
            uiStoppedColor: root.uiStoppedColor
            uiWindowOpacity: root.uiWindowOpacity
            scrollbarReserve: root.scrollbarReserve
            armedActionKey: root.armedActionKey
            armedTimerRunning: root.armedTimerRunning
            busyFor: root.busyFor
            anonymizeVmId: root.anonymizeVmId
            anonymizeName: root.anonymizeLxcName
            anonymizeIp: root.anonymizeIp
            onAction: root.onAction
            onConsole: root.onConsole
            onStatsToggled: root.onStatsToggled
            getStatsData: root.getStatsData
            isStatsLoading: root.isStatsLoading
            statsEnabled: root.statsEnabled
            consoleEnabled: root.consoleEnabled
            powerActionsEnabled: root.powerActionsEnabled
        }

        PlasmaComponents.Label {
            readonly property bool hasGuests: (root.vmsModel && root.vmsModel.count > 0)
                || (root.lxcsModel && root.lxcsModel.count > 0)

            text: hasGuests ? "No guests match the filter" : "No VMs or Containers"
            visible: !hasGuests
                || (vmSection.matchCount === 0 && lxcSection.matchCount === 0)
            opacity: 0.5
            font.pixelSize: 10
            Layout.leftMargin: 4
        }
    }
}
