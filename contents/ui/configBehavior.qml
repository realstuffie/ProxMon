import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: root
    
    width: parent?.width ?? 400
    height: parent?.height ?? 400
    
    property string title: "Behavior"
    
    // Sorting properties (this page's main config)
    property string cfg_defaultSorting: "status"
    property string cfg_defaultSortingDefault: "status"
    
    // Required properties for Plasma
    property bool cfg_expanding: false
    property int cfg_length: 0
    property bool cfg_expandingDefault: false
    property int cfg_lengthDefault: 0
    
    // Connection properties (required - defined in main.xml)
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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15

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
            text: "Choose how VMs and containers are sorted by default"
            font.pixelSize: 11
            opacity: 0.6
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Item { Layout.fillHeight: true }
    }
}
