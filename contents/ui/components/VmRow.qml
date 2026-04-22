import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

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
    property var anonymizeVmId: null
    property var anonymizeVmName: null
    property var onAction: null

    Layout.fillWidth: true
    Layout.preferredHeight: uiRowHeight
    radius: uiRadiusS

    color: vmModel && vmModel.status === "running"
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
            color: root.vmModel && root.vmModel.status === "running" ? root.uiRunningColor : root.uiStoppedColor
        }

        PlasmaComponents.Label {
            text: root.vmModel
                ? (root.anonymizeVmId(root.vmModel.vmid, root.vmIndex) + ": " + root.anonymizeVmName(root.vmModel.name, root.vmIndex))
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
                text: root.vmModel
                    ? (root.vmModel.status === "running"
                       ? (root.vmModel.cpu * 100).toFixed(0) + "%"
                       : root.vmModel.status)
                    : ""
                font.pixelSize: 10
                opacity: 0.7
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: 32
                Layout.minimumWidth: 32
                Layout.maximumWidth: 32
            }

            PlasmaComponents.Label {
                text: root.vmModel && root.vmModel.status === "running" ? "|" : ""
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
                text: root.vmModel && root.vmModel.status === "running"
                    ? (root.vmModel.mem / 1073741824).toFixed(1) + "G"
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

        Row {
            spacing: 4
            visible: root.vmModel && root.vmModel.backupStatus !== undefined && root.vmModel.backupStatus !== 0

            Rectangle {
                width: 8
                height: 8
                radius: 4
                anchors.verticalCenter: parent.verticalCenter
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

            PlasmaComponents.Label {
                text: root.vmModel ? (root.vmModel.lastBackupDisplay || "") : ""
                font.pixelSize: 8
                opacity: 0.8
                color: root.vmModel && root.vmModel.verifyState === "failed"
                    ? Kirigami.Theme.negativeTextColor
                    : Kirigami.Theme.textColor
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
                icon.name: (root.armedActionKey === ("qemu:" + root.nodeName + ":" + root.vmModel.vmid + ":start") && root.armedTimerRunning)
                    ? "dialog-ok"
                    : "media-playback-start"
                implicitWidth: 22
                implicitHeight: 22
                visible: root.vmModel && !root.busy && root.vmModel.status !== "running"

                PlasmaComponents.ToolTip { text: "Start" }

                background: Rectangle {
                    radius: 4
                    color: parent.hovered
                        ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                        : "transparent"
                }

                onClicked: if (typeof root.onAction === "function") root.onAction("qemu", root.nodeName, root.vmModel.vmid, root.vmModel.name, "start")
            }
            Item { implicitWidth: 22; implicitHeight: 22; visible: !root.vmModel || root.busy || root.vmModel.status === "running" }

            PlasmaComponents.ToolButton {
                flat: true
                icon.name: (root.armedActionKey === ("qemu:" + root.nodeName + ":" + root.vmModel.vmid + ":shutdown") && root.armedTimerRunning)
                    ? "dialog-ok"
                    : "system-shutdown"
                implicitWidth: 22
                implicitHeight: 22
                visible: root.vmModel && !root.busy && root.vmModel.status === "running"

                PlasmaComponents.ToolTip { text: "Shutdown" }

                background: Rectangle {
                    radius: 4
                    color: parent.hovered
                        ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.18)
                        : "transparent"
                }

                onClicked: if (typeof root.onAction === "function") root.onAction("qemu", root.nodeName, root.vmModel.vmid, root.vmModel.name, "shutdown")
            }
            Item { implicitWidth: 22; implicitHeight: 22; visible: !root.vmModel || root.busy || root.vmModel.status !== "running" }

            PlasmaComponents.ToolButton {
                flat: true
                icon.name: (root.armedActionKey === ("qemu:" + root.nodeName + ":" + root.vmModel.vmid + ":reboot") && root.armedTimerRunning)
                    ? "dialog-ok"
                    : "system-reboot"
                implicitWidth: 22
                implicitHeight: 22
                visible: root.vmModel && !root.busy && root.vmModel.status === "running"

                PlasmaComponents.ToolTip { text: "Reboot" }

                background: Rectangle {
                    radius: 4
                    color: parent.hovered
                        ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.18)
                        : "transparent"
                }

                onClicked: if (typeof root.onAction === "function") root.onAction("qemu", root.nodeName, root.vmModel.vmid, root.vmModel.name, "reboot")
            }
            Item { implicitWidth: 22; implicitHeight: 22; visible: !root.vmModel || root.busy || root.vmModel.status !== "running" }
        }

        Item {
            Layout.preferredWidth: root.scrollbarReserve
            Layout.minimumWidth: root.scrollbarReserve
        }
    }
}
