import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    required property var endpoint
    property string sessionKey: endpoint ? endpoint.sessionKey : ""
    property string endpointLabel: endpoint && endpoint.label ? endpoint.label : (endpoint ? endpoint.host : "")
    property string endpointError: endpoint && endpoint.error ? endpoint.error : ""
    property bool endpointOffline: endpoint && endpoint.offline
    property var nodes: endpoint && endpoint.nodes ? endpoint.nodes : []
    property int uiRadiusL: 8
    property real uiBorderOpacity: 0.22
    property real uiMutedTextOpacity: 0.68
    property int scrollbarReserve: 0
    property var safeCpuPercent: null
    property var anonymizeNodeName: null
    property var anonymizeVmId: null
    property var anonymizeVmName: null
    property var anonymizeLxcName: null
    property var getVmsForNodeMulti: null
    property var getLxcForNodeMulti: null
    property var isNodeCollapsed: null
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
    spacing: 8

    Rectangle {
        Layout.fillWidth: true
        Layout.rightMargin: root.scrollbarReserve
        Layout.preferredHeight: 34
        radius: root.uiRadiusL
        color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.10)
        border.color: Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, root.uiBorderOpacity)
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            Kirigami.Icon {
                source: "server-database"
                implicitWidth: 16
                implicitHeight: 16
                opacity: root.uiMutedTextOpacity
            }

            PlasmaComponents.Label {
                text: root.endpointLabel
                font.bold: true
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            PlasmaComponents.Label {
                visible: root.endpointOffline
                text: "Offline"
                color: Kirigami.Theme.negativeTextColor
                font.bold: true
                font.pixelSize: 10
            }

            PlasmaComponents.Label {
                text: root.endpoint ? (root.endpoint.host + ":" + root.endpoint.port) : ""
                opacity: 0.7
                font.pixelSize: 10
            }
        }
    }

    PlasmaComponents.Label {
        visible: root.endpointError !== ""
        text: root.endpointError
        color: Kirigami.Theme.negativeTextColor
        font.pixelSize: 10
        wrapMode: Text.WordWrap
        Layout.leftMargin: 6
        Layout.rightMargin: root.scrollbarReserve
    }

    Repeater {
        model: root.nodes

        delegate: MultiHostNodeSection {
            required property int index
            required property var modelData

            sessionKey: root.sessionKey
            nodeIndex: index
            nodeModel: modelData
            nodeVms: root.getVmsForNodeMulti(root.sessionKey, modelData ? modelData.node : "")
            nodeLxc: root.getLxcForNodeMulti(root.sessionKey, modelData ? modelData.node : "")
            isCollapsed: root.isNodeCollapsed(modelData ? modelData.node : "", root.sessionKey)
            uiRadiusL: root.uiRadiusL
            uiBorderOpacity: root.uiBorderOpacity
            scrollbarReserve: root.scrollbarReserve
            safeCpuPercent: root.safeCpuPercent
            anonymizeNodeName: root.anonymizeNodeName
            anonymizeVmId: root.anonymizeVmId
            anonymizeVmName: root.anonymizeVmName
            anonymizeLxcName: root.anonymizeLxcName
            getRunningVmsForNodeMulti: root.getRunningVmsForNodeMulti
            getTotalVmsForNodeMulti: root.getTotalVmsForNodeMulti
            getRunningLxcForNodeMulti: root.getRunningLxcForNodeMulti
            getTotalLxcForNodeMulti: root.getTotalLxcForNodeMulti
            isActionBusy: root.isActionBusy
            armedActionKey: root.armedActionKey
            armedTimerRunning: root.armedTimerRunning
            armedActionSessionKey: root.armedActionSessionKey
            onToggleCollapsed: root.onToggleCollapsed
            onAction: root.onAction
        }
    }
}
