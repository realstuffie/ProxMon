import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    // Bind cfg_* keys to the actual controls (KDE Plasma config convention).
    // This ensures Apply/Cancel works and values persist via Plasmoid.configuration.
    property alias cfg_defaultSorting: sortingCombo.selectedValue
    property string cfg_defaultSortingDefault: "status"

    // Compact label mode: "cpu" (default), "running", "error", "lastUpdate"
    property alias cfg_compactMode: compactModeCombo.currentValue
    property string cfg_compactModeDefault: "cpu"

    // Notification properties
    property alias cfg_enableNotifications: enableNotificationsCheck.checked
    property bool cfg_enableNotificationsDefault: true

    property alias cfg_notifyMode: notifyModeValue.value
    property string cfg_notifyModeDefault: "all"

    property alias cfg_notifyFilter: filterField.text
    property string cfg_notifyFilterDefault: ""

    property alias cfg_notifyOnStart: notifyOnStartCheck.checked
    property bool cfg_notifyOnStartDefault: true

    property alias cfg_notifyOnStop: notifyOnStopCheck.checked
    property bool cfg_notifyOnStopDefault: true

    property alias cfg_notifyOnNodeChange: notifyOnNodeChangeCheck.checked
    property bool cfg_notifyOnNodeChangeDefault: true

    // Notification rate limiting
    property alias cfg_notifyRateLimitEnabled: rateLimitEnabledCheck.checked
    property bool cfg_notifyRateLimitEnabledDefault: true
    property alias cfg_notifyRateLimitSeconds: rateLimitSecondsSpin.value
    property int cfg_notifyRateLimitSecondsDefault: 120

    // Notification privacy
    property alias cfg_redactNotifyIdentities: redactNotifyIdentitiesCheck.checked
    property bool cfg_redactNotifyIdentitiesDefault: true

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 15

        // ==================== SORTING SECTION ====================
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
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }

            QQC2.ComboBox {
                id: sortingCombo
                Layout.fillWidth: true

                // Expose selected value for cfg_ alias binding
                // NOTE: `currentValue` is a FINAL property on QQC2.ComboBox in some versions.
                // Using a different name avoids "Cannot override FINAL property".
                property string selectedValue: (currentIndex >= 0 && currentIndex < sortingModel.count)
                    ? sortingModel.get(currentIndex).value
                    : "status"

                model: ListModel {
                    id: sortingModel
                    ListElement { text: "Status (Running first)"; value: "status" }
                    ListElement { text: "Name (A-Z)"; value: "name" }
                    ListElement { text: "Name (Z-A)"; value: "nameDesc" }
                    ListElement { text: "ID (Ascending)"; value: "id" }
                    ListElement { text: "ID (Descending)"; value: "idDesc" }
                }
                textRole: "text"

                // When KCM loads, cfg_defaultSorting already contains the saved value.
                Component.onCompleted: {
                    for (var i = 0; i < sortingModel.count; i++) {
                        if (sortingModel.get(i).value === root.cfg_defaultSorting) {
                            currentIndex = i
                            break
                        }
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

        // Separator
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            implicitHeight: 1
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.3
        }

        // ==================== COMPACT DISPLAY SECTION ====================
        Kirigami.Heading {
            text: "Compact Display"
            level: 2
        }

        GridLayout {
            columns: 2
            columnSpacing: 15
            rowSpacing: 12
            Layout.fillWidth: true

            QQC2.Label {
                text: "Compact label:"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }

            QQC2.ComboBox {
                id: compactModeCombo
                Layout.fillWidth: true

                // Expose selected value for cfg_ alias binding
                property string currentValue: (currentIndex >= 0 && currentIndex < compactModeModel.count)
                    ? compactModeModel.get(currentIndex).value
                    : "cpu"

                model: ListModel {
                    id: compactModeModel
                    ListElement { text: "Avg CPU %"; value: "cpu" }
                    ListElement { text: "Running VMs/CTs"; value: "running" }
                    ListElement { text: "Error indicator"; value: "error" }
                    ListElement { text: "Last update time"; value: "lastUpdate" }
                }
                textRole: "text"

                // When KCM loads, cfg_compactMode already contains the saved value.
                Component.onCompleted: {
                    for (var i = 0; i < compactModeModel.count; i++) {
                        if (compactModeModel.get(i).value === root.cfg_compactMode) {
                            currentIndex = i
                            break
                        }
                    }
                }
            }
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            implicitHeight: 1
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.3
        }

        // ==================== NOTIFICATIONS SECTION ====================
        Kirigami.Heading {
            text: "Notification Settings"
            level: 2
        }

        // Master toggle
        QQC2.CheckBox {
            id: enableNotificationsCheck
            text: "Enable desktop notifications"
            checked: root.cfg_enableNotifications
            onCheckedChanged: root.cfg_enableNotifications = checked
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 5
            Layout.bottomMargin: 5
            implicitHeight: 1
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.2
            visible: root.cfg_enableNotifications
        }

        // Event Type Toggles
        Kirigami.Heading {
            text: "Notify On"
            level: 4
            visible: root.cfg_enableNotifications
            opacity: root.cfg_enableNotifications ? 1.0 : 0.5
        }

        GridLayout {
            columns: 2
            columnSpacing: 20
            rowSpacing: 8
            Layout.fillWidth: true
            visible: root.cfg_enableNotifications
            opacity: root.cfg_enableNotifications ? 1.0 : 0.5

            QQC2.CheckBox {
                id: notifyOnStartCheck
                text: "VM/Container started"
                checked: root.cfg_notifyOnStart
                onCheckedChanged: root.cfg_notifyOnStart = checked
                enabled: root.cfg_enableNotifications
            }

            QQC2.CheckBox {
                id: notifyOnStopCheck
                text: "VM/Container stopped"
                checked: root.cfg_notifyOnStop
                onCheckedChanged: root.cfg_notifyOnStop = checked
                enabled: root.cfg_enableNotifications
            }

            QQC2.CheckBox {
                id: notifyOnNodeChangeCheck
                text: "Node online/offline"
                checked: root.cfg_notifyOnNodeChange
                onCheckedChanged: root.cfg_notifyOnNodeChange = checked
                enabled: root.cfg_enableNotifications
            }
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.bottomMargin: 5
            implicitHeight: 1
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.2
            visible: root.cfg_enableNotifications
        }

        // Rate limiting
        Kirigami.Heading {
            text: "Rate Limiting"
            level: 4
            visible: root.cfg_enableNotifications
            opacity: root.cfg_enableNotifications ? 1.0 : 0.5
        }

        QQC2.CheckBox {
            id: rateLimitEnabledCheck
            text: "Rate limit duplicate notifications"
            checked: root.cfg_notifyRateLimitEnabled
            onCheckedChanged: root.cfg_notifyRateLimitEnabled = checked
            enabled: root.cfg_enableNotifications
            visible: root.cfg_enableNotifications
        }

        RowLayout {
            spacing: 8
            visible: root.cfg_enableNotifications
            opacity: (root.cfg_enableNotifications && root.cfg_notifyRateLimitEnabled) ? 1.0 : 0.6
            enabled: root.cfg_enableNotifications && root.cfg_notifyRateLimitEnabled

            QQC2.Label {
                text: "Minimum interval:"
                opacity: 0.8
            }

            QQC2.SpinBox {
                id: rateLimitSecondsSpin
                from: 0
                to: 3600
                value: root.cfg_notifyRateLimitSeconds
                editable: true
                onValueChanged: root.cfg_notifyRateLimitSeconds = value
            }

            QQC2.Label {
                text: "seconds"
                opacity: 0.7
            }
        }

        QQC2.Label {
            text: "Suppresses repeated notifications for the same VM/CT/node state within the interval."
            font.pixelSize: 11
            opacity: 0.6
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: root.cfg_enableNotifications
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.bottomMargin: 5
            implicitHeight: 1
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.2
            visible: root.cfg_enableNotifications
        }

        // Notification privacy
        Kirigami.Heading {
            text: "Privacy"
            level: 4
            visible: root.cfg_enableNotifications
            opacity: root.cfg_enableNotifications ? 1.0 : 0.5
        }

        QQC2.CheckBox {
            id: redactNotifyIdentitiesCheck
            text: "Redact user@realm and token ID in notifications"
            enabled: root.cfg_enableNotifications
            visible: root.cfg_enableNotifications
        }

        QQC2.Label {
            text: "Replaces patterns like 'user@realm!tokenid' with 'REDACTED@realm!REDACTED' when they appear in notification text."
            font.pixelSize: 11
            opacity: 0.6
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: root.cfg_enableNotifications
        }

        // Filter Mode
        Kirigami.Heading {
            text: "Filter Mode"
            level: 4
            visible: root.cfg_enableNotifications
            opacity: root.cfg_enableNotifications ? 1.0 : 0.5
        }

        QQC2.Label {
            text: "Control which VMs and containers trigger notifications"
            font.pixelSize: 11
            opacity: 0.6
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: root.cfg_enableNotifications
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.cfg_enableNotifications
            opacity: root.cfg_enableNotifications ? 1.0 : 0.5

            // Single source of truth for cfg_notifyMode alias binding.
            // Avoids binding loops between RadioButtons and cfg_ values.
            QtObject {
                id: notifyModeValue
                property string value: "all"
            }

            QQC2.RadioButton {
                id: modeAllRadio
                text: "All VMs and containers"
                checked: notifyModeValue.value === "all"
                onCheckedChanged: {
                    if (checked) notifyModeValue.value = "all"
                }
                enabled: root.cfg_enableNotifications
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
                checked: notifyModeValue.value === "whitelist"
                onCheckedChanged: {
                    if (checked) notifyModeValue.value = "whitelist"
                }
                enabled: root.cfg_enableNotifications
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
                checked: notifyModeValue.value === "blacklist"
                onCheckedChanged: {
                    if (checked) notifyModeValue.value = "blacklist"
                }
                enabled: root.cfg_enableNotifications
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
            visible: root.cfg_enableNotifications && notifyModeValue.value !== "all"
            Layout.topMargin: 12

            Kirigami.Heading {
                text: notifyModeValue.value === "whitelist" ? "Whitelist Filter" : "Blacklist Filter"
                level: 4
            }

            QQC2.TextField {
                id: filterField
                Layout.fillWidth: true
                placeholderText: "web-server, 100, database*, *-prod"
                text: root.cfg_notifyFilter
                onTextChanged: root.cfg_notifyFilter = text
            }

            QQC2.Label {
                text: "Enter comma-separated names or VM IDs. Use * as wildcard."
                font.pixelSize: 11
                opacity: 0.6
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            // Examples box
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.preferredHeight: examplesColumn.implicitHeight + 16
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

        // Separator
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            implicitHeight: 1
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.3
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 15
            Layout.bottomMargin: 10
            implicitHeight: 1
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.3
        }

        // ==================== INFO SECTION ====================
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
}
