pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

/**
 * Thin horizontal usage meter.
 *
 * `value` is a 0..1 fraction. Non-finite or negative input renders as an empty
 * track rather than a bar: a missing metric must never be drawn as if it were
 * real data.
 */
Item {
    id: meter

    property real value: 0
    property color barColor: Kirigami.Theme.highlightColor
    property real trackOpacity: 0.18
    property bool animated: true

    readonly property real clampedValue: {
        const v = Number(meter.value)
        if (!isFinite(v) || v <= 0) return 0
        return Math.min(1, v)
    }

    implicitWidth: 40
    implicitHeight: 4

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.textColor.r,
                       Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b,
                       meter.trackOpacity)
    }

    Rectangle {
        anchors.left: track.left
        anchors.verticalCenter: track.verticalCenter
        height: track.height
        radius: height / 2
        width: Math.round(track.width * meter.clampedValue)
        visible: meter.clampedValue > 0
        color: meter.barColor

        Behavior on width {
            enabled: meter.animated
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
    }
}
