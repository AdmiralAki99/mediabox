import QtQuick

// Generic placeholder — shown for pages not yet built
Rectangle {
    property string pageTitle: "Page"
    color: "#0A0A0A"

    Text {
        anchors.centerIn: parent
        text: pageTitle
        color: "#333333"
        font.pixelSize: 28
        font.weight: Font.Bold
    }
}
