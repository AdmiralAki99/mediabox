import QtQuick
import QtQuick.Controls.Basic
import "../components"

Rectangle {
    id: root
    color: "#000000"

    property string chapterId:    ""
    property string chapterTitle: ""
    property string comicTitle:   ""
    property string _reqId:       ""
    property bool   _controls:    true

    ListModel { id: pagesModel }

    Connections {
        target: api
        function onFetched(id, data) {
            if (id !== root._reqId) return
            var raw = JSON.parse(data)
            if (raw.error) { loadText.text = "Error loading pages"; return }
            var pages = Array.isArray(raw) ? raw : (raw.results || [])
            pagesModel.clear()
            pages.forEach(function(p) { pagesModel.append(p) })
            loadText.text = ""
        }
    }

    Component.onCompleted: {
        root._reqId = "comic_pages_" + Date.now()
        loadText.text = "Loading pages…"
        // Comic images require a server-side Referer header — fetch via proxy
        api.fetch(root._reqId, "/comics/chapter/pages", JSON.stringify({ id: chapterId }))
    }

    Timer { id: hideTimer; interval: 3000; onTriggered: root._controls = false }

    ListView {
        id: pager
        anchors.fill: parent
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        highlightMoveDuration: 180
        flickDeceleration: 3000
        maximumFlickVelocity: 4000
        clip: true
        model: pagesModel
        cacheBuffer: pager.width * 2

        delegate: Item {
            width: pager.width; height: pager.height

            Image {
                id: pageImg; anchors.fill: parent
                // Route through backend proxy so the Referer header is set server-side
                source: model.url
                       ? "http://localhost:8000/comics/image?url=" + encodeURIComponent(model.url)
                       : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true; cache: true; smooth: true

                Rectangle {
                    visible: pageImg.status === Image.Loading
                    anchors.fill: parent; color: "#080808"
                    Text { anchors.centerIn: parent; text: "…"; color: "#333"; font.pixelSize: 28 }
                }
                Rectangle {
                    visible: pageImg.status === Image.Error
                    anchors.fill: parent; color: "#080808"
                    Text { anchors.centerIn: parent; text: "Failed to load page"; color: "#444"; font.pixelSize: 13 }
                }
            }
        }
    }

    MouseArea {
        anchors.left: parent.left; width: parent.width * 0.35; height: parent.height
        onClicked: {
            if (pager.currentIndex > 0) pager.currentIndex--
            root._controls = true; hideTimer.restart()
        }
    }
    MouseArea {
        anchors.right: parent.right; width: parent.width * 0.35; height: parent.height
        onClicked: {
            if (pager.currentIndex < pagesModel.count - 1) pager.currentIndex++
            root._controls = true; hideTimer.restart()
        }
    }
    MouseArea {
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.3; height: parent.height
        onClicked: { root._controls = !root._controls; if (root._controls) hideTimer.restart() }
    }

    Text {
        id: loadText; anchors.centerIn: parent
        color: "#555"; font.pixelSize: 14; visible: text.length > 0
    }

    Rectangle {
        visible: root._controls
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: 60
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#EE000000" }
            GradientStop { position: 1.0; color: "transparent" }
        }

        BackButton {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin: 12
            onClicked: root.StackView.view.pop()
        }

        Column {
            anchors.centerIn: parent; spacing: 2
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.chapterTitle
                color: "#FFF"; font.pixelSize: 13; font.weight: Font.Medium
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.comicTitle
                color: "#888"; font.pixelSize: 11; visible: root.comicTitle !== ""
            }
        }

        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            visible: pagesModel.count > 0
            height: 24; width: pgCounter.implicitWidth + 16; radius: 12; color: "#33FFFFFF"
            Text {
                id: pgCounter; anchors.centerIn: parent
                text: (pager.currentIndex + 1) + " / " + pagesModel.count
                color: "#FFF"; font.pixelSize: 12
            }
        }
    }

    Item {
        visible: root._controls && pagesModel.count > 0
        anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
        height: 44

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: "#CC000000" }
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.bottomMargin: 12
            height: 3; radius: 2; color: "#1E1E1E"
            Rectangle {
                height: parent.height; radius: 2; color: "#4CAF50"
                width: pagesModel.count > 0
                       ? parent.width * (pager.currentIndex + 1) / pagesModel.count : 0
                Behavior on width { NumberAnimation { duration: 150 } }
            }
        }
    }

    Rectangle {
        visible: root._controls && pager.currentIndex > 0
        anchors.left: parent.left; anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 32; height: 32; radius: 16; color: "#55000000"
        Text { anchors.centerIn: parent; text: "‹"; color: "#CCC"; font.pixelSize: 22 }
    }
    Rectangle {
        visible: root._controls && pager.currentIndex < pagesModel.count - 1
        anchors.right: parent.right; anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 32; height: 32; radius: 16; color: "#55000000"
        Text { anchors.centerIn: parent; text: "›"; color: "#CCC"; font.pixelSize: 22 }
    }
}
