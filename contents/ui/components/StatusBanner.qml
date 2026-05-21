import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property bool configured: false
    property bool hasCoreConfig: false
    property string secretState: "idle"
    property bool refreshResolvingSecrets: false
    property bool loading: false
    property string errorMessage: ""
    property bool partialFailure: false
    property string retryStatusText: ""
    property string armedLabel: ""
    property bool actionPermHintShown: false
    property string actionPermHint: ""
    property string pbsError: ""
    property var onRetry: null

    function friendlyErrorHint(msg) {
        msg = msg || ""
        var m = msg.toLowerCase()

        if (m.indexOf("authentication failed") !== -1 || m.indexOf("http 401") !== -1 || m.indexOf("http 403") !== -1) {
            return "Check API Token ID/Secret and that the token has Sys.Audit + VM.Audit permissions."
        }
        if (m.indexOf("hostname") !== -1 && m.indexOf("match") !== -1) {
            return "Hostname mismatch. Use host value that matches cert SAN/CN, or use Ignore SSL only as fallback."
        }
        if (m.indexOf("ssl") !== -1 || m.indexOf("tls") !== -1 || m.indexOf("certificate") !== -1) {
            return "SSL/TLS error. Add a trusted cert PEM or cert file path first; use ‘Ignore SSL certificate errors’ only as a fallback."
        }
        if (m.indexOf("timed out") !== -1 || m.indexOf("timeout") !== -1) {
            return "Request timed out. Check host/port reachability, firewall, and DNS."
        }
        if (m.indexOf("not configured") !== -1) {
            return "Open the widget settings and enter Host + Token ID + Token Secret."
        }
        return ""
    }

    Layout.fillWidth: true
    spacing: 8

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: !root.configured
        spacing: 8

        Item { Layout.fillHeight: true }

        Kirigami.Icon {
            source: "configure"
            implicitWidth: 48
            implicitHeight: 48
            Layout.alignment: Qt.AlignHCenter
            opacity: 0.6
        }

        PlasmaComponents.Label {
            text: {
                if (!root.hasCoreConfig) return "Not Configured"
                if (root.secretState === "loading" || root.refreshResolvingSecrets) return "Loading Credentials…"
                if (root.secretState === "missing") return "Missing Token Secret"
                if (root.secretState === "error") return "Credentials Error"
                return "Not Configured"
            }
            font.bold: true
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
        }

        PlasmaComponents.Label {
            text: {
                if (!root.hasCoreConfig) return "Right-click → Configure Widget"
                if (root.secretState === "loading" || root.refreshResolvingSecrets) return "Reading API token secret from keyring…"
                if (root.secretState === "missing") return "Open settings and re-enter the API Token Secret."
                if (root.secretState === "error") return "Keyring access failed. Check logs (journalctl --user -f)."
                return "Right-click → Configure Widget"
            }
            opacity: 0.7
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: 320
        }

        Item { Layout.fillHeight: true }
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: root.loading ? 50 : 0
        visible: root.loading

        PlasmaComponents.BusyIndicator {
            anchors.centerIn: parent
            running: root.loading
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: 10
        visible: root.errorMessage !== "" && !root.partialFailure && root.configured
        spacing: 8

        RowLayout {
            spacing: 8
            Layout.alignment: Qt.AlignHCenter

            Kirigami.Icon {
                source: "dialog-error"
                implicitWidth: 22
                implicitHeight: 22
            }

            PlasmaComponents.Label {
                text: "Connection Error"
                font.bold: true
                color: Kirigami.Theme.negativeTextColor
            }
        }

        PlasmaComponents.Label {
            text: root.errorMessage
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        PlasmaComponents.Label {
            text: root.friendlyErrorHint(root.errorMessage)
            visible: text !== ""
            opacity: 0.85
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        PlasmaComponents.Label {
            text: root.retryStatusText
            visible: root.retryStatusText !== ""
            opacity: 0.85
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        PlasmaComponents.Label {
            text: root.armedLabel
            visible: root.armedLabel !== ""
            opacity: 0.9
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        PlasmaComponents.Label {
            text: root.actionPermHint
            visible: root.actionPermHintShown && root.actionPermHint !== ""
            opacity: 0.9
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        PlasmaComponents.Button {
            text: "Retry"
            icon.name: "view-refresh"
            Layout.alignment: Qt.AlignHCenter
            onClicked: if (typeof root.onRetry === "function") root.onRetry()
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: 10
        visible: root.pbsError !== "" && root.configured
        spacing: 8
        RowLayout {
            spacing: 8
            Layout.alignment: Qt.AlignHCenter
            Kirigami.Icon {
                source: "dialog-warning"
                implicitWidth: 22
                implicitHeight: 22
            }
            PlasmaComponents.Label {
                text: "PBS Error"
                font.bold: true
                color: Kirigami.Theme.neutralTextColor
            }
        }
        PlasmaComponents.Label {
            text: root.pbsError
            color: Kirigami.Theme.neutralTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
