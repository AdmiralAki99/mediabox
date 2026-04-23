import QtQuick
import QtQuick.Controls.Basic

Rectangle {
    id: btn
    width: 38; height: 38; radius: 10
    color: area.pressed ? "#2a2a2a" : "#1E1E1E"
    border.color: "#333"; border.width: 1

    signal clicked()

    Text {
        anchors.centerIn: parent
        text: "‹"
        color: "#FFFFFF"
        font.pixelSize: 22
    }

    MouseArea { id: area; anchors.fill: parent; onClicked: btn.clicked() }
    Behavior on color { ColorAnimation { duration: 80 } }
}
