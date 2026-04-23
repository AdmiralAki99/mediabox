import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    color: "#0A0A0A"

    property string _reqId:   ""
    property bool   _isSearch: false

    // One reqId per genre strip
    property string _superReqId:   ""
    property string _actionReqId:  ""
    property string _horrorReqId:  ""
    property string _fantasyReqId: ""
    property string _scifiReqId:   ""
    property string _crimeReqId:   ""
    property string _comedyReqId:  ""

    function pushDetail(model) {
        root.StackView.view.push(Qt.resolvedUrl("ComicDetail.qml"), {
            comicSlug:   model.slug        || model.id  || "",
            comicTitle:  model.title       || "",
            coverUrl:    model.cover_url   || "",
            description: model.description || "",
            genres:      model.genres      || [],
            status:      model.status      || "",
            comicYear:   model.year        || 0,
            country:     model.country     || ""
        })
    }

    function fillStrip(model, data) {
        model.clear()
        var list = (data.results || data)
        if (!Array.isArray(list)) return
        list.forEach(function(item) {
            model.append({
                id:          item.id          || "",
                slug:        item.slug        || item.id || "",
                title:       item.title       || "",
                cover_url:   item.cover_url   || "",
                status:      item.status      || "",
                description: item.description || "",
                genres_json: JSON.stringify(item.genres || []),
                year:        item.year        || 0,
                country:     item.country     || ""
            })
        })
    }

    // Re-hydrate genres array from stored JSON string
    function stripGenres(item) { try { return JSON.parse(item.genres_json) } catch(e) { return [] } }

    function loadStrip(prop, genre) {
        root[prop] = "comic_" + genre + "_" + Date.now()
        api.fetch(root[prop], "/comics/genre/" + genre, "{}")
    }

    function loadAll() {
        loadStrip("_superReqId",   "Superhero")
        loadStrip("_actionReqId",  "Action")
        loadStrip("_horrorReqId",  "Horror")
        loadStrip("_fantasyReqId", "Fantasy")
        loadStrip("_scifiReqId",   "Sci-fi")
        loadStrip("_crimeReqId",   "Crime")
        loadStrip("_comedyReqId",  "Comedy")
    }

    function doSearch(q) {
        if (!q.trim()) { root._isSearch = false; resultsModel.clear(); return }
        root._isSearch = true
        root._reqId = "comics_s_" + Date.now()
        statusText.text = "Searching…"
        api.fetch(root._reqId, "/comics/search", JSON.stringify({ q: q }))
    }

    Connections {
        target: api
        function onFetched(id, data) {
            var d = JSON.parse(data)
            if (d.error) return

            if (id === root._reqId) {
                resultsModel.clear()
                var list = d.results || []
                list.forEach(function(item) {
                    resultsModel.append({
                        id:          item.id          || "",
                        slug:        item.slug        || item.id || "",
                        title:       item.title       || "",
                        cover_url:   item.cover_url   || "",
                        status:      item.status      || "",
                        description: item.description || "",
                        genres_json: JSON.stringify(item.genres || []),
                        year:        item.year        || 0,
                        country:     item.country     || ""
                    })
                })
                statusText.text = list.length + " results"
                return
            }
            if (id === root._superReqId)   { fillStrip(superModel,   d); return }
            if (id === root._actionReqId)  { fillStrip(actionModel,  d); return }
            if (id === root._horrorReqId)  { fillStrip(horrorModel,  d); return }
            if (id === root._fantasyReqId) { fillStrip(fantasyModel, d); return }
            if (id === root._scifiReqId)   { fillStrip(scifiModel,   d); return }
            if (id === root._crimeReqId)   { fillStrip(crimeModel,   d); return }
            if (id === root._comedyReqId)  { fillStrip(comedyModel,  d); return }
        }
    }

    Component.onCompleted: loadAll()

    Rectangle {
        id: searchBar
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        anchors.topMargin: 10; anchors.leftMargin: 10; anchors.rightMargin: 10
        height: 42; radius: 12; color: "#141414"
        border.color: sf.activeFocus ? "#4CAF50" : "#222222"; border.width: 1
        Behavior on border.color { ColorAnimation { duration: 150 } }

        Row {
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
            spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter; text: "🔍"; font.pixelSize: 15 }
            TextField {
                id: sf
                width: parent.width - 40 - (statusText.visible ? statusText.implicitWidth + 8 : 0) - (clearBtn.visible ? 28 : 0)
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: "Search comics…"
                color: "#FFF"; font.pixelSize: 13; background: null; placeholderTextColor: "#444"
                onTextChanged: searchTimer.restart()
                Keys.onReturnPressed: { searchTimer.stop(); doSearch(text) }
            }
            Text {
                id: statusText
                visible: root._isSearch && text.length > 0
                anchors.verticalCenter: parent.verticalCenter
                color: "#555"; font.pixelSize: 11
            }
            Text {
                id: clearBtn; visible: sf.text.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: "✕"; color: "#555"; font.pixelSize: 13
                MouseArea {
                    anchors.fill: parent
                    onClicked: { sf.text = ""; root._isSearch = false; resultsModel.clear(); statusText.text = "" }
                }
            }
        }
    }

    Timer { id: searchTimer; interval: 400; onTriggered: doSearch(sf.text) }

    GridView {
        id: searchGrid
        anchors.top: searchBar.bottom; anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right
        anchors.topMargin: 8; anchors.leftMargin: 4; anchors.rightMargin: 4
        visible: root._isSearch
        cellWidth: Math.floor(width / 4); cellHeight: 210
        clip: true; model: resultsModel
        flickDeceleration: 700; maximumFlickVelocity: 2800
        ScrollBar.vertical: ScrollBar { width: 3
            contentItem: Rectangle { radius: 2; color: "#FFF"
                opacity: parent.active ? 0.15 : 0
                Behavior on opacity { NumberAnimation { duration: 500 } } }
            background: Item {} }
        delegate: Item {
            width: searchGrid.cellWidth; height: 210
            PosterCard {
                anchors.centerIn: parent; width: searchGrid.cellWidth - 10; height: 195
                posterUrl: model.cover_url; title: model.title
                onTapped: root.pushDetail(model)
            }
        }
    }

    Flickable {
        anchors.top: searchBar.bottom; anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right
        anchors.topMargin: 8
        visible: !root._isSearch
        contentWidth: width
        contentHeight: discoverCol.implicitHeight + 16
        clip: true
        flickDeceleration: 700; maximumFlickVelocity: 2800
        ScrollBar.vertical: ScrollBar { width: 3
            contentItem: Rectangle { radius: 2; color: "#FFF"
                opacity: parent.active ? 0.15 : 0
                Behavior on opacity { NumberAnimation { duration: 500 } } }
            background: Item {} }

        Column {
            id: discoverCol
            width: parent.width
            spacing: 10
            topPadding: 4; bottomPadding: 16

            Repeater {
                model: [
                    { label: "Superhero",  listModel: superModel,   color: "#8B5CF6" },
                    { label: "Action",     listModel: actionModel,  color: "#8B5CF6" },
                    { label: "Horror",     listModel: horrorModel,  color: "#607D8B" },
                    { label: "Fantasy",    listModel: fantasyModel, color: "#8B5CF6" },
                    { label: "Sci-Fi",     listModel: scifiModel,   color: "#8B5CF6" },
                    { label: "Crime",      listModel: crimeModel,   color: "#8B5CF6" },
                    { label: "Comedy",     listModel: comedyModel,  color: "#4CAF50" },
                ]

                Rectangle {
                    width: discoverCol.width; height: 200
                    color: "#141414"; radius: 20
                    border.color: "#222222"; border.width: 1

                    // Strip header
                    Item {
                        id: stripHdr
                        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                        anchors.topMargin: 14; anchors.leftMargin: 16; anchors.rightMargin: 16
                        height: 18

                        Row { spacing: 8
                            Rectangle {
                                width: 3; height: 14; radius: 2; color: modelData.color
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: "#FFF"; font.pixelSize: 13; font.weight: Font.Medium
                            }
                        }
                        Text {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            visible: modelData.listModel.count === 0
                            text: "Loading…"; color: "#333"; font.pixelSize: 11
                        }
                    }

                    // Horizontal cover strip
                    ListView {
                        anchors.top: stripHdr.bottom; anchors.topMargin: 10
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        orientation: ListView.Horizontal
                        spacing: 8; clip: true
                        model: modelData.listModel
                        flickDeceleration: 600; maximumFlickVelocity: 2400

                        delegate: Item {
                            width: 76; height: parent ? parent.height : 100

                            Rectangle {
                                id: coverRect
                                width: 76; height: 108; radius: 10; color: "#1C1C1C"; clip: true
                                Image {
                                    anchors.fill: parent; source: model.cover_url
                                    fillMode: Image.PreserveAspectCrop; smooth: true; asynchronous: true
                                }
                                Rectangle {
                                    visible: model.status === "ongoing"
                                    width: 6; height: 6; radius: 3; color: "#4CAF50"
                                    anchors.top: parent.top; anchors.right: parent.right
                                    anchors.topMargin: 5; anchors.rightMargin: 5
                                }
                                Rectangle {
                                    anchors.fill: parent; radius: 10; color: "white"
                                    opacity: coverMA.pressed ? 0.1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 80 } }
                                }
                            }
                            Text {
                                anchors.top: coverRect.bottom; anchors.topMargin: 4
                                anchors.left: parent.left; anchors.right: parent.right
                                text: model.title; color: "#777"; font.pixelSize: 9
                                elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                                maximumLineCount: 2; wrapMode: Text.WordWrap
                            }

                            scale: coverMA.pressed ? 0.93 : 1.0
                            Behavior on scale { SpringAnimation { spring: 6; damping: 0.42 } }

                            MouseArea {
                                id: coverMA; anchors.fill: parent
                                onClicked: root.pushDetail(model)
                            }
                        }
                    }
                }
            }
        }
    }

    ListModel { id: resultsModel }
    ListModel { id: superModel }
    ListModel { id: actionModel }
    ListModel { id: horrorModel }
    ListModel { id: fantasyModel }
    ListModel { id: scifiModel }
    ListModel { id: crimeModel }
    ListModel { id: comedyModel }
}
