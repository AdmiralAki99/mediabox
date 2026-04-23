import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    color: "#0A0A0A"

    property string _reqId:       ""
    property string _schedReqId:  ""
    property int    _tab:         0   // 0=trending  1=top-rated  2=airing  3=schedule
    property int    _schedDay:    0   // 0=today … 6=+6 days

    function posterUrl(p) { return p ? "https://image.tmdb.org/t/p/w342" + p : "" }

    function formatAirTime(ts) {
        var d = new Date(ts * 1000)
        var h = d.getHours()
        var m = d.getMinutes()
        var ampm = h >= 12 ? "PM" : "AM"
        h = h % 12 || 12
        return h + ":" + (m < 10 ? "0" : "") + m + " " + ampm
    }

    function dayLabel(offset) {
        if (offset === 0) return "Today"
        if (offset === 1) return "Tomorrow"
        var d = new Date()
        d.setDate(d.getDate() + offset)
        return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][d.getDay()]
    }

    Connections {
        target: api
        function onFetched(id, data) {
            // Browse tabs (trending / top-rated / airing)
            if (id === root._reqId) {
                var res = JSON.parse(data)
                if (res.error) { statusText.text = "Error"; return }
                resultsModel.clear()
                var list = res.results || []
                list.forEach(function(item) {
                    resultsModel.append({
                        tmdb_id:        item.id            || 0,
                        title:          item.title         || item.name || "",
                        poster_path:    item.poster_path   || "",
                        rating:         item.rating        || 0,
                        first_air_date: item.first_air_date || ""
                    })
                })
                var labels = ["Trending", "Top Rated", "Airing"]
                statusText.text = searchField.text.trim() !== ""
                    ? list.length + " results"
                    : labels[root._tab]
                return
            }

            // Schedule tab
            if (id === root._schedReqId) {
                scheduleModel.clear()
                var entries = JSON.parse(data)
                if (!Array.isArray(entries)) {
                    schedStatus.text = "Error loading schedule"
                    return
                }
                entries.forEach(function(e) {
                    scheduleModel.append({
                        media_id:   e.media_id   || 0,
                        title:      e.title      || "",
                        cover:      e.cover_image || "",
                        episode:    e.episode    || 0,
                        airing_at:  e.airing_at  || 0,
                        total_eps:  e.total_episodes || 0,
                        genres:     (e.genres || []).slice(0, 2).join("  ·  ")
                    })
                })
                schedStatus.text = entries.length > 0
                    ? entries.length + " airing"
                    : "Nothing scheduled"
                return
            }
        }
    }

    function loadTab(tab) {
        root._tab = tab
        if (tab === 3) { loadSchedule(root._schedDay); return }
        searchField.text = ""
        root._reqId = "anime_tab_" + Date.now()
        statusText.text = "Loading…"
        var eps = ["/anime/tmdb/trending", "/anime/tmdb/top-rated", "/anime/tmdb/airing-now"]
        api.fetch(root._reqId, eps[tab], "{}")
    }

    function doSearch(q) {
        if (!q.trim()) { loadTab(root._tab); return }
        root._reqId = "anime_s_" + Date.now()
        statusText.text = "Searching…"
        api.fetch(root._reqId, "/anime/tmdb/search", JSON.stringify({ q: q }))
    }

    function loadSchedule(day) {
        root._schedDay = day
        schedStatus.text = "Loading…"
        scheduleModel.clear()
        root._schedReqId = "anime_sched_" + day + "_" + Date.now()
        api.fetch(root._schedReqId, "/anime/schedule", JSON.stringify({ offset_days: day }))
    }

    Component.onCompleted: loadTab(0)

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 12; spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Text { text: "Anime"; color: "#FFF"; font.pixelSize: 20; font.weight: Font.Bold }
            Item { Layout.fillWidth: true }
            Text {
                id: statusText
                visible: root._tab !== 3
                color: "#555"; font.pixelSize: 11
            }
            Text {
                id: schedStatus
                visible: root._tab === 3
                color: "#555"; font.pixelSize: 11
            }
        }

        Rectangle {
            Layout.fillWidth: true; height: 48; radius: 16; color: "#141414"
            border.color: "#222222"; border.width: 1
            Row {
                anchors.centerIn: parent; spacing: 6
                Repeater {
                    model: ["Trending", "Top Rated", "Airing", "Schedule"]
                    Rectangle {
                        height: 30; width: tl.implicitWidth + 22; radius: 15
                        color: root._tab === index ? "#252525" : "transparent"
                        border.color: root._tab === index ? "#3A3A3A" : "transparent"; border.width: 1
                        Text {
                            id: tl; anchors.centerIn: parent; text: modelData
                            color: root._tab === index ? "#FFF" : "#444"
                            font.pixelSize: 12
                            font.weight: root._tab === index ? Font.Medium : Font.Normal
                        }
                        scale: tma.containsPress ? 0.9 : 1.0
                        Behavior on scale { SpringAnimation { spring: 7; damping: 0.42 } }
                        Behavior on color  { ColorAnimation { duration: 150 } }
                        Rectangle { anchors.fill: parent; radius: parent.radius; color: "white"
                            opacity: tma.containsPress ? 0.07 : 0
                            Behavior on opacity { NumberAnimation { duration: 100 } } }
                        MouseArea { id: tma; anchors.fill: parent; onClicked: loadTab(index) }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true; height: 40; radius: 10; color: "#141414"
            visible: root._tab !== 3
            border.color: searchField.activeFocus ? "#8B5CF6" : "#222"; border.width: 1
            RowLayout {
                anchors.fill: parent; anchors.margins: 10; spacing: 8
                Text { text: "🔍"; font.pixelSize: 15 }
                TextField {
                    id: searchField; Layout.fillWidth: true; placeholderText: "Search anime…"
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

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root._tab === 3
            spacing: 8

            // Day picker
            Item {
                Layout.fillWidth: true; height: 36
                Flickable {
                    anchors.fill: parent
                    contentWidth: dayRow.width
                    flickableDirection: Flickable.HorizontalFlick
                    clip: true
                    Row {
                        id: dayRow; spacing: 6; anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: 7
                            Rectangle {
                                height: 28; width: dl.implicitWidth + 18; radius: 14
                                color: root._schedDay === index ? "#8B5CF6" : "#1A1A1A"
                                border.color: root._schedDay === index ? "#8B5CF6" : "#2A2A2A"
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Text {
                                    id: dl; anchors.centerIn: parent
                                    text: root.dayLabel(index)
                                    color: root._schedDay === index ? "#FFF" : "#666"
                                    font.pixelSize: 11; font.weight: Font.Medium
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: loadSchedule(index)
                                }
                            }
                        }
                    }
                }
            }

            // Schedule list
            ListView {
                id: scheduleList
                Layout.fillWidth: true; Layout.fillHeight: true
                model: scheduleModel
                spacing: 6; clip: true
                flickDeceleration: 700; maximumFlickVelocity: 2800
                ScrollBar.vertical: ScrollBar { width: 3
                    contentItem: Rectangle { radius: 2; color: "#FFF"
                        opacity: parent.active ? 0.15 : 0
                        Behavior on opacity { NumberAnimation { duration: 500 } } }
                    background: Item {} }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    visible: scheduleModel.count === 0 && schedStatus.text !== "Loading…"
                    text: "Nothing airing " + root.dayLabel(root._schedDay).toLowerCase()
                    color: "#444"; font.pixelSize: 13
                }

                delegate: Rectangle {
                    width: scheduleList.width; height: 72
                    radius: 10; color: "#141414"
                    border.color: "#1E1E1E"; border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 14
                        spacing: 12

                        // Cover thumbnail
                        Rectangle {
                            width: 42; height: 56; radius: 6; color: "#0D0D0D"
                            clip: true
                            Image {
                                anchors.fill: parent; asynchronous: true
                                fillMode: Image.PreserveAspectCrop; smooth: true
                                source: model.cover || ""
                            }
                        }

                        // Title + meta
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 3

                            Text {
                                Layout.fillWidth: true
                                text: model.title
                                color: "#EEE"; font.pixelSize: 13; font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                spacing: 8
                                Text {
                                    text: "Ep " + model.episode
                                         + (model.total_eps > 0 ? " / " + model.total_eps : "")
                                    color: "#8B5CF6"; font.pixelSize: 11
                                }
                                Text {
                                    text: model.genres
                                    color: "#555"; font.pixelSize: 11
                                    visible: model.genres !== ""
                                }
                            }
                        }

                        // Air time
                        Text {
                            text: root.formatAirTime(model.airing_at)
                            color: "#888"; font.pixelSize: 11
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }

        GridView {
            id: grid; Layout.fillWidth: true; Layout.fillHeight: true
            visible: root._tab !== 3
            cellWidth: Math.floor(width / 4); cellHeight: 210; clip: true; model: resultsModel
            flickDeceleration: 700; maximumFlickVelocity: 2800
            ScrollBar.vertical: ScrollBar { width: 3
                contentItem: Rectangle { radius: 2; color: "#FFF"
                    opacity: parent.active ? 0.15 : 0
                    Behavior on opacity { NumberAnimation { duration: 500 } } }
                background: Item {} }
            delegate: Item {
                width: grid.cellWidth; height: 210
                PosterCard {
                    anchors.centerIn: parent; width: grid.cellWidth - 10; height: 195
                    posterUrl: root.posterUrl(model.poster_path)
                    title: model.title; rating: model.rating
                    onTapped: root.StackView.view.push(Qt.resolvedUrl("AnimeDetail.qml"), {
                        tmdbId:    model.tmdb_id,
                        animeName: model.title,
                        posterPath: model.poster_path || "",
                        year:      model.first_air_date ? model.first_air_date.slice(0, 4) : ""
                    })
                }
            }
        }
    }

    ListModel { id: resultsModel }
    ListModel { id: scheduleModel }
}
