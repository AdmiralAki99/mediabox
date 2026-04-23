import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    color: "#0A0A0A"

    property string mangaId:     ""
    property string mangaTitle:  ""
    property string coverUrl:    ""
    property string status:      ""
    property string description: ""
    property string tagsStr:     ""   // comma-separated

    property string _reqId:         ""
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

    ListModel { id: chaptersModel }

    Connections {
        target: api
        function onFetched(id, data) {
            if (id !== root._reqId) return
            var raw = JSON.parse(data)
            if (raw.error) { chapterStatus.text = "Error loading chapters"; return }
            var chapters = Array.isArray(raw) ? raw : (raw.results || raw)
            chaptersModel.clear()
            chapters.forEach(function(c) {
                chaptersModel.append({
                    ch_id:    c.id             || "",
                    ch_num:   c.chapter_number || "",
                    ch_title: c.title          || "",
                    ch_pages: c.pages          || 0,
                    ch_date:  c.published_at   ? c.published_at.slice(0, 10) : "",
                    volume:   c.volume         || ""
                })
            })
            root._totalChapters = chaptersModel.count
        }
    }

    Component.onCompleted: {
        root._reqId = "manga_ch_" + mangaId
        api.fetch(root._reqId, "/manga/" + mangaId + "/chapters", "{}")
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainCol.implicitHeight
        clip: true
        flickDeceleration: 700; maximumFlickVelocity: 2800

        ScrollBar.vertical: ScrollBar {
            width: 3
            contentItem: Rectangle { radius: 2; color: "#FFF"
                opacity: parent.active ? 0.15 : 0
                Behavior on opacity { NumberAnimation { duration: 500 } } }
            background: Item {}
        }

        Column {
            id: mainCol
            width: parent.width
            spacing: 0

            Item {
                width: parent.width
                height: 300

                // Blurred background cover
                Image {
                    anchors.fill: parent
                    source: root.coverUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#AA000000" }
                        GradientStop { position: 0.55; color: "#CC000000" }
                        GradientStop { position: 1.0; color: "#0A0A0A" }
                    }
                }

                // Back button
                BackButton {
                    anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 12
                    onClicked: root.StackView.view.pop()
                }

                // Cover art + meta side-by-side at bottom
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
                            anchors.fill: parent
                            source: root.coverUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }

                    // Title + badges
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBottom
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: root.mangaTitle
                            color: "#FFF"; font.pixelSize: 17; font.weight: Font.Bold
                            wrapMode: Text.WordWrap; maximumLineCount: 3
                        }

                        // Status + chapter count
                        Row {
                            spacing: 8
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
                            Text {
                                id: chapterStatus
                                anchors.verticalCenter: parent.verticalCenter
                                text: root._totalChapters > 0
                                      ? root._totalChapters + " chapters"
                                      : "Loading…"
                                color: "#888"; font.pixelSize: 11
                            }
                        }

                        // Tags row
                        Flow {
                            Layout.fillWidth: true
                            spacing: 5
                            visible: root.tagsStr !== ""
                            Repeater {
                                model: root.tagsStr !== "" ? root.tagsStr.split(",").slice(0, 5) : []
                                Rectangle {
                                    height: 20; width: tgl.implicitWidth + 12; radius: 10
                                    color: "#1E2A3A"
                                    Text {
                                        id: tgl; anchors.centerIn: parent
                                        text: modelData
                                        color: "#5B8FD4"; font.pixelSize: 10
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                visible: root.description !== ""
                width: parent.width
                height: descCard.height + 16

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

                    // "Read more" tap
                    MouseArea {
                        anchors.fill: parent
                        visible: !descText._expanded
                        onClicked: descText._expanded = true
                    }

                    // Fade on last line when collapsed
                    Rectangle {
                        anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                        height: 28; radius: 12; visible: !descText._expanded
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: "#141414" }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "more"; color: "#555"; font.pixelSize: 11
                        }
                    }
                }
            }

            Item {
                width: parent.width; height: 48
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16
                    Text {
                        text: root._totalChapters > 0
                              ? "Chapters  " + root._totalChapters
                              : (chaptersModel.count === 0 ? "Loading chapters…" : "Chapters")
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

                    // Volume divider — show when volume changes
                    Rectangle {
                        width: parent.width; height: 32
                        color: "#0F0F0F"
                        visible: {
                            if (index === 0) return true
                            var prev = chaptersModel.get(index - 1)
                            return prev.volume !== model.volume
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
                            width: volLabel.implicitWidth + 8; height: volLabel.implicitHeight + 2
                            Text {
                                id: volLabel; anchors.centerIn: parent
                                text: model.volume !== "" ? "Vol. " + model.volume : "Uncollected"
                                color: "#444"; font.pixelSize: 10; font.weight: Font.Medium
                            }
                        }
                    }

                    // Chapter row
                    Rectangle {
                        width: parent.width; height: 58
                        color: chMA.containsMouse ? "#141414" : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Rectangle {
                            anchors.bottom: parent.bottom; height: 1
                            anchors.left: parent.left; anchors.leftMargin: 16
                            anchors.right: parent.right; color: "#111"
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16; anchors.rightMargin: 14
                            spacing: 10

                            // Chapter number badge
                            Rectangle {
                                width: 38; height: 38; radius: 8; color: "#1A1A1A"
                                Layout.alignment: Qt.AlignVCenter
                                Text {
                                    anchors.centerIn: parent
                                    text: model.ch_num !== "" ? model.ch_num : "?"
                                    color: "#8B5CF6"; font.pixelSize: 11; font.weight: Font.Bold
                                }
                            }

                            // Title + meta
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 3

                                Text {
                                    Layout.fillWidth: true
                                    text: model.ch_title !== "" ? model.ch_title : "Chapter " + (model.ch_num || "?")
                                    color: "#DDD"; font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                                RowLayout {
                                    spacing: 10
                                    Text {
                                        visible: model.ch_pages > 0
                                        text: model.ch_pages + " pages"
                                        color: "#555"; font.pixelSize: 11
                                    }
                                    Text {
                                        visible: model.ch_date !== ""
                                        text: model.ch_date
                                        color: "#3A3A3A"; font.pixelSize: 11
                                    }
                                }
                            }

                            // Read button
                            Rectangle {
                                width: 40; height: 40; radius: 10; color: "#181818"
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "▶"; color: "#8B5CF6"; font.pixelSize: 13 }
                                scale: readMA.containsPress ? 0.9 : 1.0
                                Behavior on scale { SpringAnimation { spring: 7; damping: 0.5 } }
                                MouseArea {
                                    id: readMA; anchors.fill: parent
                                    onClicked: {
                                        api.recordHistory(JSON.stringify({
                                            media_type: "manga",
                                            title: root.mangaTitle,
                                            manga_id: root.mangaId,
                                            chapter_id: model.ch_id
                                        }))
                                        root.StackView.view.push(Qt.resolvedUrl("MangaReader.qml"), {
                                            chapterId:    model.ch_id,
                                            chapterTitle: model.ch_num !== "" ? "Ch. " + model.ch_num + (model.ch_title !== "" ? " – " + model.ch_title : "") : model.ch_title,
                                            mangaTitle:   root.mangaTitle
                                        })
                                    }
                                }
                            }
                        }

                        HoverHandler { id: chMA }
                    }
                }
            }

            // Bottom padding
            Item { width: parent.width; height: 40 }
        }
    }
}
