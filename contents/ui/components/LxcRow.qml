import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property var ctModel: null
    property string nodeName: ""
    property int ctIndex: 0
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
    property var anonymizeVmId: null
    property var anonymizeLxcName: null
    property var onAction: null

    Layout.fillWidth: true
    Layout.preferredHeight: uiRowHeight
    radius: uiRadiusS

    color: ctModel && ctModel.status === "running"
        ? Qt.rgba(root.uiRunningColor.r, root.uiRunningColor.g, root.uiRunningColor.b, uiSurfaceRunningOpacity * root.uiWindowOpacity)
        : Qt.rgba(root.uiStoppedColor.r, root.uiStoppedColor.g, root.uiStoppedColor.b, uiSurfaceAltOpacity * root.uiWindowOpacity)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 6

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
            elide: Text.ElideRight
            font.pixelSize: 11
        }

        Item { Layout.fillWidth: true }

        RowLayout {
            Layout.preferredWidth: 68
            Layout.minimumWidth: 68
            Layout.maximumWidth: 68
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            PlasmaComponents.Label {
                text: root.ctModel
                    ? (root.ctModel.status === "running"
                       ? (root.ctModel.cpu * 100).toFixed(0) + "%"
                       : root.ctModel.status)
                    : ""
                font.pixelSize: 10
                opacity: 0.7
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: 32
                Layout.minimumWidth: 32
                Layout.maximumWidth: 32
            }

            PlasmaComponents.Label {
                text: root.ctModel && root.ctModel.status === "running" ? "|" : ""
                font.pixelSize: 10
                opacity: 0.7
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: 4
                Layout.minimumWidth: 4
                Layout.maximumWidth: 4
                Layout.leftMargin: 2
                Layout.rightMargin: 2
            }

            PlasmaComponents.Label {
                text: root.ctModel && root.ctModel.status === "running"
                    ? (root.ctModel.mem / 1073741824).toFixed(1) + "G"
                    : ""
                font.pixelSize: 10
                opacity: 0.7
                horizontalAlignment: Text.AlignLeft
                Layout.preferredWidth: 32
                Layout.minimumWidth: 32
                Layout.maximumWidth: 32
                Layout.leftMargin: 2
            }
        }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.preferredWidth: 70
            Layout.minimumWidth: 70
            Layout.maximumWidth: 70
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            Layout.preferredHeight: 28
            Layout.minimumHeight: 28
            Layout.maximumHeight: 28

            PlasmaComponents.BusyIndicator {
                visible: root.busy
                running: root.busy
                implicitWidth: 16
                implicitHeight: 16
            }

            PlasmaComponents.ToolButton {
                flat: true
                icon.name: (root.armedActionKey === ("lxc:" + root.nodeName + ":" + root.ctModel.vmid + ":start") && root.armedTimerRunning)
                    ? "dialog-ok"
                    : "media-playback-start"
                implicitWidth: 22
                implicitHeight: 22
                visible: root.ctModel && !root.busy && root.ctModel.status !== "running"

                PlasmaComponents.ToolTip { text: "Start" }

                background: Rectangle {
                    radius: 4
                    color: parent.hovered
                        ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                        : "transparent"
                }

                onClicked: if (typeof root.onAction === "function") root.onAction("lxc", root.nodeName, root.ctModel.vmid, root.ctModel.name, "start")
            }
            Item { implicitWidth: 22; implicitHeight: 22; visible: !root.ctModel || root.busy || root.ctModel.status === "running" }

            PlasmaComponents.ToolButton {
                flat: true
                icon.name: (root.armedActionKey === ("lxc:" + root.nodeName + ":" + root.ctModel.vmid + ":shutdown") && root.armedTimerRunning)
                    ? "dialog-ok"
                    : "system-shutdown"
                implicitWidth: 22
                implicitHeight: 22
                visible: root.ctModel && !root.busy && root.ctModel.status === "running"

                PlasmaComponents.ToolTip { text: "Shutdown" }

                background: Rectangle {
                    radius: 4
                    color: parent.hovered
                        ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.18)
                        : "transparent"
                }

                onClicked: if (typeof root.onAction === "function") root.onAction("lxc", root.nodeName, root.ctModel.vmid, root.ctModel.name, "shutdown")
            }
            Item { implicitWidth: 22; implicitHeight: 22; visible: !root.ctModel || root.busy || root.ctModel.status !== "running" }

            PlasmaComponents.ToolButton {
                flat: true
                icon.name: (root.armedActionKey === ("lxc:" + root.nodeName + ":" + root.ctModel.vmid + ":reboot") && root.armedTimerRunning)
                    ? "dialog-ok"
                    : "system-reboot"
                implicitWidth: 22
                implicitHeight: 22
                visible: root.ctModel && !root.busy && root.ctModel.status === "running"

                PlasmaComponents.ToolTip { text: "Reboot" }

                background: Rectangle {
                    radius: 4
                    color: parent.hovered
                        ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.18)
                        : "transparent"
                }

                onClicked: if (typeof root.onAction === "function") root.onAction("lxc", root.nodeName, root.ctModel.vmid, root.ctModel.name, "reboot")
            }
            Item { implicitWidth: 22; implicitHeight: 22; visible: !root.ctModel || root.busy || root.ctModel.status !== "running" }
        }

        Item {
            Layout.preferredWidth: root.scrollbarReserve
            Layout.minimumWidth: root.scrollbarReserve
        }
    }
}
