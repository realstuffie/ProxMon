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

    // ---- drag-and-drop reorder ("custom" sort mode) -----------------------
    // Rows never move during a drag. The dragged row dims and a marker line
    // shows the drop position; on release the caller persists the new order
    // and the controller's re-sort moves the rows. This keeps the Repeater's
    // model, not the layout, as the only source of row positions.
    property bool reorderEnabled: false
    // (kind, from, to). Bound by the caller to its node/session.
    property var onReorder: null
    property int dragFromIndex: -1
    // Insertion point in model rows: 0 = above the first row, count = below
    // the last. -1 when no drag is in progress.
    property int dropInsertIndex: -1

    function insertionIndexAt(sceneY) {
        const y = section.mapFromItem(null, 0, sceneY).y
        let lastVisible = -1
        for (let i = 0; i < guestRepeater.count; i++) {
            const row = guestRepeater.itemAt(i)
            if (!row || !row.visible) continue
            if (y < row.y + row.height / 2) return i
            lastVisible = i
        }
        return lastVisible + 1
    }

    // ---- auto-scroll while dragging ---------------------------------------
    // Scrolls the enclosing panel when the pointer nears its top or bottom
    // edge, but never further than needed to bring this section's own first
    // or last row into view: dragging VMs does not scroll down to the
    // containers, and vice versa.
    readonly property int autoScrollEdge: 32   // px from the viewport edge
    readonly property real autoScrollMaxStep: 14 // px per tick at the edge
    property real lastDragSceneY: 0
    property var scrollFlickable: null

    function findFlickable() {
        // The panel's QQC2.ScrollView wraps its content in a Flickable; walk
        // up to it rather than threading a reference through every caller.
        for (let p = section.parent; p; p = p.parent) {
            if (p.contentY !== undefined && p.flickableDirection !== undefined) return p
        }
        return null
    }

    function autoScrollStep() {
        const flick = section.scrollFlickable
        if (section.dragFromIndex < 0 || !flick || flick.height <= 0) return 0
        const viewTop = flick.mapToItem(null, 0, 0).y
        const viewBottom = viewTop + flick.height
        const y = section.lastDragSceneY
        let step = 0
        if (y < viewTop + section.autoScrollEdge) {
            const depth = Math.min(1, (viewTop + section.autoScrollEdge - y) / section.autoScrollEdge)
            step = -Math.max(1, Math.round(depth * section.autoScrollMaxStep))
        } else if (y > viewBottom - section.autoScrollEdge) {
            const depth = Math.min(1, (y - (viewBottom - section.autoScrollEdge)) / section.autoScrollEdge)
            step = Math.max(1, Math.round(depth * section.autoScrollMaxStep))
        }
        if (step === 0) return 0

        // Limits, in content coordinates: stop once the section's top reaches
        // the viewport top (scrolling up) or its bottom reaches the viewport
        // bottom (scrolling down). A section taller than the viewport can
        // therefore still scroll through its own rows, and no further.
        const sectionTop = section.mapToItem(flick.contentItem, 0, 0).y
        const sectionBottom = sectionTop + section.height
        const contentMin = flick.originY
        const contentMax = flick.originY + Math.max(0, flick.contentHeight - flick.height)
        const minY = Math.max(contentMin, Math.min(flick.contentY, sectionTop))
        const maxY = Math.min(contentMax, Math.max(flick.contentY, sectionBottom - flick.height))

        const next = Math.max(minY, Math.min(maxY, flick.contentY + step))
        return next - flick.contentY
    }

    Timer {
        id: autoScrollTimer
        interval: 16
        repeat: true
        running: section.dragFromIndex >= 0 && section.scrollFlickable !== null
        onTriggered: {
            const delta = section.autoScrollStep()
            if (delta === 0) return
            section.scrollFlickable.contentY += delta
            // Rows moved under a stationary pointer; re-aim the drop marker.
            section.dropInsertIndex = section.insertionIndexAt(section.lastDragSceneY)
        }
    }

    function beginDrag(index) {
        if (!section.reorderEnabled) return
        section.scrollFlickable = section.findFlickable()
        // Seed the pointer position from the dragged row so the auto-scroll
        // timer never acts on a stale y before the first move arrives.
        const row = guestRepeater.itemAt(index)
        section.lastDragSceneY = row ? row.mapToItem(null, 0, row.height / 2).y : 0
        section.dragFromIndex = index
        section.dropInsertIndex = index
    }

    function updateDrag(sceneY) {
        if (section.dragFromIndex < 0) return
        section.lastDragSceneY = sceneY
        section.dropInsertIndex = section.insertionIndexAt(sceneY)
    }

    function endDrag(commit) {
        const from = section.dragFromIndex
        const insert = section.dropInsertIndex
        section.dragFromIndex = -1
        section.dropInsertIndex = -1
        section.scrollFlickable = null
        if (!commit || from < 0 || insert < 0 || !section.reorderEnabled) return
        // Removing the dragged row first shifts later insertion points up.
        const to = insert > from ? insert - 1 : insert
        if (to === from) return
        if (typeof section.onReorder === "function") section.onReorder(section.kind, from, to)
    }

    // Cancel an in-flight drag if reordering is switched off underneath it
    // (sort mode changed, or a filter was typed).
    onReorderEnabledChanged: if (!reorderEnabled) endDrag(false)

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
        id: guestRepeater
        model: section.guestsModel
        // A refresh that adds or removes rows mid-drag would invalidate the
        // captured index, so drop the drag rather than move the wrong guest.
        onCountChanged: section.endDrag(false)

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
            reorderEnabled: section.reorderEnabled
            dragging: section.dragFromIndex === index
            // Marker above this row, or below it when it is the last row and
            // the drop goes to the end. Hidden where the drop would be a no-op.
            dropMarker: {
                const from = section.dragFromIndex
                const insert = section.dropInsertIndex
                if (from < 0 || insert === from || insert === from + 1) return 0
                if (insert === index) return 1
                if (insert === guestRepeater.count && index === guestRepeater.count - 1) return 2
                return 0
            }
            onDragStarted: section.beginDrag
            onDragMoved: section.updateDrag
            onDragFinished: section.endDrag
        }
    }
}
