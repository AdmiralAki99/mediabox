import QtQuick
import QtQuick.Controls.Basic
import "../components"

Rectangle {
    id: root
    color: "#0A0A0A"

    property int    tmdbId: 0
    property string title: ""
    property string firstAirDate: ""
    property real   rating: 0
    property string posterPath: ""
    property var    meta: null
    property bool   _metaDone: false
    property int    selectedSeason: 1
    property var    seasons: []
    property string _metaReq: ""
    property string _seasonsReq: ""
    property string _epsReq: ""
    property string _creditsReq: ""
    property string _reviewsReq: ""

    function backdropUrl(p) { return p ? "https://image.tmdb.org/t/p/w780" + p : "" }
    function posterUrl(p)   { return p ? "https://image.tmdb.org/t/p/w342" + p : "" }
    function profileUrl(p)  { return p ? "https://image.tmdb.org/t/p/w185" + p : "" }
    function year()         { return firstAirDate ? firstAirDate.slice(0, 4) : "" }

    Connections {
        target: api
        function onFetched(id, data) {
            var d = JSON.parse(data)

            if (id === root._metaReq && !d.error) {
                root.meta = d
                root._metaDone = true
                return
            }
            if (id === root._seasonsReq && !d.error) {
                root.seasons = Array.isArray(d) ? d : []
                if (root.seasons.length > 0) {
                    root.selectedSeason = root.seasons[0].season_number
                    loadEpisodes(root.seasons[0].season_number)
                }
                return
            }
            if (id === root._epsReq) {
                episodesModel.clear()
                var list = Array.isArray(d) ? d : []
                list.forEach(function(e) { episodesModel.append(e) })
                return
            }
            if (id === root._creditsReq && Array.isArray(d)) {
                castModel.clear()
                d.forEach(function(m) {
                    castModel.append({
                        name:         m.name         || "",
                        character:    m.character    || "",
                        profile_path: m.profile_path || ""
                    })
                })
                return
            }
            if (id === root._reviewsReq && Array.isArray(d)) {
                reviewsModel.clear()
                d.forEach(function(r) {
                    reviewsModel.append({
                        author:     r.author     || "",
                        rating:     r.rating     || 0,
                        content:    r.content    || "",
                        created_at: r.created_at || ""
                    })
                })
                return
            }
        }
    }

    function loadEpisodes(seasonNum) {
        root.selectedSeason = seasonNum
        episodesModel.clear()
        root._epsReq = "series_eps_" + tmdbId + "_" + seasonNum + "_" + Date.now()
        api.fetch(root._epsReq, "/series/" + tmdbId + "/seasons/" + seasonNum + "/episodes", "{}")
    }

    Component.onCompleted: {
        root._metaReq    = "series_meta_"    + tmdbId
        root._seasonsReq = "series_seasons_" + tmdbId
        root._creditsReq = "series_credits_" + tmdbId
        root._reviewsReq = "series_reviews_" + tmdbId
        api.fetch(root._metaReq,    "/series/" + tmdbId + "/meta",    "{}")
        api.fetch(root._seasonsReq, "/series/" + tmdbId + "/seasons", "{}")
        api.fetch(root._creditsReq, "/series/" + tmdbId + "/credits", "{}")
        api.fetch(root._reviewsReq, "/series/" + tmdbId + "/reviews", "{}")
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: pageCol.height + 40
        clip: true
        flickDeceleration: 700
        maximumFlickVelocity: 2800

        ScrollBar.vertical: ScrollBar {
            width: 3
            contentItem: Rectangle {
                radius: 2; color: "#FFFFFF"
                opacity: parent.active ? 0.15 : 0
                Behavior on opacity { NumberAnimation { duration: 500 } }
            }
            background: Item {}
        }

        Column {
            id: pageCol
            width: parent.width
            spacing: 0

            Rectangle {
                width: parent.width; height: 200; color: "#111"
                Image {
                    anchors.fill: parent; asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    source: root.meta ? backdropUrl(root.meta.backdrop_path) : ""
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: "#0A0A0A" }
                    }
                }
                BackButton {
                    anchors.top: parent.top; anchors.left: parent.left
                    anchors.margins: 12
                    onClicked: root.StackView.view.pop()
                }
            }

            Item {
                width: parent.width; height: 116

                Rectangle {
                    x: 16; y: -28
                    width: 88; height: 132; radius: 10; color: "#1A1A1A"
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: posterUrl(root.posterPath)
                        fillMode: Image.PreserveAspectCrop; asynchronous: true
                    }
                }

                Column {
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 120; anchors.rightMargin: 16
                    anchors.top: parent.top; anchors.topMargin: 6
                    spacing: 7

                    Text {
                        width: parent.width; text: root.title
                        color: "#FFFFFF"; font.pixelSize: 18; font.weight: Font.Bold
                        wrapMode: Text.WordWrap
                    }
                    Row {
                        spacing: 10
                        Text { text: root.year(); color: "#666666"; font.pixelSize: 13 }
                        Text {
                            visible: root.meta && root.meta.status
                            text: root.meta ? (root.meta.status || "") : ""
                            color: (root.meta && root.meta.status === "Returning Series")
                                ? "#4CAF50" : "#666666"
                            font.pixelSize: 13
                        }
                        Row {
                            spacing: 3
                            Text { text: "★"; color: "#FFD700"; font.pixelSize: 13 }
                            Text { text: root.rating.toFixed(1); color: "#FFD700"; font.pixelSize: 13 }
                        }
                    }
                    Flow {
                        width: parent.width; spacing: 5
                        Repeater {
                            model: root.meta ? root.meta.genres : []
                            Rectangle {
                                height: 20; radius: 5; color: "#1C1C1C"
                                border.color: "#2E2E2E"; border.width: 1
                                width: gl.implicitWidth + 14
                                Text {
                                    id: gl; anchors.centerIn: parent
                                    text: modelData; color: "#888888"; font.pixelSize: 10
                                }
                            }
                        }
                    }
                }
            }

            Item { width: parent.width; height: 12 }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 24; radius: 20; color: "#141414"
                border.color: "#222222"; border.width: 1
                height: overviewContent.height + 32
                visible: root._metaDone

                Column {
                    id: overviewContent
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 18; anchors.rightMargin: 18; anchors.topMargin: 18
                    spacing: 10

                    Text {
                        text: "Synopsis"
                        color: "#FFFFFF"; font.pixelSize: 13; font.weight: Font.Medium
                    }
                    Text {
                        visible: root.meta && root.meta.tagline && root.meta.tagline.length > 0
                        text: root.meta ? (root.meta.tagline || "") : ""
                        color: "#8B5CF6"; font.pixelSize: 13; font.italic: true
                        wrapMode: Text.WordWrap; width: parent.width
                    }
                    Text {
                        text: root.meta ? (root.meta.overview || "") : ""
                        color: "#888888"; font.pixelSize: 13
                        wrapMode: Text.WordWrap; lineHeight: 1.55; width: parent.width
                    }
                }
            }

            Item { width: parent.width; height: 12 }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 24; height: 174; radius: 20; color: "#141414"
                border.color: "#222222"; border.width: 1
                visible: castModel.count > 0

                Text {
                    id: castHdr
                    anchors.top: parent.top; anchors.left: parent.left
                    anchors.topMargin: 16; anchors.leftMargin: 18
                    text: "Cast"
                    color: "#FFFFFF"; font.pixelSize: 13; font.weight: Font.Medium
                }

                ListView {
                    anchors.top: castHdr.bottom; anchors.topMargin: 12
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    orientation: ListView.Horizontal
                    spacing: 8; clip: true; model: castModel
                    flickDeceleration: 600; maximumFlickVelocity: 2400

                    delegate: Column {
                        width: 68; spacing: 5

                        Rectangle {
                            width: 54; height: 54; radius: 27; color: "#1E1E1E"
                            anchors.horizontalCenter: parent.horizontalCenter
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: model.profile_path ? profileUrl(model.profile_path) : ""
                                fillMode: Image.PreserveAspectCrop; asynchronous: true
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !model.profile_path
                                text: model.name ? model.name[0].toUpperCase() : "?"
                                color: "#444444"; font.pixelSize: 20; font.weight: Font.Light
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 68; text: model.name
                            color: "#CCCCCC"; font.pixelSize: 10; font.weight: Font.Medium
                            wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                            maximumLineCount: 2; elide: Text.ElideRight
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 68; text: model.character
                            color: "#3A3A3A"; font.pixelSize: 9
                            horizontalAlignment: Text.AlignHCenter
                            maximumLineCount: 1; elide: Text.ElideRight
                        }
                    }
                }
            }

            Item { width: parent.width; height: 12 }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 24; radius: 20; color: "#141414"
                border.color: "#222222"; border.width: 1
                height: detailsContent.height + 32
                visible: root._metaDone

                Column {
                    id: detailsContent
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 18; anchors.rightMargin: 18; anchors.topMargin: 18
                    spacing: 0

                    Text {
                        text: "Details"
                        color: "#FFFFFF"; font.pixelSize: 13; font.weight: Font.Medium
                        bottomPadding: 12
                    }

                    Repeater {
                        model: {
                            if (!root.meta) return []
                            var rows = []
                            if (root.meta.number_of_seasons)
                                rows.push({ label: "Seasons", value: root.meta.number_of_seasons + (root.meta.number_of_episodes ? " · " + root.meta.number_of_episodes + " episodes" : "") })
                            if (root.meta.networks && root.meta.networks.length > 0)
                                rows.push({ label: "Network", value: root.meta.networks.join(", ") })
                            if (root.meta.created_by && root.meta.created_by.length > 0)
                                rows.push({ label: "Created by", value: root.meta.created_by.join(", ") })
                            if (root.meta.production_companies && root.meta.production_companies.length > 0)
                                rows.push({ label: "Studio", value: root.meta.production_companies.join(" · ") })
                            if (root.meta.last_air_date)
                                rows.push({ label: "Last aired", value: root.meta.last_air_date })
                            return rows
                        }
                        Item {
                            width: detailsContent.width; height: 38
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 1; color: "#1C1C1C"
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: "#444444"; font.pixelSize: 12
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.value
                                color: "#CCCCCC"; font.pixelSize: 12
                                width: parent.width * 0.62
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Item { width: parent.width; height: 12 }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 24; radius: 20; color: "#141414"
                border.color: "#222222"; border.width: 1
                height: reviewsContent.height + 32
                visible: reviewsModel.count > 0

                Column {
                    id: reviewsContent
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 18; anchors.rightMargin: 18; anchors.topMargin: 18
                    spacing: 0

                    Text {
                        text: "Reviews"
                        color: "#FFFFFF"; font.pixelSize: 13; font.weight: Font.Medium
                        bottomPadding: 12
                    }

                    Repeater {
                        model: reviewsModel
                        Column {
                            width: reviewsContent.width
                            spacing: 8
                            topPadding: index > 0 ? 14 : 0

                            Item {
                                width: parent.width; height: 18
                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: model.author
                                    color: "#DDDDDD"; font.pixelSize: 13; font.weight: Font.Medium
                                    elide: Text.ElideRight; width: parent.width - 120
                                }
                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    Row {
                                        visible: model.rating > 0; spacing: 3
                                        Text { text: "★"; color: "#FFD700"; font.pixelSize: 11 }
                                        Text {
                                            text: (model.rating || 0).toFixed(1)
                                            color: "#FFD700"; font.pixelSize: 11
                                        }
                                    }
                                    Text {
                                        text: model.created_at
                                        color: "#333333"; font.pixelSize: 11
                                    }
                                }
                            }
                            Text {
                                width: parent.width; text: model.content
                                color: "#666666"; font.pixelSize: 12
                                wrapMode: Text.WordWrap; lineHeight: 1.45
                                maximumLineCount: 5; elide: Text.ElideRight
                            }
                            Rectangle {
                                width: parent.width; height: 1; color: "#1C1C1C"
                                visible: index < reviewsModel.count - 1
                            }
                        }
                    }
                }
            }

            Item { width: parent.width; height: 16 }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 24; radius: 20; color: "#141414"
                border.color: "#222222"; border.width: 1
                height: episodesSection.height + 24
                visible: root.seasons.length > 0

                Column {
                    id: episodesSection
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.topMargin: 16
                    spacing: 0

                    // Season pills
                    Item {
                        width: parent.width; height: 40
                        ListView {
                            anchors.fill: parent
                            anchors.leftMargin: 14; anchors.rightMargin: 14
                            orientation: ListView.Horizontal
                            spacing: 8; clip: true
                            model: root.seasons
                            delegate: Rectangle {
                                height: 28; width: sl.implicitWidth + 20
                                anchors.verticalCenter: parent.verticalCenter
                                radius: 8
                                color: root.selectedSeason === modelData.season_number ? "#8B5CF6" : "#1E1E1E"
                                border.color: root.selectedSeason === modelData.season_number ? "#8B5CF6" : "#2E2E2E"
                                border.width: 1
                                Text {
                                    id: sl; anchors.centerIn: parent
                                    text: "S" + modelData.season_number
                                    color: "#FFFFFF"; font.pixelSize: 12; font.weight: Font.Medium
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: loadEpisodes(modelData.season_number)
                                }
                            }
                        }
                    }

                    // Divider
                    Rectangle { width: parent.width; height: 1; color: "#1C1C1C" }

                    // Episodes list
                    Repeater {
                        model: episodesModel
                        Item {
                            width: episodesSection.width; height: 68

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 1; color: "#1C1C1C"
                                visible: index < episodesModel.count - 1
                            }

                            Column {
                                anchors.left: parent.left; anchors.right: playBtn.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 16; anchors.rightMargin: 10
                                spacing: 4

                                Text {
                                    width: parent.width
                                    text: "E" + model.episode_number + "  " + (model.title || "")
                                    color: "#EEEEEE"; font.pixelSize: 13; font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: model.runtime ? model.runtime + " min"
                                                       : (model.release_date || "")
                                    color: "#444444"; font.pixelSize: 11
                                }
                                Text {
                                    visible: model.overview && model.overview.length > 0
                                    width: parent.width
                                    text: model.overview || ""
                                    color: "#333333"; font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                id: playBtn
                                anchors.right: parent.right; anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 36; height: 36; radius: 10; color: "#1E1E1E"
                                border.color: "#2A2A2A"; border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "▶"; color: "#8B5CF6"; font.pixelSize: 14
                                }
                                scale: epMA.pressed ? 0.9 : 1.0
                                Behavior on scale { SpringAnimation { spring: 7; damping: 0.45 } }
                                MouseArea {
                                    id: epMA; anchors.fill: parent
                                    onClicked: {
                                        var streams = JSON.parse(api.seriesStream(
                                            root.tmdbId, root.selectedSeason, model.episode_number, root.title))
                                        if (!streams || streams.error || !streams.length) return
                                        var s = streams[0]
                                        api.recordHistory(JSON.stringify({
                                            media_type: "series", title: root.title, tmdb_id: root.tmdbId,
                                            season_num: root.selectedSeason, episode_num: model.episode_number
                                        }))
                                        root.StackView.view.push(Qt.resolvedUrl("Player.qml"), {
                                            streamUrl: s.url, referrer: s.referrer || "",
                                            title: root.title + " S" + root.selectedSeason + "E" + model.episode_number,
                                            subtitles: s.subtitles || []
                                        })
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item { width: parent.width; height: 32 }
        }
    }

    ListModel { id: castModel }
    ListModel { id: reviewsModel }
    ListModel { id: episodesModel }
}
