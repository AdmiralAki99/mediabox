import QtQuick
import QtQuick.Controls.Basic
import "../components"

Rectangle {
    id: root
    color: "#0A0A0A"

    property int    tmdbId: 0
    property string title: ""
    property string releaseDate: ""
    property real   rating: 0
    property string posterPath: ""
    property var    meta: null
    property bool   _metaDone: false
    property string _metaReq: ""
    property string _creditsReq: ""
    property string _reviewsReq: ""

    function backdropUrl(p) { return p ? "https://image.tmdb.org/t/p/w780" + p : "" }
    function posterUrl(p)   { return p ? "https://image.tmdb.org/t/p/w342" + p : "" }
    function profileUrl(p)  { return p ? "https://image.tmdb.org/t/p/w185" + p : "" }
    function year()         { return releaseDate ? releaseDate.slice(0, 4) : "" }
    function formatMoney(n) {
        if (!n || n < 100000) return ""
        return "$" + (n / 1000000).toFixed(0) + "M"
    }

    Connections {
        target: api
        function onFetched(id, data) {
            var d = JSON.parse(data)
            if (id === root._metaReq && !d.error) {
                root.meta = d
                root._metaDone = true
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

    Component.onCompleted: {
        root._metaReq    = "movie_meta_"    + tmdbId
        root._creditsReq = "movie_credits_" + tmdbId
        root._reviewsReq = "movie_reviews_" + tmdbId
        api.fetch(root._metaReq,    "/movies/" + tmdbId + "/meta",    "{}")
        api.fetch(root._creditsReq, "/movies/" + tmdbId + "/credits", "{}")
        api.fetch(root._reviewsReq, "/movies/" + tmdbId + "/reviews", "{}")
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentCol.height + 40
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
            id: contentCol
            width: parent.width
            spacing: 0

            Rectangle {
                width: parent.width; height: 220; color: "#111"
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
                        width: parent.width
                        text: root.title
                        color: "#FFFFFF"; font.pixelSize: 18; font.weight: Font.Bold
                        wrapMode: Text.WordWrap
                    }
                    Row {
                        spacing: 10
                        Text { text: root.year(); color: "#666666"; font.pixelSize: 13 }
                        Text {
                            visible: root.meta && root.meta.runtime > 0
                            text: root.meta ? (root.meta.runtime + " min") : ""
                            color: "#666666"; font.pixelSize: 13
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

            Item { width: parent.width; height: 8 }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 24; height: 50; radius: 14; color: "#8B5CF6"
                Text {
                    anchors.centerIn: parent
                    text: "▶  Watch Now"
                    color: "#FFFFFF"; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                scale: watchMA.pressed ? 0.97 : 1.0
                Behavior on scale { SpringAnimation { spring: 6; damping: 0.4 } }
                Rectangle { anchors.fill: parent; radius: 14; color: "white"; opacity: watchMA.pressed ? 0.08 : 0 }
                MouseArea {
                    id: watchMA; anchors.fill: parent
                    onClicked: {
                        var streams = JSON.parse(api.movieStream(root.tmdbId, root.title, root.year()))
                        if (!streams || streams.error || !streams.length) return
                        var s = streams[0]
                        api.recordHistory(JSON.stringify({
                            media_type: "movie", title: root.title, tmdb_id: root.tmdbId
                        }))
                        root.StackView.view.push(Qt.resolvedUrl("Player.qml"), {
                            streamUrl: s.url, referrer: s.referrer || "",
                            title: root.title, subtitles: s.subtitles || []
                        })
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
                        visible: root.meta && root.meta.tagline.length > 0
                        text: root.meta ? root.meta.tagline : ""
                        color: "#8B5CF6"; font.pixelSize: 13; font.italic: true
                        wrapMode: Text.WordWrap; width: parent.width
                    }
                    Text {
                        text: root.meta ? root.meta.overview : ""
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
                            if (root.meta.spoken_languages && root.meta.spoken_languages.length > 0)
                                rows.push({ label: "Language", value: root.meta.spoken_languages.join(", ") })
                            if (root.meta.runtime > 0)
                                rows.push({ label: "Runtime", value: root.meta.runtime + " minutes" })
                            var bud = formatMoney(root.meta.budget)
                            var rev = formatMoney(root.meta.revenue)
                            if (bud) rows.push({ label: "Budget", value: bud })
                            if (rev) rows.push({ label: "Box Office", value: rev })
                            if (root.meta.production_companies && root.meta.production_companies.length > 0)
                                rows.push({ label: "Studio", value: root.meta.production_companies.join(" · ") })
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

                            // Author row
                            Item {
                                width: parent.width; height: 18
                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: model.author
                                    color: "#DDDDDD"; font.pixelSize: 13; font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    width: parent.width - 120
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
                                width: parent.width
                                text: model.content
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

            Item { width: parent.width; height: 32 }
        }
    }

    ListModel { id: castModel }
    ListModel { id: reviewsModel }
}
