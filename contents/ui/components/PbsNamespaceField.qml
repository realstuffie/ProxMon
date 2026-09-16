import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

// Edits a PBS namespace filter stored as a string: "*" means all namespaces,
// "" means the root namespace only, anything else is one exact namespace.
// The parent owns the value; this item only reports edits, so bindings on
// `value` stay intact.
RowLayout {
    id: root

    property string value: "*"
    signal edited(string value)

    readonly property int modeAll: 0
    readonly property int modeRoot: 1
    readonly property int modeNamed: 2

    // "Specific namespace" was picked but no name typed yet. The stored value
    // keeps its previous meaning until a name is entered.
    property bool namedPending: false

    function modeFor(v) {
        const t = (v || "").trim()
        return t === "*" ? modeAll : (t === "" ? modeRoot : modeNamed)
    }
    readonly property int effectiveMode: namedPending ? modeNamed : modeFor(value)

    onEffectiveModeChanged: modeBox.currentIndex = effectiveMode
    onValueChanged: {
        if (modeFor(value) === modeNamed) namedPending = false
    }

    QQC2.ComboBox {
        id: modeBox
        model: ["All namespaces", "Root only", "Specific namespace"]
        Component.onCompleted: currentIndex = root.effectiveMode
        onActivated: (index) => {
            if (index === root.modeNamed) {
                if (root.modeFor(root.value) !== root.modeNamed) {
                    root.namedPending = true
                    nameField.forceActiveFocus()
                }
                return
            }
            root.namedPending = false
            const next = index === root.modeAll ? "*" : ""
            if (next !== root.value) root.edited(next)
            // Re-sync the box when the value did not change, for example
            // "Root only" picked while already on root.
            currentIndex = root.effectiveMode
        }
    }

    QQC2.TextField {
        id: nameField
        visible: root.effectiveMode === root.modeNamed
        Layout.fillWidth: true
        placeholderText: "cluster-a"
        text: root.modeFor(root.value) === root.modeNamed ? root.value : ""
        onTextEdited: {
            const t = text.trim()
            // Empty or "*" would silently switch meaning; wait for a real name.
            if (t === "" || t === "*") {
                root.namedPending = true
                return
            }
            root.edited(text)
        }
    }
}
