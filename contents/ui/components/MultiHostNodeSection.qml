import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    required property string sessionKey
    required property int nodeIndex
    required property var nodeModel
    property string nodeName: nodeModel ? nodeModel.node : ""
    property var nodeVms: []
    property var nodeLxc: []
    property bool isCollapsed: false
    property int uiRadiusL: 8
    property real uiBorderOpacity: 0.22
    property real uiNodeCardOpacity: 0.98
    property color uiRunningColor: Kirigami.Theme.positiveTextColor
    property color uiStoppedColor: Kirigami.Theme.disabledTextColor
    property int scrollbarReserve: 0
    property var safeCpuPercent: null
    property var anonymizeNodeName: null
    property var anonymizeVmId: null
    property var anonymizeVmName: null
    property var anonymizeLxcName: null
    property var getRunningVmsForNodeMulti: null
    property var getTotalVmsForNodeMulti: null
    property var getRunningLxcForNodeMulti: null
    property var getTotalLxcForNodeMulti: null
    property var isActionBusy: null
    property string armedActionKey: ""
    property bool armedTimerRunning: false
    property string armedActionSessionKey: ""
    property var onToggleCollapsed: null
    property var onAction: null

    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    spacing: 4

    Rectangle {
        Layout.fillWidth: true
        Layout.rightMargin: root.scrollbarReserve
        Layout.preferredHeight: 70
        radius: root.uiRadiusL
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, root.uiNodeCardOpacity)
        border.color: Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, root.uiBorderOpacity)
        border.width: 1

        MouseArea {
            anchors.fill: parent
            onClicked: if (typeof root.onToggleCollapsed === "function") root.onToggleCollapsed(root.nodeName, root.sessionKey)
            cursorShape: Qt.PointingHandCursor
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                Kirigami.Icon {
                    source: root.isCollapsed ? "arrow-right" : "arrow-down"
                    implicitWidth: 14
                    implicitHeight: 14
                }

                Kirigami.Icon {
                    source: "computer"
                    implicitWidth: 18
                    implicitHeight: 18
                }

                PlasmaComponents.Label {
                    text: root.anonymizeNodeName(root.nodeName, root.nodeIndex)
                    font.bold: true
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    implicitWidth: 52
                    implicitHeight: 16
                    radius: root.uiRadiusL
                    color: root.nodeModel && root.nodeModel.status === "online"
                        ? Qt.rgba(root.uiRunningColor.r, root.uiRunningColor.g, root.uiRunningColor.b, 0.82)
                        : Qt.rgba(root.uiStoppedColor.r, root.uiStoppedColor.g, root.uiStoppedColor.b, 0.82)

                    PlasmaComponents.Label {
                        anchors.centerIn: parent
                        text: root.nodeModel ? root.nodeModel.status : ""
                        color: "white"
                        font.pixelSize: 9
                    }
                }

                Item { }

                RowLayout {
                    spacing: 4
                    visible: root.isCollapsed

                    Kirigami.Icon {
                        source: "computer-symbolic"
                        implicitWidth: 12
                        implicitHeight: 12
                        opacity: 0.7
                    }

                    PlasmaComponents.Label {
                        text: root.getRunningVmsForNodeMulti(root.sessionKey, root.nodeName) + "/" + root.getTotalVmsForNodeMulti(root.sessionKey, root.nodeName)
                        font.pixelSize: 10
                        opacity: 0.7
                    }

                    Item { implicitWidth: 4 }

                    Kirigami.Icon {
                        source: "lxc"
                        implicitWidth: 12
                        implicitHeight: 12
                        opacity: 0.7
                    }

                    PlasmaComponents.Label {
                        text: root.getRunningLxcForNodeMulti(root.sessionKey, root.nodeName) + "/" + root.getTotalLxcForNodeMulti(root.sessionKey, root.nodeName)
                        font.pixelSize: 10
                        opacity: 0.7
                    }
                }
            }

            RowLayout {
                spacing: 12

                PlasmaComponents.Label {
                    text: root.nodeModel ? ("CPU: " + root.safeCpuPercent(root.nodeModel.cpu).toFixed(1) + "%") : ""
                    font.pixelSize: 12
                }

                PlasmaComponents.Label {
                    text: root.nodeModel ? ("Mem: " + (root.nodeModel.mem / 1073741824).toFixed(1) + "/" + (root.nodeModel.maxmem / 1073741824).toFixed(1) + "G") : ""
                    font.pixelSize: 12
                }

                Item { Layout.fillWidth: true }

                PlasmaComponents.Label {
                    text: root.nodeModel ? (Math.floor(root.nodeModel.uptime / 86400) + "d " + Math.floor((root.nodeModel.uptime % 86400) / 3600) + "h") : ""
                    font.pixelSize: 11
                    opacity: 0.7
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: root.scrollbarReserve
        visible: !root.isCollapsed
        spacing: 4

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.nodeVms.length > 0
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
                    text: "VMs (" + root.getRunningVmsForNodeMulti(root.sessionKey, root.nodeName) + "/" + root.nodeVms.length + ")"
                    font.bold: true
                    font.pixelSize: 11
                }
            }

            Repeater {
                model: root.nodeVms

                delegate: VmRow {
                    required property int index
                    required property var modelData

                    vmIndex: index
                    vmModel: modelData
                    nodeName: root.nodeName
                    busy: root.isActionBusy(root.nodeName, "qemu", modelData.vmid, root.sessionKey)
                    armedActionKey: root.armedActionSessionKey === root.sessionKey
                        ? root.armedActionKey.replace(root.sessionKey + "::", "")
                        : ""
                    armedTimerRunning: root.armedTimerRunning
                    uiRowHeight: 28
                    uiRadiusS: 4
                    uiSurfaceRunningOpacity: 0.15
                    uiSurfaceAltOpacity: 0.10
                    uiRunningColor: root.uiRunningColor
                    uiStoppedColor: root.uiStoppedColor
                    scrollbarReserve: 0
                    anonymizeVmId: root.anonymizeVmId
                    anonymizeVmName: root.anonymizeVmName
                    onAction: function(kind, nodeName, vmid, displayName, action) {
                        if (typeof root.onAction === "function") root.onAction(root.sessionKey, kind, nodeName, vmid, displayName, action)
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.nodeLxc.length > 0
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
                    text: "Containers (" + root.getRunningLxcForNodeMulti(root.sessionKey, root.nodeName) + "/" + root.nodeLxc.length + ")"
                    font.bold: true
                    font.pixelSize: 11
                }
            }

            Repeater {
                model: root.nodeLxc

                delegate: LxcRow {
                    required property int index
                    required property var modelData

                    ctIndex: index
                    ctModel: modelData
                    nodeName: root.nodeName
                    busy: root.isActionBusy(root.nodeName, "lxc", modelData.vmid, root.sessionKey)
                    armedActionKey: root.armedActionSessionKey === root.sessionKey
                        ? root.armedActionKey.replace(root.sessionKey + "::", "")
                        : ""
                    armedTimerRunning: root.armedTimerRunning
                    uiRowHeight: 28
                    uiRadiusS: 4
                    uiSurfaceRunningOpacity: 0.15
                    uiSurfaceAltOpacity: 0.10
                    uiRunningColor: root.uiRunningColor
                    uiStoppedColor: root.uiStoppedColor
                    scrollbarReserve: 0
                    anonymizeVmId: root.anonymizeVmId
                    anonymizeLxcName: root.anonymizeLxcName
                    onAction: function(kind, nodeName, vmid, displayName, action) {
                        if (typeof root.onAction === "function") root.onAction(root.sessionKey, kind, nodeName, vmid, displayName, action)
                    }
                }
            }
        }

        PlasmaComponents.Label {
            text: "No VMs or Containers"
            visible: root.nodeVms.length === 0 && root.nodeLxc.length === 0
            opacity: 0.5
            font.pixelSize: 10
            Layout.leftMargin: 4
        }
    }
}
