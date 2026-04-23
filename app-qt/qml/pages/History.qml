import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#0A0A0A"

    property var filterTypes: ["all", "movie", "series", "anime", "manga", "comic"]
    property int filterIndex: 0

    property string _reqId: ""

    Connections {
        target: api
        function onFetched(id, data) {
            if (id !== root._reqId) return
            var d = JSON.parse(data)
            if (d.error) return
            historyModel.clear()
            var list = Array.isArray(d) ? d : (d.results || d)
            list.forEach(function(item) { historyModel.append(item) })
        }
    }

    Component.onCompleted: loadHistory()

    function loadHistory() {
        historyModel.clear()
        root._reqId = "history_" + filterIndex + "_" + Date.now()
        var path   = "/history"
        var params = filterIndex === 0 ? "{}" : JSON.stringify({ media_type: filterTypes[filterIndex] })
        api.fetch(root._reqId, path, params)
    }

    function mediaIcon(t) {
        return t === "movie"  ? "🎬" :
               t === "series" ? "📺" :
               t === "anime"  ? "⛩"  :
               t === "manga"  ? "📖" :
               t === "comic"  ? "💬" : "📄"
    }
    function timeAgo(dt) {
        if (!dt) return ""
        var d = new Date(dt), now = new Date()
        var diff = Math.floor((now - d) / 1000)
        if (diff < 60)   return diff + "s ago"
        if (diff < 3600) return Math.floor(diff/60) + "m ago"
        if (diff < 86400) return Math.floor(diff/3600) + "h ago"
        return Math.floor(diff/86400) + "d ago"
    }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Text { text: "History"; color: "#FFF"; font.pixelSize: 22; font.weight: Font.Bold }
            Item { Layout.fillWidth: true }
            Rectangle {
                width: 70; height: 30; radius: 8; color: "#1E1E1E"; border.color: "#333"; border.width: 1
                Text { anchors.centerIn: parent; text: "Clear all"; color: "#8B5CF6"; font.pixelSize: 12 }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        api.clearHistory()
                        historyModel.clear()
                        root.loadHistory()
                    }
                }
            }
        }

        Row {
            spacing: 8
            Repeater {
                model: ["All", "Movies", "Series", "Anime", "Manga", "Comics"]
                Rectangle {
                    height: 28; width: chipLabel.implicitWidth + 20; radius: 6
                    color: root.filterIndex === index ? "#8B5CF6" : "#1E1E1E"
                    border.color: root.filterIndex === index ? "#8B5CF6" : "#333"; border.width: 1
                    Text { id: chipLabel; anchors.centerIn: parent; text: modelData; color: "#FFF"; font.pixelSize: 12 }
                    MouseArea { anchors.fill: parent; onClicked: { root.filterIndex = index; root.loadHistory() } }
                }
            }
        }

        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 1; model: historyModel

            delegate: Rectangle {
                width: ListView.view.width; height: 62; color: "#0A0A0A"
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#1A1A1A" }

                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 12; spacing: 12

                    // Type icon
                    Text { text: root.mediaIcon(model.media_type); font.pixelSize: 22 }

                    // Title + meta
                    Column {
                        Layout.fillWidth: true; spacing: 3
                        Text {
                            width: parent.width
                            text: model.title || ""
                            color: "#FFF"; font.pixelSize: 14; elide: Text.ElideRight
                        }
                        Row {
                            spacing: 8
                            Text {
                                visible: model.season_num > 0
                                text: "S" + model.season_num + "E" + model.episode_num
                                color: "#888"; font.pixelSize: 11
                            }
                            Text {
                                visible: model.chapter_id !== ""
                                text: "Chapter"
                                color: "#888"; font.pixelSize: 11
                            }
                            Text {
                                text: root.timeAgo(model.watched_at)
                                color: "#555"; font.pixelSize: 11
                            }
                        }
                    }

                    // Completed badge
                    Rectangle {
                        visible: model.completed === true
                        width: 16; height: 16; radius: 8; color: "#4CAF50"
                        Text { anchors.centerIn: parent; text: "✓"; color: "#FFF"; font.pixelSize: 9 }
                    }
                }
            }
        }
    }

    ListModel { id: historyModel }
}
