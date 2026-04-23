import QtQuick
import QtQuick.Controls.Basic
import Qt5Compat.GraphicalEffects

Rectangle {
    id: sidebar
    width: 64
    color: "transparent"

    property int currentIndex: 0
    signal pageRequested(int index)

    property var items: [
        { icon: "home_vector.svg"                         },
        { icon: "movie_vector.svg"                        },
        { icon: "show_vector.svg"                         },
        { icon: "anime_vector.svg"                        },
        { icon: "manga_vector.svg"                        },
        { icon: "comics_vector.svg"                       },
        { icon: "books_vector.svg"                        },
        { icon: "research_paper_vector.svg"               },
        { icon: "browser.svg"                             },
        { icon: "history_vector.svg"                      },
        { icon: "settings_vector.svg"                     },
    ]

    Rectangle {
        id: pill
        width: 52
        height: itemCol.implicitHeight + 28
        radius: 26
        color: "#181818"
        border.color: "#252525"
        border.width: 1
        anchors.centerIn: parent

        Rectangle {
            anchors.top: parent.top; anchors.topMargin: 1
            anchors.left: parent.left; anchors.leftMargin: 8
            anchors.right: parent.right; anchors.rightMargin: 8
            height: 1; color: "#333333"; radius: 1
        }

        Column {
            id: itemCol
            anchors.centerIn: parent
            spacing: 4

            Repeater {
                model: sidebar.items

                Rectangle {
                    id: iconBtn
                    width: 40; height: 40; radius: 20
                    color: sidebar.currentIndex === index ? "#1E1245" : "transparent"
                    scale: iconMA.containsPress ? 0.82 : 1.0

                    Behavior on color  { ColorAnimation  { duration: 180 } }
                    Behavior on scale  { SpringAnimation { spring: 7; damping: 0.45 } }

                    Rectangle {
                        visible: sidebar.currentIndex === index
                        width: 4; height: 4; radius: 2; color: "#8B5CF6"; opacity: 1.0
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 3
                        anchors.horizontalCenter: parent.horizontalCenter
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }

                    Rectangle {
                        anchors.fill: parent; radius: parent.radius
                        color: "white"
                        opacity: iconMA.containsPress ? 0.06 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    Image {
                        id: iconImg
                        anchors.centerIn: parent
                        source: Qt.resolvedUrl("../../assets/icons/" + modelData.icon)
                        sourceSize: Qt.size(48, 48)
                        width: 22; height: 22
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        visible: false  // coloroverlay needs this as its source
                    }
                    ColorOverlay {
                        anchors.fill: iconImg
                        source: iconImg
                        color: "#FFFFFF"
                        opacity: sidebar.currentIndex === index ? 1.0 : 0.40
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }

                    MouseArea {
                        id: iconMA
                        anchors.fill: parent
                        onClicked: {
                            sidebar.currentIndex = index
                            sidebar.pageRequested(index)
                        }
                    }
                }
            }
        }
    }
}
