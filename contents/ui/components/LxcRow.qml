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
    property int uiActionButtonSize: 22
    property int uiBusyIndicatorSize: 16
    property real uiButtonHoverOpacity: 0.08
    property real uiButtonHoverDangerOpacity: 0.18
    readonly property real bytesPerGiB: 1073741824.0
    property var anonymizeVmId: null
    property var anonymizeLxcName: null
    property var onAction: null
    property var onConsole: null
    property bool consoleEnabled: true

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

        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 1
            Layout.preferredWidth: 80
            Layout.minimumWidth: 80
            Layout.maximumWidth: 80

            PlasmaComponents.Label {
                visible: root.ctModel && root.ctModel.status !== "running"
                text: root.ctModel && root.ctModel.status !== "running" ? root.ctModel.status : ""
                font.pixelSize: 10
                opacity: 0.7
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                visible: root.ctModel && root.ctModel.status === "running"
                text: root.ctModel && root.ctModel.status === "running"
                    ? (root.ctModel.cpu * 100).toFixed(0) + "%"
                    : ""
                font.pixelSize: 10
                opacity: 0.7
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: 28
                Layout.minimumWidth: 28
                Layout.maximumWidth: 28
            }

            PlasmaComponents.Label {
                visible: root.ctModel && root.ctModel.status === "running"
                text: "|"
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
                visible: root.ctModel && root.ctModel.status === "running"
                text: root.ctModel && root.ctModel.status === "running"
                    ? (root.ctModel.mem / root.bytesPerGiB).toFixed(1) + "G"
                    : ""
                font.pixelSize: 10
                opacity: 0.7
                horizontalAlignment: Text.AlignLeft
                Layout.leftMargin: 2
                Layout.preferredWidth: 36
                Layout.minimumWidth: 36
                Layout.maximumWidth: 36
            }
        }

        Row {
            spacing: 4
            Layout.leftMargin: 4
            Layout.preferredWidth: 50
            opacity: (root.ctModel && root.ctModel.backupStatus !== undefined && root.ctModel.backupStatus !== 0) ? 1 : 0

            Rectangle {
                width: 8
                height: 8
                radius: 4
                anchors.verticalCenter: parent.verticalCenter
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

            PlasmaComponents.Label {
                text: root.ctModel ? (root.ctModel.lastBackupDisplay || "") : ""
                font.pixelSize: 8
                opacity: 0.8
                color: root.ctModel && root.ctModel.verifyState === "failed"
                    ? Kirigami.Theme.negativeTextColor
                    : Kirigami.Theme.textColor
            }
        }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.preferredWidth: 92
            Layout.minimumWidth: 92
            Layout.maximumWidth: 92
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            Layout.preferredHeight: 28
            Layout.minimumHeight: 28
            Layout.maximumHeight: 28

            PlasmaComponents.BusyIndicator {
                visible: root.busy
                running: root.busy
                implicitWidth: root.uiBusyIndicatorSize
                implicitHeight: root.uiBusyIndicatorSize
            }

            PlasmaComponents.ToolButton {
                flat: true
                icon.name: (root.armedActionKey === ("lxc:" + root.nodeName + ":" + root.ctModel.vmid + ":start") && root.armedTimerRunning)
                    ? "dialog-ok"
                    : "media-playback-start"
                implicitWidth: root.uiActionButtonSize
                implicitHeight: root.uiActionButtonSize
                visible: root.ctModel && !root.busy && root.ctModel.status !== "running"

                PlasmaComponents.ToolTip { text: "Start" }

                background: Rectangle {
                    radius: 4
                    color: parent.hovered
                        ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, root.uiButtonHoverOpacity)
                        : "transparent"
                }

                onClicked: if (typeof root.onAction === "function") root.onAction("lxc", root.nodeName, root.ctModel.vmid, root.ctModel.name, "start")
            }
            Item { implicitWidth: root.uiActionButtonSize; implicitHeight: root.uiActionButtonSize; visible: !root.ctModel || root.busy || root.ctModel.status === "running" }

            PlasmaComponents.ToolButton {
                flat: true
                icon.name: (root.armedActionKey === ("lxc:" + root.nodeName + ":" + root.ctModel.vmid + ":shutdown") && root.armedTimerRunning)
                    ? "dialog-ok"
                    : "system-shutdown"
                implicitWidth: root.uiActionButtonSize
                implicitHeight: root.uiActionButtonSize
                visible: root.ctModel && !root.busy && root.ctModel.status === "running"

                PlasmaComponents.ToolTip { text: "Shutdown" }

                background: Rectangle {
                    radius: 4
                    color: parent.hovered
                        ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, root.uiButtonHoverDangerOpacity)
                        : "transparent"
                }

                onClicked: if (typeof root.onAction === "function") root.onAction("lxc", root.nodeName, root.ctModel.vmid, root.ctModel.name, "shutdown")
            }
            Item { implicitWidth: root.uiActionButtonSize; implicitHeight: root.uiActionButtonSize; visible: !root.ctModel || root.busy || root.ctModel.status !== "running" }

            PlasmaComponents.ToolButton {
                flat: true
                icon.name: (root.armedActionKey === ("lxc:" + root.nodeName + ":" + root.ctModel.vmid + ":reboot") && root.armedTimerRunning)
                    ? "dialog-ok"
                    : "system-reboot"
                implicitWidth: root.uiActionButtonSize
                implicitHeight: root.uiActionButtonSize
                visible: root.ctModel && !root.busy && root.ctModel.status === "running"

                PlasmaComponents.ToolTip { text: "Reboot" }

                background: Rectangle {
                    radius: 4
                    color: parent.hovered
                        ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, root.uiButtonHoverDangerOpacity)
                        : "transparent"
                }

                onClicked: if (typeof root.onAction === "function") root.onAction("lxc", root.nodeName, root.ctModel.vmid, root.ctModel.name, "reboot")
            }
            Item { implicitWidth: root.uiActionButtonSize; implicitHeight: root.uiActionButtonSize; visible: !root.ctModel || root.busy || root.ctModel.status !== "running" }
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
            Layout.preferredWidth: root.scrollbarReserve
            Layout.minimumWidth: root.scrollbarReserve
        }
    }
}
