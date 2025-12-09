import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: root
    
    width: parent?.width ?? 400
    height: parent?.height ?? 400
    property string title: "Behavior"
    property string cfg_defaultSorting: "status"
    property string cfg_defaultSortingDefault: "status"
    
    // Required properties for Plasma
    property bool cfg_expanding: false
    property int cfg_length: 0
    property bool cfg_expandingDefault: false
    property int cfg_lengthDefault: 0

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
