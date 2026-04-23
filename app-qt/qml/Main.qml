import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.VirtualKeyboard
import "components"
import "pages"

ApplicationWindow {
    id: root
    width: 600
    height: 1024
    visible: true
    title: "Mediabox"
    color: "#0A0A0A"

    // 0 = full width, 1 = right-hand, 2 = left-hand
    property int _kbMode: 0
    readonly property real _kbOneWidth: Math.round(root.width * 0.74)

    InputPanel {
        id: inputPanel
        z: 99

        width:  root._kbMode === 0 ? root.width : root._kbOneWidth
        x:      root._kbMode === 2 ? 0 : (root.width - width)   // left-hand: 0, else right/full
        y:      active ? (root.height - height) : root.height

        Behavior on y     { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }
        Behavior on x     { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }
        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }
    }

    // little handle that floats above the keyboard to switch one-handed mode
    Rectangle {
        z: 100
        visible: inputPanel.active

        width:  root._kbMode === 0 ? 64 : 52
        height: 26
        radius: 13

        x: root._kbMode === 2
               ? (inputPanel.x + inputPanel.width - width - 6)  // left-hand: right edge
               : (inputPanel.x + 6)                              // right-hand or full: left edge

        y: inputPanel.y - height - 6

        color: "#1C1C1C"
        border.color: "#333"; border.width: 1

        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }

        Row {
            anchors.centerIn: parent
            spacing: 4

            Text {
                text: root._kbMode === 0 ? "⊢"
                    : root._kbMode === 1 ? "↔"
                    :                      "↔"
                color: "#666"; font.pixelSize: 13
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root._kbMode === 0 ? "1H"
                    : root._kbMode === 1 ? "R"
                    :                      "L"
                color: "#555"; font.pixelSize: 10; font.weight: Font.Bold
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        TapHandler {
            onTapped: root._kbMode = (root._kbMode + 1) % 3
        }
    }

    readonly property var pageComponents: [
        homeComp, moviesComp, seriesComp, animeComp,
        mangaComp, comicsComp, booksComp, papersComp, browserComp, historyComp, settingsComp
    ]

    // covers everything on first launch until setup is done
    Loader {
        id: enrollLoader
        anchors.fill: parent
        z: 200
        active: !api.isEnrolled()
        sourceComponent: Component {
            Enrollment {
                anchors.fill: parent
                onDone: enrollLoader.active = false
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Sidebar {
            id: sidebar
            Layout.fillHeight: true
            Layout.preferredWidth: 64
            currentIndex: 0
            onPageRequested: (idx) => {
                stack.replace(pageComponents[idx])
            }
        }

        StackView {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            background: Rectangle { color: "#0A0A0A" }
            initialItem: homeComp

            replaceEnter: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0;  to: 1;  duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "y";       from: 18; to: 0;  duration: 260; easing.type: Easing.OutCubic }
                }
            }
            replaceExit: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 1;  to: 0;  duration: 140 }
                    NumberAnimation { property: "y";       from: 0;  to: -10; duration: 140; easing.type: Easing.InCubic }
                }
            }
        }
    }

    Component {
        id: homeComp
        Home {
            onNavRequested: (idx) => {
                sidebar.currentIndex = idx
                stack.replace(pageComponents[idx])
            }
        }
    }
    Component { id: moviesComp;  Movies  {} }
    Component { id: seriesComp;  Series  {} }
    Component { id: animeComp;   Anime   {} }
    Component { id: mangaComp;   Manga   {} }
    Component { id: comicsComp;  Comics  {} }
    Component { id: booksComp;   Books   {} }
    Component { id: papersComp;  Papers  {} }
    Component { id: browserComp; Browser {} }
    Component { id: historyComp; History {} }

    Component { id: settingsComp; Settings {} }
}
