pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

/**
 * Multi-host view of one node. Identical widgets to the single-host
 * NodeSection; the difference is that every callback carries a session key and
 * the armed-action key is namespaced per endpoint.
 */
ColumnLayout {
    id: root

    required property string sessionKey
    required property int nodeIndex
    required property var nodeModel
    property string nodeName: nodeModel ? nodeModel.node : ""
    // Per-node diffing models owned by the controller (VariantListModel).
    property var vmsModel: null
    property var lxcsModel: null
    property bool isCollapsed: false
    property int uiRadiusL: 8
    property real uiBorderOpacity: 0.22
    property real uiNodeCardOpacity: 0.98
    property real uiWindowOpacity: 1.0
    property color uiNodeColor: Kirigami.Theme.backgroundColor
    property real uiSurfaceAltOpacity: 0.10
    property real uiSurfaceRunningOpacity: 0.12
    property color uiRunningColor: Kirigami.Theme.positiveTextColor
    property color uiStoppedColor: Kirigami.Theme.disabledTextColor
    property int scrollbarReserve: 0
    property var safeCpuPercent: null
    property var anonymizeNodeName: null
    property var anonymizeVmId: null
    property var anonymizeVmName: null
    property var anonymizeLxcName: null
    property var isActionBusy: null
    property string armedActionKey: ""
    property bool armedTimerRunning: false
    property string armedActionSessionKey: ""
    property var onToggleCollapsed: null
    property var onAction: null
    property var onConsole: null
    property string filterText: ""
    property bool consoleEnabled: true
    property bool powerActionsEnabled: true

    // Armed state is stored globally as "<sessionKey>::<rowKey>". Rows only
    // ever see their own endpoint's key, so an armed action on one host can
    // never light up the same vmid on another.
    readonly property string scopedArmedActionKey: root.armedActionSessionKey === root.sessionKey
        ? root.armedActionKey.replace(root.sessionKey + "::", "")
        : ""

    function busyFor(kind, vmid) {
        return !!(root.isActionBusy && root.isActionBusy(root.nodeName, kind, vmid, root.sessionKey))
    }

    function forwardAction(kind, nodeName, vmid, displayName, action) {
        if (typeof root.onAction === "function")
            root.onAction(root.sessionKey, kind, nodeName, vmid, displayName, action)
    }

    property bool reorderEnabled: false
    // (sessionKey, kind, nodeName, from, to)
    property var onReorder: null

    function forwardReorder(kind, from, to) {
        if (typeof root.onReorder === "function")
            root.onReorder(root.sessionKey, kind, root.nodeName, from, to)
    }

    function forwardConsole(kind, nodeName, vmid, displayName) {
        if (typeof root.onConsole === "function")
            root.onConsole(root.sessionKey, kind, nodeName, vmid, displayName)
    }

    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    spacing: 4

    NodeCard {
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
            if (typeof root.onToggleCollapsed === "function")
                root.onToggleCollapsed(root.nodeName, root.sessionKey)
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
            uiRowHeight: 28
            uiRadiusS: 4
            uiSurfaceRunningOpacity: root.uiSurfaceRunningOpacity
            uiSurfaceAltOpacity: root.uiSurfaceAltOpacity
            uiRunningColor: root.uiRunningColor
            uiStoppedColor: root.uiStoppedColor
            uiWindowOpacity: root.uiWindowOpacity
            scrollbarReserve: 0
            armedActionKey: root.scopedArmedActionKey
            armedTimerRunning: root.armedTimerRunning
            busyFor: root.busyFor
            reorderEnabled: root.reorderEnabled
            onReorder: root.forwardReorder
            anonymizeVmId: root.anonymizeVmId
            anonymizeName: root.anonymizeVmName
            onAction: root.forwardAction
            onConsole: root.forwardConsole
            statsEnabled: false
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
            uiRowHeight: 28
            uiRadiusS: 4
            uiSurfaceRunningOpacity: root.uiSurfaceRunningOpacity
            uiSurfaceAltOpacity: root.uiSurfaceAltOpacity
            uiRunningColor: root.uiRunningColor
            uiStoppedColor: root.uiStoppedColor
            uiWindowOpacity: root.uiWindowOpacity
            scrollbarReserve: 0
            armedActionKey: root.scopedArmedActionKey
            armedTimerRunning: root.armedTimerRunning
            busyFor: root.busyFor
            reorderEnabled: root.reorderEnabled
            onReorder: root.forwardReorder
            anonymizeVmId: root.anonymizeVmId
            anonymizeName: root.anonymizeLxcName
            onAction: root.forwardAction
            onConsole: root.forwardConsole
            statsEnabled: false
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
