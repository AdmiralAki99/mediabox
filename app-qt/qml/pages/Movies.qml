import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    color: "#0A0A0A"
    property string _reqId: ""
    property int    _tab: 0   // 0=trending  1=now playing  2=upcoming

    function posterUrl(path) { return path ? "https://image.tmdb.org/t/p/w342" + path : "" }

    Connections {
        target: api
        function onFetched(id, data) {
            if (id !== root._reqId) return
            var result = JSON.parse(data)
            if (result.error) { statusText.text = "Error"; return }
            resultsModel.clear()
            var list = result.results || []
            list.forEach(function(item) { resultsModel.append(item) })
            var labels = ["Trending", "Now Playing", "Upcoming"]
            statusText.text = searchField.text.trim() !== ""
                ? list.length + " results"
                : labels[root._tab]
        }
    }

    function loadTab(tab) {
        root._tab = tab
        searchField.text = ""
        root._reqId = "movies_tab_" + Date.now()
        statusText.text = "Loading…"
        var endpoints = ["/movies/trending", "/movies/now-playing", "/movies/upcoming"]
        api.fetch(root._reqId, endpoints[tab], "{}")
    }

    function doSearch(q) {
        if (q.trim() === "") { loadTab(root._tab); return }
        root._reqId = "movies_s_" + Date.now()
        statusText.text = "Searching…"
        api.fetch(root._reqId, "/movies/search", JSON.stringify({ q: q }))
    }

    Component.onCompleted: loadTab(0)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Text { text: "Movies"; color: "#FFFFFF"; font.pixelSize: 20; font.weight: Font.Bold }
            Item { Layout.fillWidth: true }
            Text { id: statusText; color: "#555"; font.pixelSize: 11 }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 48
            radius: 16; color: "#141414"
            border.color: "#222222"; border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 6

                Repeater {
                    model: ["Trending", "Now Playing", "Upcoming"]
                    Rectangle {
                        height: 30; width: tabLabel.implicitWidth + 22; radius: 15
                        color: root._tab === index ? "#252525" : "transparent"
                        border.color: root._tab === index ? "#3A3A3A" : "transparent"; border.width: 1
                        Text {
                            id: tabLabel; anchors.centerIn: parent; text: modelData
                            color: root._tab === index ? "#FFFFFF" : "#444444"
                            font.pixelSize: 12
                            font.weight: root._tab === index ? Font.Medium : Font.Normal
                        }
                        scale: tabMA.containsPress ? 0.90 : 1.0
                        Behavior on scale { SpringAnimation { spring: 7; damping: 0.42 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Rectangle { anchors.fill: parent; radius: parent.radius; color: "white"
                            opacity: tabMA.containsPress ? 0.07 : 0; Behavior on opacity { NumberAnimation { duration: 100 } } }
                        MouseArea { id: tabMA; anchors.fill: parent; onClicked: loadTab(index) }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true; height: 40; radius: 10; color: "#141414"
            border.color: searchField.activeFocus ? "#8B5CF6" : "#222"; border.width: 1
            RowLayout {
                anchors.fill: parent; anchors.margins: 10; spacing: 8
                Text { text: "🔍"; font.pixelSize: 15 }
                TextField {
                    id: searchField; Layout.fillWidth: true; placeholderText: "Search movies…"
                    color: "#FFF"; font.pixelSize: 13; background: null; placeholderTextColor: "#444"
                    onTextChanged: searchTimer.restart()
                    Keys.onReturnPressed: { searchTimer.stop(); doSearch(text) }
                }
                Text {
                    visible: searchField.text.length > 0; text: "✕"; color: "#555"; font.pixelSize: 13
                    MouseArea { anchors.fill: parent; onClicked: { searchField.text = ""; loadTab(root._tab) } }
                }
            }
        }
        Timer { id: searchTimer; interval: 400; onTriggered: doSearch(searchField.text) }

        GridView {
            id: grid
            Layout.fillWidth: true; Layout.fillHeight: true
            cellWidth: Math.floor(width / 4); cellHeight: 210; clip: true
            model: resultsModel
            flickDeceleration: 700; maximumFlickVelocity: 2800
            ScrollBar.vertical: ScrollBar { width: 3
                contentItem: Rectangle { radius: 2; color: "#FFFFFF"
                    opacity: parent.active ? 0.15 : 0; Behavior on opacity { NumberAnimation { duration: 500 } } }
                background: Item {} }
            delegate: Item {
                width: grid.cellWidth; height: grid.cellHeight
                PosterCard {
                    anchors.centerIn: parent; width: grid.cellWidth - 10; height: 195
                    posterUrl: root.posterUrl(model.poster_path)
                    title: model.title || ""; rating: model.rating || 0
                    onTapped: root.StackView.view.push(Qt.resolvedUrl("MovieDetail.qml"), {
                        tmdbId: model.id, title: model.title || "",
                        releaseDate: model.release_date || "",
                        rating: model.rating || 0, posterPath: model.poster_path || ""
                    })
                }
            }
        }
    }

    ListModel { id: resultsModel }
}
