pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

/**
 * Flat icon button used for every per-row action.
 *
 * Exists so hover treatment, hit area and icon sizing are defined once instead
 * of being re-declared at each call site. `danger` tints the hover state with
 * the highlight colour for actions that change guest power state.
 */
PlasmaComponents.ToolButton {
    id: control

    property bool danger: false
    property int iconSize: 16
    property real hoverOpacity: 0.08
    property real hoverDangerOpacity: 0.18

    flat: true
    icon.width: control.iconSize
    icon.height: control.iconSize
    implicitWidth: 22
    implicitHeight: 22

    background: Rectangle {
        radius: 4
        color: {
            if (!control.hovered) return "transparent"
            const c = control.danger ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
            return Qt.rgba(c.r, c.g, c.b,
                           control.danger ? control.hoverDangerOpacity : control.hoverOpacity)
        }

        Behavior on color {
            ColorAnimation { duration: 100 }
        }
    }
}
