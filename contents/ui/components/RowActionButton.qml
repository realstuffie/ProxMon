pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

/**
 * Flat icon button shared by the toolbar and guest actions.
 *
 * Exists so hover treatment, hit area and icon sizing are defined once instead
 * of being re-declared at each call site.
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
    icon.color: Kirigami.Theme.textColor
    implicitWidth: 22
    implicitHeight: 22

    background: Rectangle {
        radius: 5
        border.width: control.visualFocus ? 1 : 0
        border.color: Kirigami.Theme.highlightColor
        color: {
            if (!control.hovered && !control.down && !control.checked && !control.visualFocus)
                return "transparent"
            const c = control.danger ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor
            return Qt.rgba(c.r, c.g, c.b,
                           control.down || control.checked || control.danger
                               ? control.hoverDangerOpacity : control.hoverOpacity)
        }

        Behavior on color {
            ColorAnimation { duration: 100 }
        }
    }
}
