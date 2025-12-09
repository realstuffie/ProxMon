import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: root
    
    width: parent?.width ?? 400
    height: parent?.height ?? 400

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
                model: [
                    { text: "Status (Running first)", value: "status" },
                    { text: "Name (A-Z)", value: "name" },
                    { text: "Name (Z-A)", value: "nameDesc" },
                    { text: "ID (Ascending)", value: "id" },
                    { text: "ID (Descending)", value: "idDesc" }
                ]
                textRole: "text"
                valueRole: "value"
                
                Component.onCompleted: {
                    for (var i = 0; i < model.length; i++) {
                        if (model[i].value === cfg_defaultSorting) {
                            currentIndex = i
                            break
                        }
                    }
                }
                
                onCurrentIndexChanged: {
                    if (currentIndex >= 0) {
                        cfg_defaultSorting = model[currentIndex].value
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
