import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root; color: "#0A0A0A"

    property string paperId:       ""
    property string paperTitle:    ""
    property string paperAuthors:  ""
    property string paperAbstract: ""
    property string paperDate:     ""
    property string paperCategory: ""

    Flickable {
        anchors.fill: parent
        contentHeight: contentCol.implicitHeight + 40
        clip: true

        Column {
            id: contentCol
            width: parent.width
            spacing: 0

            Rectangle {
                width: parent.width; height: 60; color: "#0A0A0A"
                BackButton {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left; anchors.leftMargin: 12
                    onClicked: root.StackView.view.pop()
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left; anchors.leftMargin: 64
                    anchors.right: parent.right; anchors.rightMargin: 16
                    text: "Paper"; color: "#FFF"; font.pixelSize: 18; font.weight: Font.Bold
                }
            }

            Text {
                width: parent.width
                text: root.paperTitle
                color: "#FFF"; font.pixelSize: 17; font.weight: Font.Bold
                wrapMode: Text.WordWrap
                leftPadding: 16; rightPadding: 16; bottomPadding: 10
            }

            Row {
                leftPadding: 16; rightPadding: 16; bottomPadding: 12
                spacing: 8

                Rectangle {
                    height: 22; radius: 5; color: "#1E0A3A"
                    width: catLabel.implicitWidth + 12
                    Text {
                        id: catLabel; anchors.centerIn: parent
                        text: root.paperCategory; color: "#9C7FD4"; font.pixelSize: 11
                    }
                }
                Text {
                    text: root.paperDate; color: "#555"; font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Text {
                visible: root.paperAuthors !== ""
                width: parent.width
                text: root.paperAuthors
                color: "#AAA"; font.pixelSize: 13
                wrapMode: Text.WordWrap
                leftPadding: 16; rightPadding: 16; bottomPadding: 16
            }

            Rectangle {
                width: parent.width - 32; height: 1; color: "#1E1E1E"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                width: parent.width
                text: "Abstract"
                color: "#666"; font.pixelSize: 11; font.weight: Font.Medium
                leftPadding: 16; topPadding: 14; bottomPadding: 8
            }

            Text {
                width: parent.width
                text: root.paperAbstract
                color: "#CCC"; font.pixelSize: 13
                wrapMode: Text.WordWrap
                lineHeight: 1.45
                leftPadding: 16; rightPadding: 16; bottomPadding: 24
            }

            Rectangle {
                width: parent.width - 32; height: 1; color: "#1E1E1E"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 20; bottomPadding: 8; spacing: 12

                // Read HTML inline in the browser tab
                Rectangle {
                    width: 168; height: 48; radius: 12; color: "#8B5CF6"
                    Text { anchors.centerIn: parent; text: "📄  Read HTML"; color: "#FFF"; font.pixelSize: 15; font.weight: Font.DemiBold }
                    scale: htmlArea.pressed ? 0.97 : 1.0
                    Behavior on scale { NumberAnimation { duration: 80 } }
                    MouseArea {
                        id: htmlArea; anchors.fill: parent
                        onClicked: root.StackView.view.push(Qt.resolvedUrl("Browser.qml"), {
                            homeUrl: "http://localhost:8000/arxiv/html/" + root.paperId
                        })
                    }
                }

                // Read PDF in-app
                Rectangle {
                    width: 168; height: 48; radius: 12; color: "#1E1E1E"
                    border.color: "#8B5CF6"; border.width: 1
                    Text { anchors.centerIn: parent; text: "📄  Read PDF"; color: "#9C7FD4"; font.pixelSize: 15; font.weight: Font.DemiBold }
                    scale: pdfArea.pressed ? 0.97 : 1.0
                    Behavior on scale { NumberAnimation { duration: 80 } }
                    MouseArea {
                        id: pdfArea; anchors.fill: parent
                        onClicked: root.StackView.view.push(Qt.resolvedUrl("PaperReader.qml"), {
                            paperId:    root.paperId,
                            paperTitle: root.paperTitle
                        })
                    }
                }
            }
        }
    }
}
