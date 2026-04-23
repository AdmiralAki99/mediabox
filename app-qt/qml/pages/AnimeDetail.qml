import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    color: "#0A0A0A"

    property int    tmdbId:    0
    property string animeName: ""
    property string posterPath: ""   // TMDB path like "/abc.jpg"
    property string year:      ""

    property var  _meta:          null
    property bool _metaDone:      false
    property var  seasons:        []   // [{name, identifier}]
    property int  selectedSeason: -1
    property bool _streaming:     false

    property string _metaReq:   ""
    property string _searchReq: ""
    property string _epsReq:    ""

    function backdropUrl(p) { return p ? "https://image.tmdb.org/t/p/w780" + p  : "" }
    function posterUrl(p)   { return p ? "https://image.tmdb.org/t/p/w342" + p  : "" }

    Connections {
        target: api
        function onFetched(id, data) {
            var d = JSON.parse(data)

            if (id === root._metaReq && !d.error) {
                root._meta    = d
                root._metaDone = true
                return
            }

            if (id === root._searchReq) {
                if (d.error) { epStatus.text = "Not found on AllAnime"; return }
                var results = d.results || []
                var built = []
                results.forEach(function(r) {
                    var prov = r.providers && r.providers.length > 0 ? r.providers[0] : null
                    if (prov && prov.identifier)
                        built.push({ name: r.name, identifier: prov.identifier })
                })
                root.seasons = built
                if (built.length === 0) { epStatus.text = "No streaming source found"; return }
                loadEpisodes(0)
                return
            }

            if (id === root._epsReq) {
                episodesModel.clear()
                if (d.error) { epStatus.text = "Failed to load episodes"; return }
                var list = Array.isArray(d) ? d : (d.results || [])
                list.forEach(function(e) { episodesModel.append({ number: e.number }) })
                epStatus.text = list.length + " episode" + (list.length !== 1 ? "s" : "")
                return
            }
        }
    }

    function loadEpisodes(idx) {
        if (idx < 0 || idx >= root.seasons.length) return
        root.selectedSeason = idx
        episodesModel.clear()
        epStatus.text = "Loading…"
        var s = root.seasons[idx]
        root._epsReq = "anime_eps_" + s.identifier + "_" + Date.now()
        api.fetch(root._epsReq, "/anime/allanime/" + s.identifier + "/episodes", "{}")
    }

    Component.onCompleted: Qt.callLater(function() {
        if (root.tmdbId > 0) {
            root._metaReq = "anime_meta_" + root.tmdbId
            api.fetch(root._metaReq, "/series/" + root.tmdbId + "/meta", "{}")
        }
        root._searchReq = "anime_allanime_" + Date.now()
        api.fetch(root._searchReq, "/anime/search", JSON.stringify({ q: root.animeName }))
    })

    Flickable {
        anchors.fill: parent
        contentHeight: pageCol.height + 24
        flickableDirection: Flickable.VerticalFlick
        flickDeceleration: 700; maximumFlickVelocity: 2800
        ScrollBar.vertical: ScrollBar { width: 3
            contentItem: Rectangle { radius: 2; color: "#FFF"
                opacity: parent.active ? 0.15 : 0
                Behavior on opacity { NumberAnimation { duration: 500 } } }
            background: Item {} }

        Column {
            id: pageCol
            width: parent.width
            spacing: 0

            Rectangle {
                width: parent.width; height: 240; color: "#111"

                Image {
                    anchors.fill: parent; asynchronous: true
                    fillMode: Image.PreserveAspectCrop; smooth: true
                    source: root._metaDone && root._meta && root._meta.backdrop_path
                        ? backdropUrl(root._meta.backdrop_path)
                        : posterUrl(root.posterPath)
                }
                // gradient fade to page background
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.7; color: "#CC0A0A0A" }
                        GradientStop { position: 1.0; color: "#0A0A0A" }
                    }
                }

                BackButton {
                    anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 12
                    onClicked: root.StackView.view.pop()
                }

                Column {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: 16; spacing: 6

                    Text {
                        text: root.animeName; width: parent.width
                        color: "#FFF"; font.pixelSize: 20; font.weight: Font.Bold
                        wrapMode: Text.WordWrap
                    }

                    Row {
                        spacing: 10
                        Text {
                            visible: root.year !== ""
                            text: root.year; color: "#777"; font.pixelSize: 12
                        }
                        Text {
                            visible: root._metaDone && root._meta && (root._meta.status || "") !== ""
                            text: root._meta ? (root._meta.status || "") : ""
                            color: root._meta && root._meta.status === "Returning Series"
                                   ? "#4CAF50" : "#777"
                            font.pixelSize: 12
                        }
                        Text {
                            visible: root._metaDone && root._meta && root._meta.number_of_episodes > 0
                            text: root._meta ? (root._meta.number_of_episodes + " eps") : ""
                            color: "#777"; font.pixelSize: 12
                        }
                    }
                }
            }

            Item {
                width: parent.width; height: 38
                visible: root._metaDone && root._meta
                         && root._meta.genres && root._meta.genres.length > 0
                Flickable {
                    anchors.fill: parent; anchors.leftMargin: 16
                    contentWidth: genreRow.width; flickableDirection: Flickable.HorizontalFlick
                    clip: true
                    Row {
                        id: genreRow; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        Repeater {
                            model: root._meta ? root._meta.genres : []
                            Rectangle {
                                height: 22; width: gl.implicitWidth + 14; radius: 11
                                color: "#1A1A1A"; border.color: "#2A2A2A"; border.width: 1
                                Text {
                                    id: gl; anchors.centerIn: parent; text: modelData
                                    color: "#888"; font.pixelSize: 10
                                }
                            }
                        }
                    }
                }
            }

            Item { width: 1; height: 12 }

            Rectangle {
                width: parent.width - 32; x: 16
                visible: root._metaDone && root._meta
                         && root._meta.overview && root._meta.overview.length > 0
                height: synCol.implicitHeight + 28; radius: 16
                color: "#141414"; border.color: "#222"; border.width: 1

                Column {
                    id: synCol
                    width: parent.width - 32; anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top; anchors.topMargin: 14; spacing: 8

                    Text {
                        text: "Synopsis"; color: "#FFF"
                        font.pixelSize: 13; font.weight: Font.Medium
                    }
                    Text {
                        width: parent.width
                        text: root._meta ? (root._meta.overview || "") : ""
                        color: "#888"; font.pixelSize: 13
                        wrapMode: Text.WordWrap; lineHeight: 1.55
                    }
                }
            }

            Item { width: 1; height: 12 }

            Rectangle {
                width: parent.width - 32; x: 16
                height: epsCol.implicitHeight + 28; radius: 16
                color: "#141414"; border.color: "#222"; border.width: 1

                Column {
                    id: epsCol
                    width: parent.width - 32; anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top; anchors.topMargin: 14; spacing: 10

                    RowLayout {
                        width: parent.width
                        Text {
                            text: "Episodes"; color: "#FFF"
                            font.pixelSize: 13; font.weight: Font.Medium
                        }
                        Item { Layout.fillWidth: true }
                        Text { id: epStatus; text: "Searching…"; color: "#555"; font.pixelSize: 11 }
                    }

                    ComboBox {
                        id: seasonPicker
                        width: parent.width
                        visible: root.seasons.length > 1
                        model: root.seasons.map(function(s) { return s.name })
                        currentIndex: root.selectedSeason
                        onActivated: function(index) { loadEpisodes(index) }

                        background: Rectangle {
                            radius: 8; color: "#1E1E1E"
                            border.color: "#333"; border.width: 1
                        }
                        contentItem: Text {
                            leftPadding: 10; rightPadding: 30
                            text: seasonPicker.displayText
                            color: "#FFF"; font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                        }
                        indicator: Text {
                            x: seasonPicker.width - width - 10
                            y: (seasonPicker.height - height) / 2
                            text: "▾"; color: "#888"; font.pixelSize: 12
                        }
                        delegate: ItemDelegate {
                            width: seasonPicker.popup.width
                            contentItem: Text {
                                text: modelData; color: "#FFF"; font.pixelSize: 13
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 10; elide: Text.ElideRight
                            }
                            background: Rectangle {
                                color: highlighted ? "#8B5CF6" : (hovered ? "#2A2A2A" : "#1E1E1E")
                            }
                            highlighted: seasonPicker.currentIndex === index
                        }
                        popup: Popup {
                            y: seasonPicker.height + 4; width: seasonPicker.width; padding: 0
                            contentItem: ListView {
                                clip: true; model: seasonPicker.delegateModel
                                implicitHeight: Math.min(contentHeight, 200)
                            }
                            background: Rectangle {
                                color: "#1E1E1E"; radius: 8
                                border.color: "#333"; border.width: 1
                            }
                        }
                    }

                    Repeater {
                        model: episodesModel
                        Rectangle {
                            width: epsCol.width; height: 50; radius: 10; color: "#1A1A1A"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14; anchors.rightMargin: 14

                                Text {
                                    text: "Episode " + (model.number % 1 === 0
                                          ? Math.floor(model.number)
                                          : model.number.toFixed(1))
                                    color: "#EEE"; font.pixelSize: 14
                                }
                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    width: 36; height: 36; radius: 8
                                    color: pma.containsPress ? "#111" : "#222"
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "▶"; color: "#8B5CF6"; font.pixelSize: 14
                                    }
                                    MouseArea {
                                        id: pma; anchors.fill: parent
                                        enabled: !root._streaming
                                        onClicked: {
                                            var season = root.seasons[root.selectedSeason]
                                            if (!season) return
                                            root._streaming = true
                                            var raw = api.animeStream(
                                                "allanime", season.identifier,
                                                String(model.number))
                                            root._streaming = false
                                            var streams = JSON.parse(raw)
                                            if (!streams || streams.error || !streams.length) return
                                            var s = streams[0]
                                            api.recordHistory(JSON.stringify({
                                                media_type:        "anime",
                                                title:             root.animeName,
                                                poster_path:       root.posterPath,
                                                anime_provider_id: season.identifier,
                                                episode_num:       model.number
                                            }))
                                            root.StackView.view.push(
                                                Qt.resolvedUrl("Player.qml"), {
                                                    streamUrl: s.url,
                                                    referrer:  s.referrer || "",
                                                    title:     root.animeName
                                                             + " Ep "
                                                             + Math.floor(model.number)
                                                })
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item { width: 1; height: 24 }
        }
    }

    Rectangle {
        anchors.fill: parent; color: "#B0000000"
        visible: root._streaming
        Column {
            anchors.centerIn: parent; spacing: 12
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Resolving stream…"; color: "#FFF"; font.pixelSize: 15
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "This may take a few seconds"; color: "#666"; font.pixelSize: 12
            }
        }
    }

    ListModel { id: episodesModel }
}
