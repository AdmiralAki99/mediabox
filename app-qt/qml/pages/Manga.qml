import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    color: "#0A0A0A"

    property string _reqId:      ""
    property string _updReqId:   ""
    property bool   _isSearch:   false
    property bool   _isUpdates:  false

    // One reqId per category strip
    property string _latestReqId:    ""
    property string _popularReqId:   ""
    property string _topRatedReqId:  ""
    property string _actionReqId:    ""
    property string _romanceReqId:   ""
    property string _fantasyReqId:   ""
    property string _isekaiReqId:    ""
    property string _horrorReqId:    ""

    function coverUrl(u) { return u || "" }

    function timeAgo(isoStr) {
        var diff = (Date.now() - new Date(isoStr).getTime()) / 1000
        if (diff < 3600)   return Math.floor(diff / 60)   + "m ago"
        if (diff < 86400)  return Math.floor(diff / 3600) + "h ago"
        if (diff < 604800) return Math.floor(diff / 86400) + "d ago"
        return Math.floor(diff / 604800) + "w ago"
    }

    function loadUpdates() {
        root._isUpdates = true
        root._isSearch  = false
        sf.text = ""
        if (updatesModel.count > 0) return   // already loaded, use cache
        root._updReqId = "manga_upd_" + Date.now()
        api.fetch(root._updReqId, "/manga/updates", "{}")
    }

    function showBrowse() {
        root._isUpdates = false
        root._isSearch  = false
        sf.text = ""
    }

    function loadStrip(reqIdProp, path, params) {
        root[reqIdProp] = "manga_" + reqIdProp + "_" + Date.now()
        api.fetch(root[reqIdProp], path, params || "{}")
    }

    function loadAll() {
        loadStrip("_latestReqId",   "/manga/latest",        "{}")
        loadStrip("_popularReqId",  "/manga/popular",       "{}")
        loadStrip("_topRatedReqId", "/manga/top-rated",     "{}")
        loadStrip("_actionReqId",   "/manga/genre/action",  "{}")
        loadStrip("_romanceReqId",  "/manga/genre/romance", "{}")
        loadStrip("_fantasyReqId",  "/manga/genre/fantasy", "{}")
        loadStrip("_isekaiReqId",   "/manga/genre/isekai",  "{}")
        loadStrip("_horrorReqId",   "/manga/genre/horror",  "{}")
    }

    function doSearch(q) {
        if (!q.trim()) {
            root._isSearch = false
            resultsModel.clear()
            return
        }
        root._isSearch = true
        root._reqId = "manga_s_" + Date.now()
        statusText.text = "Searching…"
        api.fetch(root._reqId, "/manga/search", JSON.stringify({ q: q }))
    }

    function fillModel(model, data) {
        model.clear()
        var list = data.results || data
        if (!Array.isArray(list)) return
        list.forEach(function(item) {
            model.append({
                id:          item.id          || "",
                title:       item.title       || "",
                cover_url:   item.cover_url   || "",
                status:      item.status      || "",
                description: item.description || "",
                tags_str:    (item.tags && item.tags.length > 0) ? item.tags.join(",") : ""
            })
        })
    }

    Connections {
        target: api
        function onFetched(id, data) {
            var d = JSON.parse(data)
            if (d.error) return

            if (id === root._reqId) {
                fillModel(resultsModel, d)
                statusText.text = (d.results || []).length + " results"
                return
            }

            if (id === root._updReqId) {
                updatesModel.clear()
                var list = Array.isArray(d) ? d : []
                list.forEach(function(e) {
                    updatesModel.append({
                        chapter_id:     e.chapter_id     || "",
                        chapter_number: e.chapter_number || "",
                        chapter_title:  e.chapter_title  || "",
                        published_at:   e.published_at   || "",
                        manga_id:       e.manga_id       || "",
                        manga_title:    e.manga_title    || "",
                        cover_url:      e.cover_url      || ""
                    })
                })
                return
            }

            if (id === root._latestReqId)   { fillModel(latestModel,   d); return }
            if (id === root._popularReqId)  { fillModel(popularModel,  d); return }
            if (id === root._topRatedReqId) { fillModel(topRatedModel, d); return }
            if (id === root._actionReqId)   { fillModel(actionModel,   d); return }
            if (id === root._romanceReqId)  { fillModel(romanceModel,  d); return }
            if (id === root._fantasyReqId)  { fillModel(fantasyModel,  d); return }
            if (id === root._isekaiReqId)   { fillModel(isekaiModel,   d); return }
            if (id === root._horrorReqId)   { fillModel(horrorModel,   d); return }
        }
    }

    Component.onCompleted: loadAll()

    Item {
        id: headerRow
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        anchors.topMargin: 10; anchors.leftMargin: 10; anchors.rightMargin: 10
        height: 32

        Text {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: "Manga"; color: "#FFF"; font.pixelSize: 20; font.weight: Font.Bold
        }

        // Browse / Updates tab pills
        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Repeater {
                model: ["Browse", "Updates"]
                Rectangle {
                    height: 26; width: hl.implicitWidth + 16; radius: 13
                    color: (index === 0 ? !root._isUpdates : root._isUpdates) ? "#252525" : "transparent"
                    border.color: (index === 0 ? !root._isUpdates : root._isUpdates) ? "#3A3A3A" : "transparent"
                    border.width: 1
                    Text {
                        id: hl; anchors.centerIn: parent; text: modelData
                        color: (index === 0 ? !root._isUpdates : root._isUpdates) ? "#FFF" : "#444"
                        font.pixelSize: 11
                        font.weight: (index === 0 ? !root._isUpdates : root._isUpdates) ? Font.Medium : Font.Normal
                    }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: index === 0 ? showBrowse() : loadUpdates()
                    }
                }
            }
        }
    }

    Rectangle {
        id: searchBar
        anchors.top: headerRow.bottom; anchors.left: parent.left; anchors.right: parent.right
        anchors.topMargin: 8; anchors.leftMargin: 10; anchors.rightMargin: 10
        height: root._isUpdates ? 0 : 42
        visible: !root._isUpdates
        radius: 12; color: "#141414"
        border.color: sf.activeFocus ? "#8B5CF6" : "#222222"; border.width: 1
        Behavior on border.color { ColorAnimation { duration: 150 } }

        Row {
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "🔍"; font.pixelSize: 15
            }
            TextField {
                id: sf
                width: parent.width - 40 - (statusText.visible ? statusText.width + 8 : 0) - (clearBtn.visible ? 28 : 0)
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: "Search manga…"
                color: "#FFFFFF"; font.pixelSize: 13; background: null
                placeholderTextColor: "#444444"
                onTextChanged: searchTimer.restart()
                Keys.onReturnPressed: { searchTimer.stop(); doSearch(text) }
            }
            Text {
                id: statusText
                visible: root._isSearch && text.length > 0
                anchors.verticalCenter: parent.verticalCenter
                color: "#555555"; font.pixelSize: 11
            }
            Text {
                id: clearBtn
                visible: sf.text.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: "✕"; color: "#555555"; font.pixelSize: 13
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        sf.text = ""
                        root._isSearch = false
                        resultsModel.clear()
                        statusText.text = ""
                    }
                }
            }
        }
    }

    Timer { id: searchTimer; interval: 400; onTriggered: doSearch(sf.text) }

    ListView {
        id: updatesList
        anchors.top: headerRow.bottom; anchors.topMargin: 10
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: 10; anchors.rightMargin: 10
        visible: root._isUpdates
        spacing: 6; clip: true
        model: updatesModel
        flickDeceleration: 700; maximumFlickVelocity: 2800

        ScrollBar.vertical: ScrollBar { width: 3
            contentItem: Rectangle { radius: 2; color: "#FFF"
                opacity: parent.active ? 0.15 : 0
                Behavior on opacity { NumberAnimation { duration: 500 } } }
            background: Item {} }

        // Loading / empty state
        Text {
            anchors.centerIn: parent
            visible: updatesModel.count === 0
            text: "Loading updates…"; color: "#444"; font.pixelSize: 13
        }

        delegate: Rectangle {
            width: updatesList.width; height: 76
            radius: 12; color: "#141414"
            border.color: "#1E1E1E"; border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10; anchors.rightMargin: 14
                spacing: 12

                // Cover
                Rectangle {
                    width: 44; height: 60; radius: 6; color: "#0D0D0D"; clip: true
                    Image {
                        anchors.fill: parent; asynchronous: true
                        fillMode: Image.PreserveAspectCrop; smooth: true
                        source: model.cover_url || ""
                    }
                }

                // Title + chapter info
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 4

                    Text {
                        Layout.fillWidth: true
                        text: model.manga_title
                        color: "#EEE"; font.pixelSize: 13; font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        spacing: 6
                        Text {
                            text: model.chapter_number !== ""
                                  ? "Ch. " + model.chapter_number
                                  : "Oneshot"
                            color: "#8B5CF6"; font.pixelSize: 11; font.weight: Font.Medium
                        }
                        Text {
                            visible: model.chapter_title !== ""
                            text: model.chapter_title
                            color: "#666"; font.pixelSize: 11
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }

                // Time ago
                Text {
                    text: root.timeAgo(model.published_at)
                    color: "#555"; font.pixelSize: 10
                    horizontalAlignment: Text.AlignRight
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.StackView.view.push(Qt.resolvedUrl("MangaDetail.qml"), {
                    mangaId: model.manga_id,
                    mangaTitle: model.manga_title,
                    coverUrl: model.cover_url
                })
            }
        }
    }

    GridView {
        id: searchGrid
        anchors.top: searchBar.bottom; anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right
        anchors.topMargin: 8; anchors.leftMargin: 4; anchors.rightMargin: 4
        visible: root._isSearch && !root._isUpdates
        cellWidth: Math.floor(width / 4); cellHeight: 210
        clip: true; model: resultsModel
        flickDeceleration: 700; maximumFlickVelocity: 2800

        ScrollBar.vertical: ScrollBar {
            width: 3
            contentItem: Rectangle {
                radius: 2; color: "#FFFFFF"
                opacity: parent.active ? 0.15 : 0
                Behavior on opacity { NumberAnimation { duration: 500 } }
            }
            background: Item {}
        }

        delegate: Item {
            width: searchGrid.cellWidth; height: 210
            PosterCard {
                anchors.centerIn: parent
                width: searchGrid.cellWidth - 10; height: 195
                posterUrl: model.cover_url; title: model.title; rating: 0
                onTapped: root.StackView.view.push(Qt.resolvedUrl("MangaDetail.qml"), {
                    mangaId: model.id, mangaTitle: model.title, coverUrl: model.cover_url,
                    status: model.status, description: model.description,
                    tagsStr: model.tags_str
                })
            }
        }
    }

    Flickable {
        anchors.top: searchBar.bottom; anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right
        anchors.topMargin: 8
        visible: !root._isSearch && !root._isUpdates
        contentWidth: width
        contentHeight: discoverCol.height + 16
        clip: true
        flickDeceleration: 700; maximumFlickVelocity: 2800

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
            id: discoverCol
            width: parent.width
            spacing: 10
            topPadding: 4; bottomPadding: 16

            // Render each category strip
            Repeater {
                model: [
                    { label: "Latest Updates",  model: latestModel,   color: "#8B5CF6" },
                    { label: "Most Popular",     model: popularModel,  color: "#8B5CF6" },
                    { label: "Top Rated",        model: topRatedModel, color: "#FFD700" },
                    { label: "Action",           model: actionModel,   color: "#8B5CF6" },
                    { label: "Romance",          model: romanceModel,  color: "#8B5CF6" },
                    { label: "Fantasy",          model: fantasyModel,  color: "#8B5CF6" },
                    { label: "Isekai",           model: isekaiModel,   color: "#8B5CF6" },
                    { label: "Horror",           model: horrorModel,   color: "#607D8B" },
                ]

                Rectangle {
                    width: discoverCol.width; height: 200
                    color: "#141414"; radius: 20
                    border.color: "#222222"; border.width: 1

                    // Strip header
                    Item {
                        id: stripHeader
                        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                        anchors.topMargin: 14; anchors.leftMargin: 16; anchors.rightMargin: 16
                        height: 18

                        Row { spacing: 8
                            Rectangle {
                                width: 3; height: 14; radius: 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelData.color
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: "#FFFFFF"; font.pixelSize: 13; font.weight: Font.Medium
                            }
                        }

                        Text {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            visible: modelData.model.count === 0
                            text: "Loading…"; color: "#333333"; font.pixelSize: 11
                        }
                    }

                    // Horizontal cover strip
                    ListView {
                        anchors.top: stripHeader.bottom; anchors.topMargin: 10
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        orientation: ListView.Horizontal
                        spacing: 8; clip: true
                        model: modelData.model
                        flickDeceleration: 600; maximumFlickVelocity: 2400

                        delegate: Item {
                            width: 76; height: parent ? parent.height : 100

                            Rectangle {
                                id: coverRect
                                width: 76; height: 108; radius: 10; color: "#1C1C1C"; clip: true
                                Image {
                                    anchors.fill: parent
                                    source: model.cover_url
                                    fillMode: Image.PreserveAspectCrop
                                    smooth: true; asynchronous: true
                                }
                                // Status dot
                                Rectangle {
                                    visible: model.status === "ongoing"
                                    width: 6; height: 6; radius: 3; color: "#4CAF50"
                                    anchors.top: parent.top; anchors.right: parent.right
                                    anchors.topMargin: 5; anchors.rightMargin: 5
                                }
                                // Press flash
                                Rectangle {
                                    anchors.fill: parent; radius: 10; color: "white"
                                    opacity: coverMA.pressed ? 0.1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 80 } }
                                }
                            }
                            Text {
                                anchors.top: coverRect.bottom; anchors.topMargin: 4
                                anchors.left: parent.left; anchors.right: parent.right
                                text: model.title; color: "#777777"; font.pixelSize: 9
                                elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                                maximumLineCount: 2; wrapMode: Text.WordWrap
                            }

                            scale: coverMA.pressed ? 0.93 : 1.0
                            Behavior on scale { SpringAnimation { spring: 6; damping: 0.42 } }

                            MouseArea {
                                id: coverMA; anchors.fill: parent
                                onClicked: root.StackView.view.push(Qt.resolvedUrl("MangaDetail.qml"), {
                                    mangaId: model.id, mangaTitle: model.title, coverUrl: model.cover_url
                                })
                            }
                        }
                    }
                }
            }
        }
    }

    ListModel { id: resultsModel }
    ListModel { id: updatesModel }
    ListModel { id: latestModel }
    ListModel { id: popularModel }
    ListModel { id: topRatedModel }
    ListModel { id: actionModel }
    ListModel { id: romanceModel }
    ListModel { id: fantasyModel }
    ListModel { id: isekaiModel }
    ListModel { id: horrorModel }
}
