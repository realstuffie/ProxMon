import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    property string cfg_proxmoxHost: ""
    property string cfg_proxmoxHostDefault: ""
    property int cfg_proxmoxPort: 8006
    property int cfg_proxmoxPortDefault: 8006
    property string cfg_apiTokenId: ""
    property string cfg_apiTokenIdDefault: ""
    property string cfg_apiTokenSecret: ""
    property string cfg_apiTokenSecretDefault: ""
    property int cfg_refreshInterval: 30
    property int cfg_refreshIntervalDefault: 30
    property bool cfg_ignoreSsl: true
    property bool cfg_ignoreSslDefault: true
    property string cfg_connectionMode: "single"
    property string cfg_connectionModeDefault: "single"
    property string cfg_multiHostsJson: "[]"
    property string cfg_multiHostsJsonDefault: "[]"
    property string cfg_multiHostSecretsJson: "{}"
    property string cfg_multiHostSecretsJsonDefault: "{}"
    property bool cfg_autoRetry: true
    property bool cfg_autoRetryDefault: true
    property int cfg_retryStartSeconds: 5
    property int cfg_retryStartSecondsDefault: 5
    property int cfg_retryMaxSeconds: 300
    property int cfg_retryMaxSecondsDefault: 300
    property string cfg_defaultSorting: "status"
    property string cfg_defaultSortingDefault: "status"
    property string cfg_compactMode: "cpu"
    property string cfg_compactModeDefault: "cpu"
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
    property bool cfg_notifyRateLimitEnabled: true
    property bool cfg_notifyRateLimitEnabledDefault: true
    property int cfg_notifyRateLimitSeconds: 120
    property int cfg_notifyRateLimitSecondsDefault: 120
    property bool cfg_redactNotifyIdentities: true
    property bool cfg_redactNotifyIdentitiesDefault: true
    property bool cfg_lowLatency: false
    property bool cfg_lowLatencyDefault: false

    property string cfg_appearanceRunningColor: ""
    property string cfg_appearanceRunningColorDefault: ""
    property string cfg_appearanceStoppedColor: ""
    property string cfg_appearanceStoppedColorDefault: ""
    property int cfg_appearanceCardTintOpacity: 10
    property int cfg_appearanceCardTintOpacityDefault: 10
    property int cfg_appearanceWindowOpacity: 100
    property int cfg_appearanceWindowOpacityDefault: 100

    function normalizeHexColor(value) {
        var text = (value || "").trim()
        if (text === "") return ""
        if (text.charAt(0) !== "#") text = "#" + text
        var hex = text.slice(1)
        if (!/^[0-9a-fA-F]+$/.test(hex)) return null
        if (hex.length === 3 || hex.length === 4) {
            var expanded = ""
            for (var i = 0; i < hex.length; ++i) expanded += hex.charAt(i) + hex.charAt(i)
            hex = expanded
        }
        if (hex.length !== 6 && hex.length !== 8) return null
        return "#" + hex.toUpperCase()
    }

    function channelFromHex(value, index) {
        var normalized = normalizeHexColor(value)
        if (!normalized) return 0
        var hex = normalized.slice(1)
        var start = hex.length === 8 ? 2 : 0
        return parseInt(hex.slice(start + index * 2, start + index * 2 + 2), 16)
    }

    function rgbToHex(r, g, b) {
        function part(value) {
            var channel = Math.max(0, Math.min(255, Number(value)))
            var hex = channel.toString(16).toUpperCase()
            return hex.length < 2 ? "0" + hex : hex
        }
        return "#" + part(r) + part(g) + part(b)
    }

    function setColorFromHex(targetKey, value) {
        var normalized = normalizeHexColor(value)
        if (normalized === null) return false
        if (targetKey === "running") root.cfg_appearanceRunningColor = normalized
        else root.cfg_appearanceStoppedColor = normalized
        return true
    }

    function setColorFromRgb(targetKey, r, g, b) {
        var color = rgbToHex(r, g, b)
        if (targetKey === "running") root.cfg_appearanceRunningColor = color
        else root.cfg_appearanceStoppedColor = color
    }

    function previewColor(value, fallback) {
        var normalized = normalizeHexColor(value)
        if (normalized === "") return fallback
        if (normalized) return normalized
        return fallback
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 15

        GridLayout {
            columns: 2
            columnSpacing: 15
            rowSpacing: 12
            Layout.fillWidth: true

            QQC2.Label {
                text: "Running color:"
                Layout.alignment: Qt.AlignRight | Qt.AlignTop
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    QQC2.TextField {
                        id: runningHexField
                        Layout.fillWidth: true
                        Layout.maximumWidth: 280
                        placeholderText: "Theme default or #RRGGBB"
                        text: root.cfg_appearanceRunningColor
                        onEditingFinished: {
                            if (!root.setColorFromHex("running", text)) text = root.cfg_appearanceRunningColor
                        }
                    }

                    Rectangle {
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: 6
                        border.width: 1
                        border.color: Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, 0.35)
                        color: root.previewColor(root.cfg_appearanceRunningColor, Kirigami.Theme.positiveTextColor)
                    }
                }

                QQC2.Label {
                    text: "Enter a hex color or leave blank for the theme default."
                    font.pixelSize: 11
                    opacity: 0.6
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                QQC2.Label {
                    text: "RGB values stay synced with the hex field."
                    font.pixelSize: 11
                    opacity: 0.6
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    spacing: 8

                    QQC2.Label { text: "R" }
                    QQC2.SpinBox {
                        from: 0
                        to: 255
                        value: root.channelFromHex(root.cfg_appearanceRunningColor, 0)
                        editable: true
                        onValueModified: root.setColorFromRgb("running", value, runningGreenSpin.value, runningBlueSpin.value)
                    }

                    QQC2.Label { text: "G" }
                    QQC2.SpinBox {
                        id: runningGreenSpin
                        from: 0
                        to: 255
                        value: root.channelFromHex(root.cfg_appearanceRunningColor, 1)
                        editable: true
                        onValueModified: root.setColorFromRgb("running", runningRedSpin.value, value, runningBlueSpin.value)
                    }

                    QQC2.Label { text: "B" }
                    QQC2.SpinBox {
                        id: runningBlueSpin
                        from: 0
                        to: 255
                        value: root.channelFromHex(root.cfg_appearanceRunningColor, 2)
                        editable: true
                        onValueModified: root.setColorFromRgb("running", runningRedSpin.value, runningGreenSpin.value, value)
                    }
                }

                QQC2.Button {
                    text: "Use theme default"
                    Layout.alignment: Qt.AlignLeft
                    onClicked: root.cfg_appearanceRunningColor = ""
                }
            }

            QQC2.Label {
                text: "Stopped/offline color:"
                Layout.alignment: Qt.AlignRight | Qt.AlignTop
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    QQC2.TextField {
                        id: stoppedHexField
                        Layout.fillWidth: true
                        Layout.maximumWidth: 280
                        placeholderText: "Theme default or #RRGGBB"
                        text: root.cfg_appearanceStoppedColor
                        onEditingFinished: {
                            if (!root.setColorFromHex("stopped", text)) text = root.cfg_appearanceStoppedColor
                        }
                    }

                    Rectangle {
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: 6
                        border.width: 1
                        border.color: Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, 0.35)
                        color: root.previewColor(root.cfg_appearanceStoppedColor, Kirigami.Theme.disabledTextColor)
                    }
                }

                QQC2.Label {
                    text: "Use a custom stopped/offline color, or leave blank for the theme default."
                    font.pixelSize: 11
                    opacity: 0.6
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                QQC2.Label {
                    text: "RGB values stay synced with the hex field."
                    font.pixelSize: 11
                    opacity: 0.6
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    spacing: 8

                    QQC2.Label { text: "R" }
                    QQC2.SpinBox {
                        id: stoppedRedSpin
                        from: 0
                        to: 255
                        value: root.channelFromHex(root.cfg_appearanceStoppedColor, 0)
                        editable: true
                        onValueModified: root.setColorFromRgb("stopped", value, stoppedGreenSpin.value, stoppedBlueSpin.value)
                    }

                    QQC2.Label { text: "G" }
                    QQC2.SpinBox {
                        id: stoppedGreenSpin
                        from: 0
                        to: 255
                        value: root.channelFromHex(root.cfg_appearanceStoppedColor, 1)
                        editable: true
                        onValueModified: root.setColorFromRgb("stopped", stoppedRedSpin.value, value, stoppedBlueSpin.value)
                    }

                    QQC2.Label { text: "B" }
                    QQC2.SpinBox {
                        id: stoppedBlueSpin
                        from: 0
                        to: 255
                        value: root.channelFromHex(root.cfg_appearanceStoppedColor, 2)
                        editable: true
                        onValueModified: root.setColorFromRgb("stopped", stoppedRedSpin.value, stoppedGreenSpin.value, value)
                    }
                }

                QQC2.Button {
                    text: "Use theme default"
                    Layout.alignment: Qt.AlignLeft
                    onClicked: root.cfg_appearanceStoppedColor = ""
                }
            }

            QQC2.Label {
                text: "Card tint opacity:"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    spacing: 8

                    QQC2.SpinBox {
                        id: cardTintOpacitySpin
                        from: 0
                        to: 40
                        value: root.cfg_appearanceCardTintOpacity
                        editable: true
                        onValueChanged: root.cfg_appearanceCardTintOpacity = value
                    }

                    QQC2.Label {
                        text: "%"
                        opacity: 0.7
                    }
                }

                QQC2.Label {
                    text: "Controls how strongly cards are tinted by the appearance palette."
                    font.pixelSize: 11
                    opacity: 0.6
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }

            QQC2.Label {
                text: "Preview:"
                Layout.alignment: Qt.AlignRight | Qt.AlignTop
            }

            Rectangle {
                implicitWidth: 220
                implicitHeight: 96
                radius: 10
                border.width: 1
                border.color: Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, 0.35)
                color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, root.cfg_appearanceWindowOpacity / 100)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: 6
                        color: Qt.rgba(root.previewColor(root.cfg_appearanceRunningColor, Kirigami.Theme.positiveTextColor).r,
                                       root.previewColor(root.cfg_appearanceRunningColor, Kirigami.Theme.positiveTextColor).g,
                                       root.previewColor(root.cfg_appearanceRunningColor, Kirigami.Theme.positiveTextColor).b,
                                       root.cfg_appearanceCardTintOpacity / 100)

                        QQC2.Label {
                            anchors.centerIn: parent
                            text: "Running"
                            font.pixelSize: 10
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: 6
                        color: Qt.rgba(root.previewColor(root.cfg_appearanceStoppedColor, Kirigami.Theme.disabledTextColor).r,
                                       root.previewColor(root.cfg_appearanceStoppedColor, Kirigami.Theme.disabledTextColor).g,
                                       root.previewColor(root.cfg_appearanceStoppedColor, Kirigami.Theme.disabledTextColor).b,
                                       root.cfg_appearanceCardTintOpacity / 100)

                        QQC2.Label {
                            anchors.centerIn: parent
                            text: "Stopped"
                            font.pixelSize: 10
                        }
                    }
                }
            }

            QQC2.Label {
                text: "Window opacity:"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    spacing: 8

                    QQC2.SpinBox {
                        id: windowOpacitySpin
                        from: 60
                        to: 100
                        value: root.cfg_appearanceWindowOpacity
                        editable: true
                        onValueChanged: root.cfg_appearanceWindowOpacity = value
                    }

                    QQC2.Label {
                        text: "%"
                        opacity: 0.7
                    }
                }

                QQC2.Label {
                    text: "Sets the overall opacity of the expanded widget window."
                    font.pixelSize: 11
                    opacity: 0.6
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }
        }

    }
}
