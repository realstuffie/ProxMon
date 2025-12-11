// contents/ui/configBehavior.qml
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: root
    width: parent?.width ?? 400
    height: parent?.height ?? 400
    property string title: "Behavior"

    // Sorting properties
    property string cfg_defaultSorting: "status"
    property string cfg_defaultSortingDefault: "status"

    // Notification properties
    property bool cfg_enableNotifications: true
    property bool cfg_enableNotificationsDefault: true

    property string cfg_notifyMode: "all"
    property string cfg_notifyModeDefault: "all"

    property string cfg_notifyFilter: ""
    property string cfg_notifyFilterDefault: ""

    property bool cfg_notifyOnStart: true
    property bool cfg_notifyOnStartDefault: true

    property bool cfg_notifyOnStop: true
    property bool cfg_notifyOnStopDefault: true

    property bool cfg_notifyOnNodeChange: true
    property bool cfg_notifyOnNodeChangeDefault: true

    QQC2.ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 20

            // ==================== SORTING SECTION ====================
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 20
                spacing: 12

                Kirigami.Heading {
                    text: "Sorting Options"
                    level: 2
                }

                GridLayout {
                    columns: 2
                    columnSpacing: 15
                    rowSpacing: 12
                    Layout.fillWidth: true

                    QQC2.Label {
                        text: "Default Sorting:"
                    }

                    QQC2.ComboBox {
                        id: sortingCombo
                        Layout.fillWidth: true
                        model: ListModel {
                            id: sortingModel
                            ListElement { text: "Status (Running first)"; value: "status" }
                            ListElement { text: "Name (A-Z)"; value: "name" }
                            ListElement { text: "Name (Z-A)"; value: "nameDesc" }
                            ListElement { text: "ID (Ascending)"; value: "id" }
                            ListElement { text: "ID (Descending)"; value: "idDesc" }
                        }
                        textRole: "text"

                        Component.onCompleted: {
                            for (var i = 0; i < sortingModel.count; i++) {
                                if (sortingModel.get(i).value === cfg_defaultSorting) {
                                    currentIndex = i
                                    break
                                }
                            }
                        }

                        onCurrentIndexChanged: {
                            if (currentIndex >= 0) {
                                cfg_defaultSorting = sortingModel.get(currentIndex).value
                            }
                        }
                    }
                }

                QQC2.Label {
                    text: "Choose how VMs and containers are sorted in the widget"
                    font.pixelSize: 11
                    opacity: 0.6
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                height: 1
                color: Kirigami.Theme.disabledTextColor
                opacity: 0.3
            }

            // ==================== NOTIFICATIONS SECTION ====================
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                spacing: 12

                Kirigami.Heading {
                    text: "Notification Settings"
                    level: 2
                }

                // Master toggle
                QQC2.CheckBox {
                    id: enableNotificationsCheck
                    text: "Enable desktop notifications"
                    checked: cfg_enableNotifications
                    onCheckedChanged: cfg_enableNotifications = checked
                }

                // Notification options (disabled when notifications are off)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    opacity: cfg_enableNotifications ? 1.0 : 0.5
                    enabled: cfg_enableNotifications

                    // Event Type Toggles
                    Kirigami.Heading {
                        text: "Notify On"
                        level: 4
                        Layout.topMargin: 8
                    }

                    GridLayout {
                        columns: 2
                        columnSpacing: 20
                        rowSpacing: 8
                        Layout.fillWidth: true

                        QQC2.CheckBox {
                            id: notifyOnStartCheck
                            text: "VM/Container started"
                            checked: cfg_notifyOnStart
                            onCheckedChanged: cfg_notifyOnStart = checked
                        }

                        QQC2.CheckBox {
                            id: notifyOnStopCheck
                            text: "VM/Container stopped"
                            checked: cfg_notifyOnStop
                            onCheckedChanged: cfg_notifyOnStop = checked
                        }

                        QQC2.CheckBox {
                            id: notifyOnNodeChangeCheck
                            text: "Node online/offline"
                            checked: cfg_notifyOnNodeChange
                            onCheckedChanged: cfg_notifyOnNodeChange = checked
                            Layout.columnSpan: 2
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Kirigami.Theme.disabledTextColor
                        opacity: 0.2
                        Layout.topMargin: 8
                        Layout.bottomMargin: 8
                    }

                    // Filter Mode
                    Kirigami.Heading {
                        text: "Filter Mode"
                        level: 4
                    }

                    QQC2.Label {
                        text: "Control which VMs and containers trigger notifications"
                        font.pixelSize: 11
                        opacity: 0.6
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        QQC2.RadioButton {
                            id: modeAllRadio
                            text: "All VMs and containers"
                            checked: cfg_notifyMode === "all"
                            onCheckedChanged: {
                                if (checked) cfg_notifyMode = "all"
                            }
                        }

                        QQC2.Label {
                            text: "Send notifications for all state changes"
                            font.pixelSize: 11
                            opacity: 0.5
                            Layout.leftMargin: 24
                        }

                        QQC2.RadioButton {
                            id: modeWhitelistRadio
                            text: "Only specified (Whitelist)"
                            checked: cfg_notifyMode === "whitelist"
                            onCheckedChanged: {
                                if (checked) cfg_notifyMode = "whitelist"
                            }
                            Layout.topMargin: 8
                        }

                        QQC2.Label {
                            text: "Only notify for VMs/containers in the filter list"
                            font.pixelSize: 11
                            opacity: 0.5
                            Layout.leftMargin: 24
                        }

                        QQC2.RadioButton {
                            id: modeBlacklistRadio
                            text: "All except specified (Blacklist)"
                            checked: cfg_notifyMode === "blacklist"
                            onCheckedChanged: {
                                if (checked) cfg_notifyMode = "blacklist"
                            }
                            Layout.topMargin: 8
                        }

                        QQC2.Label {
                            text: "Notify for all except VMs/containers in the filter list"
                            font.pixelSize: 11
                            opacity: 0.5
                            Layout.leftMargin: 24
                        }
                    }

                    // Filter Input (only visible when whitelist or blacklist is selected)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: cfg_notifyMode !== "all"
                        Layout.topMargin: 12

                        Kirigami.Heading {
                            text: cfg_notifyMode === "whitelist" ? "Whitelist Filter" : "Blacklist Filter"
                            level: 4
                        }

                        QQC2.TextField {
                            id: filterField
                            Layout.fillWidth: true
                            placeholderText: "web-server, 100, database*, *-prod"
                            text: cfg_notifyFilter
                            onTextChanged: cfg_notifyFilter = text
                        }

                        QQC2.Label {
                            text: "Enter comma-separated names or VM IDs. Use * as wildcard."
                            font.pixelSize: 11
                            opacity: 0.6
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }

                        // Examples
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            height: examplesColumn.implicitHeight + 16
                            radius: 4
                            color: Kirigami.Theme.backgroundColor
                            border.color: Kirigami.Theme.disabledTextColor
                            border.width: 1
                            opacity: 0.8

                            ColumnLayout {
                                id: examplesColumn
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                QQC2.Label {
                                    text: "Examples:"
                                    font.bold: true
                                    font.pixelSize: 11
                                }

                                QQC2.Label {
                                    text: "• <b>web-server</b> — Exact name match"
                                    font.pixelSize: 11
                                    textFormat: Text.RichText
                                }

                                QQC2.Label {
                                    text: "• <b>100</b> — Match VM/CT ID 100"
                                    font.pixelSize: 11
                                    textFormat: Text.RichText
                                }

                                QQC2.Label {
                                    text: "• <b>*-prod</b> — Match names ending with '-prod'"
                                    font.pixelSize: 11
                                    textFormat: Text.RichText
                                }

                                QQC2.Label {
                                    text: "• <b>db-*</b> — Match names starting with 'db-'"
                                    font.pixelSize: 11
                                    textFormat: Text.RichText
                                }

                                QQC2.Label {
                                    text: "• <b>*test*</b> — Match names containing 'test'"
                                    font.pixelSize: 11
                                    textFormat: Text.RichText
                                }
                            }
                        }
                    }
                }
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                height: 1
                color: Kirigami.Theme.disabledTextColor
                opacity: 0.3
            }

            // ==================== INFO SECTION ====================
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.bottomMargin: 20
                spacing: 8

                RowLayout {
                    spacing: 8

                    Kirigami.Icon {
                        source: "dialog-information"
                        implicitWidth: 16
                        implicitHeight: 16
                        opacity: 0.7
                    }

                    QQC2.Label {
                        text: "About Notifications"
                        font.bold: true
                        font.pixelSize: 12
                    }
                }

                QQC2.Label {
                    text: "Notifications are sent using your system's notification service. " +
                          "The first refresh after startup records the initial state — " +
                          "notifications are only sent for subsequent changes."
                    font.pixelSize: 11
                    opacity: 0.6
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                QQC2.Label {
                    text: "Node notifications are always sent regardless of filter settings, " +
                          "as node state changes affect the entire cluster."
                    font.pixelSize: 11
                    opacity: 0.6
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    Layout.topMargin: 4
                }
            }

            // Bottom spacer
            Item { Layout.fillHeight: true }
        }
    }
}
