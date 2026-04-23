import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    color: "#0A0A0A"
    property string _reqId: ""

    function posterUrl(p) { return p ? "https://image.tmdb.org/t/p/w342" + p : "" }

    Connections {
        target: api
        function onFetched(id, data) {
            if (id !== root._reqId) return
            var result = JSON.parse(data)
            if (result.error) { statusText.text = "Error"; return }
            resultsModel.clear()
            var list = result.results || []
            list.forEach(function(item) { resultsModel.append(item) })
            statusText.text = sf.text.trim() === "" ? "Trending" : list.length + " results"
        }
    }

    function loadTrending() {
        root._reqId = "series_t_" + Date.now(); statusText.text = "Loading…"
        api.fetch(root._reqId, "/series/trending", "{}")
    }
    function doSearch(q) {
        if (!q.trim()) { loadTrending(); return }
        root._reqId = "series_s_" + Date.now(); statusText.text = "Searching…"
        api.fetch(root._reqId, "/series/search", JSON.stringify({ q: q }))
    }

    Component.onCompleted: loadTrending()

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Text { text: "Series"; color: "#FFF"; font.pixelSize: 22; font.weight: Font.Bold }
            Item { Layout.fillWidth: true }
            Text { id: statusText; color: "#666"; font.pixelSize: 12 }
        }
        Rectangle {
            Layout.fillWidth: true; height: 42; radius: 10; color: "#1E1E1E"
            border.color: sf.activeFocus ? "#8B5CF6" : "#333"; border.width: 1
            RowLayout { anchors.fill: parent; anchors.margins: 10; spacing: 8
                Text { text: "🔍"; font.pixelSize: 16 }
                TextField { id: sf; Layout.fillWidth: true; placeholderText: "Search series…"
                    color: "#FFF"; font.pixelSize: 14; background: null; placeholderTextColor: "#555"
                    onTextChanged: t.restart(); Keys.onReturnPressed: { t.stop(); doSearch(text) } }
                Text { visible: sf.text.length > 0; text: "✕"; color: "#666"; font.pixelSize: 14
                    MouseArea { anchors.fill: parent; onClicked: { sf.text = ""; loadTrending() } } }
            }
        }
        Timer { id: t; interval: 400; onTriggered: doSearch(sf.text) }
        GridView {
            id: grid; Layout.fillWidth: true; Layout.fillHeight: true
            cellWidth: Math.floor(width / 4); cellHeight: 210; clip: true; model: resultsModel
            delegate: Item { width: grid.cellWidth; height: 210
                PosterCard { anchors.centerIn: parent; width: grid.cellWidth - 10; height: 195
                    posterUrl: root.posterUrl(model.poster_path); title: model.title || ""; rating: model.rating || 0
                    onTapped: root.StackView.view.push(Qt.resolvedUrl("SeriesDetail.qml"), {
                        tmdbId: model.id, title: model.title || "",
                        firstAirDate: model.first_air_date || "",
                        rating: model.rating || 0, posterPath: model.poster_path || "" })
                }
            }
        }
    }
    ListModel { id: resultsModel }
}
