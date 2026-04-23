import QtQuick

Rectangle {
    id: card
    width: 130
    height: 195
    radius: 10
    color: "#1A1A1A"
    clip: true

    property string posterUrl: ""
    property string title: ""
    property real rating: 0
    signal tapped()

    // Poster image
    Image {
        anchors.fill: parent
        source: card.posterUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true

        // Shimmer placeholder while loading
        Rectangle {
            anchors.fill: parent
            visible: parent.status !== Image.Ready
            color: "#1E1E1E"

            Rectangle {
                id: shimmer
                width: parent.width * 0.6
                height: parent.height
                color: "#FFFFFF"
                opacity: 0.04

                NumberAnimation on x {
                    from: -card.width
                    to: card.width
                    duration: 1200
                    loops: Animation.Infinite
                    running: true
                }
            }
        }
    }

    // Bottom gradient + title
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 64
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: "#CC000000" }
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 7
            anchors.bottomMargin: 6
            text: card.title
            color: "#FFFFFF"
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    // Rating badge
    Rectangle {
        visible: card.rating > 0
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 5
        width: 36
        height: 18
        radius: 4
        color: "#CC000000"

        Text {
            anchors.centerIn: parent
            text: card.rating.toFixed(1)
            color: "#FFD700"
            font.pixelSize: 10
            font.weight: Font.Bold
        }
    }

    // Touch feedback
    scale: area.pressed ? 0.94 : 1.0
    Behavior on scale { NumberAnimation { duration: 80 } }

    MouseArea {
        id: area
        anchors.fill: parent
        onClicked: card.tapped()
    }
}
