import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root; color: "#0A0A0A"

    property string _reqId: ""
    property string _catReqId: ""
    property bool   _isSearch: false
    property var    _categories: []

    Connections {
        target: api
        function onFetched(id, data) {
            var raw = JSON.parse(data)

            if (id === root._catReqId) {
                if (!raw.error && Array.isArray(raw)) {
                    root._categories = raw
                    if (raw.length > 0) loadCategory(raw[0].id)
                }
                return
            }

            if (id !== root._reqId) return
            if (raw.error) { statusText.text = "Error"; return }

            var list = raw.papers || []
            papersModel.clear()
            list.forEach(function(p) {
                var authors = Array.isArray(p.authors) ? p.authors : []
                papersModel.append({
                    paper_id:         p.id || "",
                    title:            p.title || "",
                    authors_str:      authors.slice(0, 2).join(", ") + (authors.length > 2 ? " et al." : ""),
                    abstract:         p.abstract || "",
                    published:        p.published ? p.published.substring(0, 10) : "",
                    primary_category: p.primary_category || ""
                })
            })
            statusText.text = list.length + " papers"
        }
    }

    function loadCategory(catId) {
        root._isSearch = false
        root._reqId = "arxiv_cat_" + Date.now()
        statusText.text = "Loading…"
        api.fetch(root._reqId, "/arxiv/latest", JSON.stringify({ category: catId, limit: 20 }))
    }

    function doSearch(q) {
        if (!q.trim()) return
        root._isSearch = true
        root._reqId = "arxiv_s_" + Date.now()
        statusText.text = "Searching…"
        api.fetch(root._reqId, "/arxiv/search", JSON.stringify({ q: q, limit: 20 }))
    }

    Component.onCompleted: {
        root._catReqId = "arxiv_cats_" + Date.now()
        api.fetch(root._catReqId, "/arxiv/categories", "{}")
    }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Text { text: "Papers"; color: "#FFF"; font.pixelSize: 22; font.weight: Font.Bold }
            Item { Layout.fillWidth: true }
            Text { id: statusText; color: "#666"; font.pixelSize: 12 }
        }

        ComboBox {
            id: catPicker
            Layout.fillWidth: true
            visible: root._categories.length > 0 && !root._isSearch
            model: root._categories.map(function(c) { return c.label })
            onActivated: loadCategory(root._categories[index].id)

            background: Rectangle {
                radius: 8; color: "#1E1E1E"
                border.color: catPicker.activeFocus ? "#8B5CF6" : "#333"; border.width: 1
            }
            contentItem: Text {
                leftPadding: 10; rightPadding: 30; text: catPicker.displayText
                color: "#FFF"; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            indicator: Text {
                x: catPicker.width - width - 10; y: (catPicker.height - height) / 2
                text: "▾"; color: "#888"; font.pixelSize: 12
            }
            delegate: ItemDelegate {
                width: catPicker.popup.width
                contentItem: Text {
                    text: modelData; color: "#FFF"; font.pixelSize: 13
                    verticalAlignment: Text.AlignVCenter; leftPadding: 10; elide: Text.ElideRight
                }
                background: Rectangle {
                    color: highlighted ? "#8B5CF6" : (hovered ? "#2A2A2A" : "#1E1E1E")
                }
                highlighted: catPicker.currentIndex === index
            }
            popup: Popup {
                y: catPicker.height + 4; width: catPicker.width; padding: 0
                contentItem: ListView {
                    clip: true; model: catPicker.delegateModel
                    implicitHeight: Math.min(contentHeight, 240)
                }
                background: Rectangle {
                    color: "#1E1E1E"; radius: 6; border.color: "#333"; border.width: 1
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true; height: 42; radius: 10; color: "#1E1E1E"
            border.color: sf.activeFocus ? "#8B5CF6" : "#333"; border.width: 1
            RowLayout { anchors.fill: parent; anchors.margins: 10; spacing: 8
                Text { text: "🔍"; font.pixelSize: 16 }
                TextField {
                    id: sf; Layout.fillWidth: true; placeholderText: "Search papers…"
                    color: "#FFF"; font.pixelSize: 14; background: null; placeholderTextColor: "#555"
                    onTextChanged: t.restart()
                    Keys.onReturnPressed: { t.stop(); doSearch(text) }
                }
                Text {
                    visible: sf.text.length > 0; text: "✕"; color: "#666"; font.pixelSize: 14
                    MouseArea { anchors.fill: parent; onClicked: {
                        sf.text = ""; root._isSearch = false
                        if (root._categories.length > 0)
                            loadCategory(root._categories[catPicker.currentIndex].id)
                    }}
                }
            }
        }
        Timer { id: t; interval: 600; onTriggered: doSearch(sf.text) }

        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 1; model: papersModel

            delegate: Rectangle {
                width: ListView.view.width; height: 78; color: "#0A0A0A"
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#1A1A1A" }

                Column {
                    anchors { fill: parent; margins: 12; rightMargin: 16 }
                    spacing: 5

                    Text {
                        width: parent.width; text: model.title
                        color: "#EEE"; font.pixelSize: 13; font.weight: Font.Medium
                        elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        width: parent.width; spacing: 8
                        Text {
                            Layout.fillWidth: true; text: model.authors_str
                            color: "#888"; font.pixelSize: 11; elide: Text.ElideRight
                        }
                        Text { text: model.published; color: "#555"; font.pixelSize: 11 }
                        Rectangle {
                            height: 18; radius: 4; color: "#1E0A3A"
                            width: catBadge.implicitWidth + 10
                            Text {
                                id: catBadge; anchors.centerIn: parent
                                text: model.primary_category; color: "#9C7FD4"; font.pixelSize: 10
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.StackView.view.push(Qt.resolvedUrl("PaperDetail.qml"), {
                        paperId:       model.paper_id,
                        paperTitle:    model.title,
                        paperAuthors:  model.authors_str,
                        paperAbstract: model.abstract,
                        paperDate:     model.published,
                        paperCategory: model.primary_category
                    })
                }
            }
        }
    }

    ListModel { id: papersModel }
}
