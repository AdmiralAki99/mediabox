import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    color: "#0A0A0A"

    property string comicSlug:   ""
    property string comicTitle:  ""
    property string coverUrl:    ""
    property string description: ""
    property var    genres:      []
    property string status:      ""
    property int    comicYear:   0
    property string country:     ""

    property string _chapReqId:     ""
    property int    _totalChapters: 0

    function statusColor(s) {
        if (s === "ongoing")   return "#4CAF50"
        if (s === "completed") return "#64B5F6"
        if (s === "hiatus")    return "#FFA726"
        return "#888"
    }
    function statusBg(s) {
        if (s === "ongoing")   return "#1B4A2A"
        if (s === "completed") return "#1A3A6E"
        if (s === "hiatus")    return "#3A2A1A"
        return "#1E1E1E"
    }
    function originLabel(c) {
        var map = { "jp": "Japan", "kr": "Korea", "cn": "China", "us": "USA" }
        return map[c] || c.toUpperCase()
    }

    ListModel { id: chaptersModel }

    Connections {
        target: api
        function onFetched(id, data) {
            if (id !== root._chapReqId) return
            var d = JSON.parse(data)
            if (d.error) { chapterStatus.text = "Error"; return }
            var list = Array.isArray(d) ? d : (d.results || [])
            chaptersModel.clear()
            list.forEach(function(c) {
                chaptersModel.append({
                    ch_id:    c.id             || "",
                    ch_num:   c.chapter_number || "",
                    ch_title: c.title          || "",
                    ch_date:  c.published_at   ? c.published_at.slice(0, 10) : "",
                    volume:   c.volume         || ""
                })
            })
            root._totalChapters = chaptersModel.count
        }
    }

    Component.onCompleted: {
        root._chapReqId = "comic_ch_" + comicSlug
        api.fetch(root._chapReqId, "/comics/" + comicSlug + "/chapters", "{}")
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainCol.implicitHeight
        clip: true
        flickDeceleration: 700; maximumFlickVelocity: 2800
        ScrollBar.vertical: ScrollBar { width: 3
            contentItem: Rectangle { radius: 2; color: "#FFF"
                opacity: parent.active ? 0.15 : 0
                Behavior on opacity { NumberAnimation { duration: 500 } } }
            background: Item {} }

        Column {
            id: mainCol
            width: parent.width
            spacing: 0

            Item {
                width: parent.width; height: 300

                Image {
                    anchors.fill: parent; source: root.coverUrl
                    fillMode: Image.PreserveAspectCrop; asynchronous: true
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#AA000000" }
                        GradientStop { position: 0.55; color: "#CC000000" }
                        GradientStop { position: 1.0; color: "#0A0A0A" }
                    }
                }

                BackButton {
                    anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 12
                    onClicked: root.StackView.view.pop()
                }

                RowLayout {
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 20
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 16; anchors.rightMargin: 16
                    spacing: 14

                    // Cover thumbnail
                    Rectangle {
                        width: 110; height: 156; radius: 8; color: "#111"; clip: true
                        Layout.alignment: Qt.AlignBottom
                        Image {
                            anchors.fill: parent; source: root.coverUrl
                            fillMode: Image.PreserveAspectCrop; asynchronous: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true; Layout.alignment: Qt.AlignBottom; spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: root.comicTitle
                            color: "#FFF"; font.pixelSize: 17; font.weight: Font.Bold
                            wrapMode: Text.WordWrap; maximumLineCount: 3
                        }

                        // Status + year + country badges
                        Row {
                            spacing: 6
                            Rectangle {
                                visible: root.status !== ""
                                height: 22; width: stLabel.implicitWidth + 14; radius: 11
                                color: root.statusBg(root.status)
                                Text {
                                    id: stLabel; anchors.centerIn: parent
                                    text: root.status.charAt(0).toUpperCase() + root.status.slice(1)
                                    color: root.statusColor(root.status)
                                    font.pixelSize: 10; font.weight: Font.Medium
                                }
                            }
                            Rectangle {
                                visible: root.country !== ""
                                height: 22; width: ctLabel.implicitWidth + 14; radius: 11
                                color: "#1C2A1C"
                                Text {
                                    id: ctLabel; anchors.centerIn: parent
                                    text: root.originLabel(root.country)
                                    color: "#6DBF6D"; font.pixelSize: 10
                                }
                            }
                            Text {
                                visible: root.comicYear > 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.comicYear; color: "#888"; font.pixelSize: 11
                            }
                            Text {
                                id: chapterStatus
                                anchors.verticalCenter: parent.verticalCenter
                                text: root._totalChapters > 0
                                      ? root._totalChapters + " issues"
                                      : "Loading…"
                                color: "#555"; font.pixelSize: 11
                            }
                        }

                        // Genre tags
                        Flow {
                            Layout.fillWidth: true; spacing: 5
                            visible: root.genres && root.genres.length > 0
                            Repeater {
                                model: root.genres ? root.genres.slice(0, 5) : []
                                Rectangle {
                                    height: 20; width: genreLabel.implicitWidth + 12; radius: 10
                                    color: "#1E2A1E"
                                    Text {
                                        id: genreLabel; anchors.centerIn: parent
                                        text: modelData; color: "#4CAF50"; font.pixelSize: 10
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                visible: root.description !== ""
                width: parent.width; height: descCard.height + 16

                Rectangle {
                    id: descCard
                    x: 16; width: parent.width - 32
                    anchors.top: parent.top; anchors.topMargin: 8
                    color: "#141414"; radius: 12
                    height: descText.implicitHeight + 24

                    Text {
                        id: descText
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        text: root.description
                        color: "#999"; font.pixelSize: 12; lineHeight: 1.4
                        wrapMode: Text.WordWrap
                        maximumLineCount: _expanded ? 999 : 4
                        elide: _expanded ? Text.ElideNone : Text.ElideRight
                        property bool _expanded: false
                    }
                    MouseArea {
                        anchors.fill: parent; visible: !descText._expanded
                        onClicked: descText._expanded = true
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                        height: 28; radius: 12; visible: !descText._expanded
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: "#141414" }
                        }
                        Text { anchors.centerIn: parent; text: "more"; color: "#555"; font.pixelSize: 11 }
                    }
                }
            }

            Item {
                width: parent.width; height: 48
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16
                    Text {
                        text: root._totalChapters > 0
                              ? "Issues  " + root._totalChapters
                              : (chaptersModel.count === 0 ? "Loading issues…" : "Issues")
                        color: "#FFF"; font.pixelSize: 14; font.weight: Font.SemiBold
                    }
                    Item { Layout.fillWidth: true }
                }
                Rectangle { anchors.bottom: parent.bottom; height: 1; width: parent.width; color: "#1A1A1A" }
            }

            Repeater {
                model: chaptersModel

                Column {
                    width: mainCol.width

                    // Volume divider
                    Rectangle {
                        width: parent.width; height: 30; color: "#0F0F0F"
                        visible: {
                            if (index === 0) return true
                            return chaptersModel.get(index - 1).volume !== model.volume
                        }
                        Rectangle {
                            anchors.left: parent.left; anchors.leftMargin: 16
                            anchors.right: parent.right; anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            height: 1; color: "#222"
                        }
                        Rectangle {
                            anchors.left: parent.left; anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#0F0F0F"
                            width: volLbl.implicitWidth + 8; height: volLbl.implicitHeight + 2
                            Text {
                                id: volLbl; anchors.centerIn: parent
                                text: model.volume !== "" ? "Vol. " + model.volume : "Uncollected"
                                color: "#444"; font.pixelSize: 10; font.weight: Font.Medium
                            }
                        }
                    }

                    // Issue row
                    Rectangle {
                        width: parent.width; height: 58; color: "transparent"
                        Rectangle {
                            anchors.bottom: parent.bottom; height: 1
                            anchors.left: parent.left; anchors.leftMargin: 16
                            anchors.right: parent.right; color: "#111"
                        }

                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 14; spacing: 10

                            // Issue number badge
                            Rectangle {
                                width: 38; height: 38; radius: 8; color: "#1A1A1A"
                                Layout.alignment: Qt.AlignVCenter
                                Text {
                                    anchors.centerIn: parent
                                    text: model.ch_num !== "" ? model.ch_num : "?"
                                    color: "#4CAF50"; font.pixelSize: 11; font.weight: Font.Bold
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 3
                                Text {
                                    Layout.fillWidth: true
                                    text: model.ch_title !== "" ? model.ch_title : "Issue " + (model.ch_num || "?")
                                    color: "#DDD"; font.pixelSize: 13; elide: Text.ElideRight
                                }
                                Text {
                                    visible: model.ch_date !== ""
                                    text: model.ch_date; color: "#3A3A3A"; font.pixelSize: 11
                                }
                            }

                            // Read button
                            Rectangle {
                                width: 40; height: 40; radius: 10; color: "#181818"
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "▶"; color: "#4CAF50"; font.pixelSize: 13 }
                                scale: readMA.containsPress ? 0.9 : 1.0
                                Behavior on scale { SpringAnimation { spring: 7; damping: 0.5 } }
                                MouseArea {
                                    id: readMA; anchors.fill: parent
                                    onClicked: {
                                        api.recordHistory(JSON.stringify({
                                            media_type: "comic", title: root.comicTitle,
                                            manga_id: root.comicSlug, chapter_id: model.ch_id
                                        }))
                                        root.StackView.view.push(Qt.resolvedUrl("ComicReader.qml"), {
                                            chapterId:    model.ch_id,
                                            chapterTitle: model.ch_num !== "" ? "Issue " + model.ch_num + (model.ch_title !== "" ? " – " + model.ch_title : "") : model.ch_title,
                                            comicTitle:   root.comicTitle
                                        })
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item { width: parent.width; height: 40 }
        }
    }
}
