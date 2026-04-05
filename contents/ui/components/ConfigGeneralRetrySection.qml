import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property alias autoRetryChecked: autoRetryCheck.checked
    property alias retryStartValue: retryStartSpin.value
    property alias retryMaxValue: retryMaxSpin.value

    Layout.fillWidth: true
    spacing: 15

    Kirigami.Heading {
        text: "Auto-Retry"
        level: 2
    }

    QQC2.CheckBox {
        id: autoRetryCheck
        text: "Automatically retry on connection errors"
        checked: true
    }

    GridLayout {
        columns: 2
        columnSpacing: 15
        rowSpacing: 12
        Layout.fillWidth: true
        enabled: autoRetryCheck.checked
        opacity: enabled ? 1.0 : 0.6

        QQC2.Label {
            text: "Start delay:"
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        }
        RowLayout {
            spacing: 8
            QQC2.SpinBox {
                id: retryStartSpin
                from: 1
                to: 300
                value: 5
                editable: true
            }
            QQC2.Label {
                text: "seconds"
                opacity: 0.7
            }
        }

        QQC2.Label {
            text: "Max delay:"
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        }
        RowLayout {
            spacing: 8
            QQC2.SpinBox {
                id: retryMaxSpin
                from: 5
                to: 3600
                value: 300
                editable: true
            }
            QQC2.Label {
                text: "seconds"
                opacity: 0.7
            }
        }
    }
}
