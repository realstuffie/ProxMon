pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

/**
 * One titled group of guests ("VMs" / "Containers") plus its rows.
 *
 * Both the single-host and multi-host node views render two of these, so the
 * section header and the row wiring are declared once. Callers hand in
 * callbacks that are already bound to their own context (node, and session key
 * in the multi-host case), which is what lets the two views share this.
 */
ColumnLayout {
    id: section

    required property string kind
    required property string title
    required property string iconName
    property var guestsModel: null
    property string nodeName: ""

    // Theming forwarded to each row.
    property int uiRowHeight: 30
    property int uiRadiusS: 4
    property real uiSurfaceRunningOpacity: 0.12
    property real uiSurfaceAltOpacity: 0.10
    property color uiRunningColor: Kirigami.Theme.positiveTextColor
    property color uiStoppedColor: Kirigami.Theme.disabledTextColor
    property real uiWindowOpacity: 1.0
    property int scrollbarReserve: 0

    property string armedActionKey: ""
    property bool armedTimerRunning: false

    // (kind, vmid) -> bool. Bound by the caller to its node/session.
    property var busyFor: null

    property var anonymizeVmId: null
    property var anonymizeName: null
    property var anonymizeIp: null
    property var onAction: null
    property var onConsole: null
    property var onStatsToggled: null
    property var getStatsData: null
    property var isStatsLoading: null

    property bool statsEnabled: false
    property bool consoleEnabled: true
    property bool powerActionsEnabled: true

    property string filterText: ""

    readonly property int totalCount: guestsModel ? guestsModel.count : 0
    readonly property int runningCount: guestsModel ? guestsModel.runningCount : 0
    readonly property bool filtering: section.filterText !== ""

    // Match against what is actually on screen, so a filter still works while
    // dev-mode anonymisation is replacing the real names.
    function haystackFor(item, index) {
        if (!item) return ""
        const id = section.anonymizeVmId ? section.anonymizeVmId(item.vmid, index) : item.vmid
        const nm = section.anonymizeName ? section.anonymizeName(item.name, index) : item.name
        return (id + " " + nm).toString().toLowerCase()
    }

    function matchesFilter(item, index) {
        if (!section.filtering) return true
        if (!item) return false
        return section.haystackFor(item, index).indexOf(section.filterText.toLowerCase()) !== -1
    }

    // Recomputed when the filter changes or the model's length changes. A row
    // renamed in place without a count change will not re-trigger this; the
    // next refresh that adds or removes anything corrects it.
    readonly property int matchCount: {
        if (!section.guestsModel) return 0
        const n = section.guestsModel.count
        if (!section.filtering) return n
        let hits = 0
        for (let i = 0; i < n; i++) {
            if (section.matchesFilter(section.guestsModel.get(i), i)) hits++
        }
        return hits
    }

    Layout.fillWidth: true
    visible: totalCount > 0 && matchCount > 0
    spacing: 2

    RowLayout {
        Layout.preferredHeight: 20
        Layout.bottomMargin: 1
        spacing: 6

        Kirigami.Icon {
            source: section.iconName
            implicitWidth: 13
            implicitHeight: 13
            opacity: 0.85
        }

        PlasmaComponents.Label {
            text: section.title
            font.bold: true
            font.pixelSize: 11
        }

        PlasmaComponents.Label {
            text: section.filtering
                ? section.matchCount + " of " + section.totalCount
                : section.runningCount + "/" + section.totalCount
            font.pixelSize: 10
            font.family: "JetBrains Mono"
            opacity: 0.6
        }

        // Hairline running to the right edge, so the eye can find where one
        // group ends and the next begins without another block of bold text.
        Rectangle {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: 2
            height: 1
            color: Qt.rgba(Kirigami.Theme.textColor.r,
                           Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, 0.12)
        }
    }

    Repeater {
        model: section.guestsModel

        delegate: GuestRow {
            required property int index
            required property var itemData

            kind: section.kind
            guestIndex: index
            guestModel: itemData
            visible: section.matchesFilter(itemData, index)
            nodeName: section.nodeName
            busy: !!(section.busyFor && itemData && section.busyFor(section.kind, itemData.vmid))
            armedActionKey: section.armedActionKey
            armedTimerRunning: section.armedTimerRunning
            uiRowHeight: section.uiRowHeight
            uiRadiusS: section.uiRadiusS
            uiSurfaceRunningOpacity: section.uiSurfaceRunningOpacity
            uiSurfaceAltOpacity: section.uiSurfaceAltOpacity
            uiRunningColor: section.uiRunningColor
            uiStoppedColor: section.uiStoppedColor
            uiWindowOpacity: section.uiWindowOpacity
            scrollbarReserve: section.scrollbarReserve
            anonymizeVmId: section.anonymizeVmId
            anonymizeName: section.anonymizeName
            anonymizeIp: section.anonymizeIp
            onAction: section.onAction
            onConsole: section.onConsole
            onStatsToggled: section.onStatsToggled
            getStatsData: section.getStatsData
            isStatsLoading: section.isStatsLoading
            statsEnabled: section.statsEnabled
            consoleEnabled: section.consoleEnabled
            powerActionsEnabled: section.powerActionsEnabled
        }
    }
}
