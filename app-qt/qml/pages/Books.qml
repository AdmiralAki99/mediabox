import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    color: "#0A0A0A"

    property string _reqId:         ""
    property bool   _isSearch:      false
    property bool   _loading:       false
    property string _selectedGenre: ""
    property string _tab:           "browse"
    property string _bsListName:    "fiction"
    property bool   _bsLoaded:      false

    property var  _homeReqMap:  ({})     // reqId → carousel index
    property bool _homeLoaded:  false

    readonly property var carouselDefs: [
        { label: "Science Fiction", q: "science fiction",    color: "#8B5CF6", emoji: "🚀" },
        { label: "Fantasy",         q: "fantasy novel",      color: "#8B5CF6", emoji: "✨" },
        { label: "Mystery",         q: "mystery thriller",   color: "#8B5CF6", emoji: "🔍" },
        { label: "Biography",       q: "biography memoir",   color: "#009688", emoji: "👤" },
        { label: "Classics",        q: "classic literature", color: "#8B5CF6", emoji: "📜" },
    ]

    // 5 pre-defined ListModels — one per carousel
    ListModel { id: cm0 }
    ListModel { id: cm1 }
    ListModel { id: cm2 }
    ListModel { id: cm3 }
    ListModel { id: cm4 }
    readonly property var _cms: [cm0, cm1, cm2, cm3, cm4]

    function loadHomeCarousels() {
        if (root._homeLoaded) return
        root._homeLoaded = true
        var map = {}
        for (var i = 0; i < root.carouselDefs.length; i++) {
            var reqId = "hc_" + i + "_" + Date.now()
            map[reqId] = i
            api.fetch(reqId, "/books/search",
                      JSON.stringify({ q: root.carouselDefs[i].q, limit: 12 }))
        }
        root._homeReqMap = map
    }

    Component.onCompleted: loadHomeCarousels()

    readonly property var genres: [
        { label: "Science Fiction", q: "science fiction",    color: "#8B5CF6" },
        { label: "Fantasy",         q: "fantasy novel",      color: "#8B5CF6" },
        { label: "Mystery",         q: "mystery thriller",   color: "#8B5CF6" },
        { label: "Horror",          q: "horror novel",       color: "#607D8B" },
        { label: "History",         q: "world history",      color: "#795548" },
        { label: "Biography",       q: "biography memoir",   color: "#009688" },
        { label: "Philosophy",      q: "philosophy",         color: "#3F51B5" },
        { label: "Romance",         q: "romance novel",      color: "#8B5CF6" },
        { label: "Classic",         q: "classic literature", color: "#8B5CF6" },
        { label: "Science",         q: "popular science",    color: "#4CAF50" },
    ]

    Connections {
        target: api
        function onFetched(id, data) {
            // Carousel home responses
            if (root._homeReqMap.hasOwnProperty(id)) {
                var ci   = root._homeReqMap[id]
                var craw = JSON.parse(data)
                var list = Array.isArray(craw) ? craw : []
                list.forEach(function(item) {
                    root._cms[ci].append({
                        title:    item.title     || "",
                        author:   item.author    || "",
                        coverUrl: item.cover_url || "",
                        source:   item.source    || "",
                        bookJson: JSON.stringify(item)
                    })
                })
                return
            }

            if (id !== root._reqId) return
            root._loading = false
            var raw = JSON.parse(data)
            if (raw.error) {
                statusText.text    = "Error"
                bsStatusText.text  = "Failed to load"
                return
            }
            resultsModel.clear()
            var items = Array.isArray(raw) ? raw : (raw.results || [])
            items.forEach(function(item) {
                resultsModel.append({
                    title:    item.title     || "",
                    author:   item.author    || "",
                    coverUrl: item.cover_url || "",
                    source:   item.source    || "",
                    bookJson: JSON.stringify(item)
                })
            })
            if (root._tab === "bestsellers") {
                root._bsLoaded    = true
                bsStatusText.text = items.length + " titles"
            } else {
                statusText.text = items.length + " results"
            }
        }
    }

    function doSearch(q) {
        if (!q.trim()) { root._isSearch = false; resultsModel.clear(); return }
        root._isSearch  = true
        root._loading   = true
        statusText.text = "Searching…"
        root._reqId = "books_s_" + Date.now()
        api.fetch(root._reqId, "/books/search", JSON.stringify({ q: q }))
    }

    function pushDetail(bookJson) {
        root.StackView.view.push(Qt.resolvedUrl("BookDetail.qml"), { bookJson: bookJson })
    }

    function loadBestsellers(listName) {
        root._bsListName = listName
        root._loading    = true
        root._bsLoaded   = false
        root._reqId      = "books_bs_" + Date.now()
        api.fetch(root._reqId, "/books/trending", JSON.stringify({ list_name: listName }))
    }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 12; spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Text { text: "Books"; color: "#FFF"; font.pixelSize: 20; font.weight: Font.Bold }
            Item { Layout.fillWidth: true }
            Row {
                spacing: 4
                Repeater {
                    model: [{ label: "Browse", key: "browse" },
                            { label: "Best Sellers", key: "bestsellers" }]
                    Rectangle {
                        height: 26; width: tabLbl.implicitWidth + 16; radius: 13
                        color: root._tab === modelData.key ? "#8B5CF6" : "#141414"
                        border.color: root._tab === modelData.key ? "#8B5CF6" : "#2A2A2A"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            id: tabLbl; anchors.centerIn: parent
                            text: modelData.label
                            color: root._tab === modelData.key ? "#FFF" : "#666"
                            font.pixelSize: 11; font.weight: Font.Medium
                        }
                        TapHandler {
                            onTapped: {
                                if (root._tab === modelData.key) return
                                root._tab = modelData.key
                                if (modelData.key === "bestsellers" && !root._bsLoaded) {
                                    resultsModel.clear()
                                    loadBestsellers(root._bsListName)
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true; height: 42; radius: 12; color: "#141414"
            visible: root._tab === "browse"
            border.color: sf.activeFocus ? "#8B5CF6" : "#222"; border.width: 1
            Behavior on border.color { ColorAnimation { duration: 150 } }
            Row {
                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: "🔍"; font.pixelSize: 15 }
                TextField {
                    id: sf
                    width: parent.width - 40 - (clearBtn.visible ? 28 : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "Search books, authors, ISBN…"
                    color: "#FFF"; font.pixelSize: 13; background: null; placeholderTextColor: "#444"
                    onTextChanged: { root._selectedGenre = ""; searchTimer.restart() }
                    Keys.onReturnPressed: { searchTimer.stop(); doSearch(text) }
                }
                Text {
                    id: clearBtn; visible: sf.text.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; color: "#555"; font.pixelSize: 13
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            sf.text = ""; root._isSearch = false
                            root._selectedGenre = ""
                            resultsModel.clear(); statusText.text = ""
                        }
                    }
                }
            }
        }
        Timer { id: searchTimer; interval: 400; onTriggered: doSearch(sf.text) }

        Item {
            Layout.fillWidth: true; height: 32
            visible: root._tab === "browse"
            Flickable {
                anchors.fill: parent
                contentWidth: chipRow.implicitWidth
                flickableDirection: Flickable.HorizontalFlick
                clip: true
                Row {
                    id: chipRow; spacing: 6; anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: root.genres
                        Rectangle {
                            id: chip
                            property bool active: root._selectedGenre === modelData.label
                            height: 26; width: chipLabel.implicitWidth + 16; radius: 13
                            color: active ? modelData.color : "#141414"
                            border.color: active ? modelData.color : "#2A2A2A"; border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            opacity: chipTap.pressed ? 0.6 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 80 } }
                            Text {
                                id: chipLabel; anchors.centerIn: parent
                                text: modelData.label
                                color: chip.active ? "#FFF" : "#666"; font.pixelSize: 11
                            }
                            TapHandler {
                                id: chipTap
                                onTapped: {
                                    if (root._selectedGenre === modelData.label) {
                                        root._selectedGenre = ""; root._isSearch = false
                                        resultsModel.clear(); statusText.text = ""
                                    } else {
                                        root._selectedGenre = modelData.label
                                        sf.clear(); searchTimer.stop()
                                        doSearch(modelData.q)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root._tab === "bestsellers"
            spacing: 6
            Repeater {
                model: [{ label: "Fiction",     key: "fiction"     },
                        { label: "Nonfiction",   key: "nonfiction"  },
                        { label: "Young Adult",  key: "young-adult" },
                        { label: "Paperback",    key: "paperback"   }]
                Rectangle {
                    height: 26; width: bsChipLbl.implicitWidth + 14; radius: 13
                    color: root._bsListName === modelData.key ? "#8B5CF6" : "#141414"
                    border.color: root._bsListName === modelData.key ? "#8B5CF6" : "#2A2A2A"; border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text {
                        id: bsChipLbl; anchors.centerIn: parent; text: modelData.label
                        color: root._bsListName === modelData.key ? "#FFF" : "#666"; font.pixelSize: 11
                    }
                    TapHandler {
                        onTapped: {
                            if (root._bsListName === modelData.key) return
                            resultsModel.clear(); loadBestsellers(modelData.key)
                        }
                    }
                }
            }
            Item { Layout.fillWidth: true }
            Text { id: bsStatusText; color: "#444"; font.pixelSize: 10; text: root._loading ? "Loading…" : "" }
        }

        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            // Searching / loading indicator
            Text {
                anchors.centerIn: parent
                visible: root._loading
                text: root._tab === "bestsellers" ? "Loading best sellers…" : "Searching…"
                color: "#444"; font.pixelSize: 13
            }

            Flickable {
                id: homeFlickable
                anchors.fill: parent
                contentHeight: carouselCol.implicitHeight + 8
                flickableDirection: Flickable.VerticalFlick
                clip: true
                visible: root._tab === "browse" && !root._isSearch && !root._loading

                ScrollBar.vertical: ScrollBar { width: 3
                    contentItem: Rectangle { radius: 2; color: "#FFF"
                        opacity: parent.active ? 0.08 : 0
                        Behavior on opacity { NumberAnimation { duration: 400 } } }
                    background: Item {} }

                Column {
                    id: carouselCol
                    width: homeFlickable.width
                    spacing: 0

                    Repeater {
                        model: root.carouselDefs.length

                        Item {
                            // Capture carousel index before inner Repeaters shadow it
                            property int ci: index

                            width: carouselCol.width
                            height: carouselSection.implicitHeight + 24

                            Column {
                                id: carouselSection
                                width: parent.width
                                spacing: 10
                                topPadding: ci === 0 ? 4 : 0

                                // Section header (plain Item, no RowLayout — avoids anchors conflict)
                                Item {
                                    width: parent.width; height: 22

                                    Rectangle {
                                        width: 3; height: 16; radius: 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: root.carouselDefs[ci].color
                                    }

                                    Text {
                                        anchors.left: parent.left; anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.carouselDefs[ci].emoji + "  " + root.carouselDefs[ci].label
                                        color: "#DDD"; font.pixelSize: 13; font.weight: Font.Bold
                                    }

                                    Text {
                                        anchors.right: parent.right; anchors.rightMargin: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "See all →"
                                        color: root.carouselDefs[ci].color
                                        font.pixelSize: 11
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                root._selectedGenre = root.carouselDefs[ci].label
                                                sf.clear(); searchTimer.stop()
                                                doSearch(root.carouselDefs[ci].q)
                                            }
                                        }
                                    }
                                }

                                // Horizontal book strip
                                Flickable {
                                    width: parent.width
                                    height: 162
                                    contentWidth: stripRow.implicitWidth + 4
                                    flickableDirection: Flickable.HorizontalFlick
                                    clip: true

                                    Row {
                                        id: stripRow
                                        spacing: 8; leftPadding: 2; rightPadding: 2

                                        // Skeleton placeholders while loading
                                        Repeater {
                                            model: root._cms[ci].count === 0 ? 6 : 0
                                            Rectangle {
                                                width: 90; height: 135; radius: 8; color: "#141414"
                                                Rectangle {
                                                    width: parent.width * 0.55; height: parent.height
                                                    color: "#FFF"; opacity: 0.025; radius: 8
                                                    NumberAnimation on x {
                                                        from: -90; to: 90
                                                        duration: 1400; loops: Animation.Infinite; running: true
                                                    }
                                                }
                                            }
                                        }

                                        // Actual books
                                        Repeater {
                                            model: root._cms[ci]
                                            delegate: Item {
                                                width: 90; height: 162

                                                // Carousel index accessible from parent scope
                                                property int carouselIdx: ci

                                                // Cover
                                                Rectangle {
                                                    id: cCard
                                                    width: 90; height: 135; radius: 8
                                                    color: "#1A1A1A"; clip: true

                                                    Image {
                                                        id: cImg; anchors.fill: parent
                                                        source: model.coverUrl !== ""
                                                                ? ("http://localhost:8000/books/cover?url="
                                                                   + encodeURIComponent(model.coverUrl))
                                                                : ""
                                                        fillMode: Image.PreserveAspectCrop
                                                        asynchronous: true; cache: true; smooth: true
                                                    }

                                                    // Skeleton shimmer while loading
                                                    Rectangle {
                                                        anchors.fill: parent; color: "#1E1E1E"
                                                        visible: cImg.status === Image.Loading
                                                        Rectangle {
                                                            width: parent.width * 0.55; height: parent.height
                                                            color: "#FFF"; opacity: 0.03
                                                            NumberAnimation on x {
                                                                from: -90; to: 90
                                                                duration: 1300; loops: Animation.Infinite; running: true
                                                            }
                                                        }
                                                    }

                                                    // No cover fallback
                                                    Text {
                                                        anchors.centerIn: parent
                                                        visible: model.coverUrl === "" || cImg.status === Image.Error
                                                        text: root.carouselDefs[carouselIdx].emoji
                                                        font.pixelSize: 26; opacity: 0.25
                                                    }

                                                    // Bottom title gradient overlay
                                                    Rectangle {
                                                        anchors.bottom: parent.bottom
                                                        width: parent.width; height: 52; radius: 8
                                                        gradient: Gradient {
                                                            GradientStop { position: 0.0; color: "transparent" }
                                                            GradientStop { position: 1.0; color: "#CC000000" }
                                                        }
                                                    }
                                                    Text {
                                                        anchors.bottom: parent.bottom
                                                        anchors.left: parent.left; anchors.right: parent.right
                                                        anchors.margins: 6; bottomPadding: 5
                                                        text: model.title; color: "#EEE"
                                                        font.pixelSize: 9; font.weight: Font.Medium
                                                        wrapMode: Text.WordWrap; maximumLineCount: 2
                                                        elide: Text.ElideRight
                                                    }

                                                    // Sheen
                                                    Item {
                                                        anchors.fill: parent; clip: true
                                                        visible: cImg.status === Image.Ready
                                                        Rectangle {
                                                            id: cSheen
                                                            width: parent.width * 0.4; height: parent.height * 3
                                                            y: -parent.height; rotation: -22; x: -90
                                                            gradient: Gradient {
                                                                GradientStop { position: 0.0; color: "transparent" }
                                                                GradientStop { position: 0.5; color: Qt.rgba(1,1,1,0.06) }
                                                                GradientStop { position: 1.0; color: "transparent" }
                                                            }
                                                            SequentialAnimation on x {
                                                                id: cSheenAnim; running: false; loops: Animation.Infinite
                                                                NumberAnimation {
                                                                    from: -cSheen.parent.width * 0.5
                                                                    to:    cSheen.parent.width * 1.3
                                                                    duration: 850; easing.type: Easing.InOutQuad
                                                                }
                                                                PauseAnimation { duration: 5500 }
                                                            }
                                                        }
                                                        Component.onCompleted: {
                                                            cSheenTimer.interval = Math.random() * 5000
                                                            cSheenTimer.start()
                                                        }
                                                        Timer {
                                                            id: cSheenTimer
                                                            onTriggered: cSheenAnim.running = true
                                                        }
                                                    }

                                                    // Press flash
                                                    Rectangle {
                                                        anchors.fill: parent; radius: 8; color: "white"
                                                        opacity: cTap.pressed ? 0.1 : 0
                                                        Behavior on opacity { NumberAnimation { duration: 80 } }
                                                    }
                                                }

                                                // Author below card
                                                Text {
                                                    anchors.top: cCard.bottom; anchors.topMargin: 4
                                                    anchors.left: parent.left; anchors.right: parent.right
                                                    text: model.author; color: "#444"; font.pixelSize: 9
                                                    elide: Text.ElideRight
                                                }

                                                // Scale on press
                                                scale: cTap.pressed ? 0.93 : 1.0
                                                Behavior on scale { SpringAnimation { spring: 7; damping: 0.5 } }

                                                TapHandler {
                                                    id: cTap
                                                    onTapped: root.pushDetail(model.bookJson)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            GridView {
                id: grid
                anchors.fill: parent
                visible: !root._loading && resultsModel.count > 0 &&
                         (root._isSearch || root._selectedGenre !== "" || root._tab === "bestsellers")
                cellWidth: Math.floor(width / 4); cellHeight: 230
                clip: true; model: resultsModel
                flickDeceleration: 700; maximumFlickVelocity: 2800

                ScrollBar.vertical: ScrollBar { width: 3
                    contentItem: Rectangle { radius: 2; color: "#FFF"
                        opacity: parent.active ? 0.15 : 0
                        Behavior on opacity { NumberAnimation { duration: 500 } } }
                    background: Item {} }

                delegate: Item {
                    width: grid.cellWidth; height: 230

                    Column {
                        anchors.centerIn: parent; spacing: 0
                        width: grid.cellWidth - 10

                        Rectangle {
                            width: parent.width; height: 178; radius: 10; color: "#1A1A1A"; clip: true

                            Image {
                                id: coverImg; anchors.fill: parent
                                source: model.coverUrl !== ""
                                        ? ("http://localhost:8000/books/cover?url="
                                           + encodeURIComponent(model.coverUrl))
                                        : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true; cache: true; smooth: true

                                Rectangle {
                                    anchors.fill: parent; color: "#1E1E1E"
                                    visible: coverImg.status === Image.Loading
                                    Rectangle {
                                        width: parent.width * 0.6; height: parent.height
                                        color: "#FFF"; opacity: 0.03
                                        NumberAnimation on x {
                                            from: -parent.parent.width; to: parent.parent.width
                                            duration: 1200; loops: Animation.Infinite; running: true
                                        }
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: model.coverUrl === "" || coverImg.status === Image.Error
                                    text: "📖"; font.pixelSize: 28; opacity: 0.3
                                }
                            }

                            Item {
                                anchors.fill: parent; clip: true
                                visible: coverImg.status === Image.Ready
                                Rectangle {
                                    id: sheenStrip
                                    width: parent.width * 0.45; height: parent.height * 3
                                    y: -parent.height; rotation: -22; x: -parent.width
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 0.5; color: Qt.rgba(1,1,1,0.07) }
                                        GradientStop { position: 1.0; color: "transparent" }
                                    }
                                    SequentialAnimation on x {
                                        id: sheenAnim; running: false; loops: Animation.Infinite
                                        NumberAnimation {
                                            from: -sheenStrip.parent.width * 0.5
                                            to:    sheenStrip.parent.width * 1.3
                                            duration: 900; easing.type: Easing.InOutQuad
                                        }
                                        PauseAnimation { duration: 5000 }
                                    }
                                }
                                Component.onCompleted: {
                                    sheenDelay.interval = Math.random() * 4000; sheenDelay.start()
                                }
                                Timer { id: sheenDelay; onTriggered: sheenAnim.running = true }
                            }

                            Rectangle {
                                anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 5
                                height: 16; width: srcBadge.implicitWidth + 8; radius: 4
                                color: model.source === "gutenberg" ? "#0D3320" : "#0D2020"; opacity: 0.9
                                Text {
                                    id: srcBadge; anchors.centerIn: parent
                                    text: model.source === "gutenberg" ? "PG" : "ZL"
                                    color: model.source === "gutenberg" ? "#4CAF50" : "#26C6DA"
                                    font.pixelSize: 8; font.weight: Font.Bold
                                }
                            }

                            Rectangle {
                                anchors.fill: parent; radius: 10; color: "white"
                                opacity: cardMA.pressed ? 0.08 : 0
                                Behavior on opacity { NumberAnimation { duration: 80 } }
                            }
                        }

                        Text {
                            width: parent.width; topPadding: 5
                            text: model.title; color: "#DDD"; font.pixelSize: 11
                            elide: Text.ElideRight; maximumLineCount: 1
                        }
                        Text {
                            width: parent.width
                            text: model.author; color: "#555"; font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    scale: cardMA.pressed ? 0.95 : 1.0
                    Behavior on scale { SpringAnimation { spring: 6; damping: 0.42 } }
                    MouseArea { id: cardMA; anchors.fill: parent; onClicked: root.pushDetail(model.bookJson) }
                }
            }

            // Status text (bottom-right, browse search results)
            Text {
                id: statusText
                anchors.bottom: parent.bottom; anchors.right: parent.right
                anchors.bottomMargin: 4; anchors.rightMargin: 4
                color: "#333"; font.pixelSize: 10
                visible: root._tab === "browse" && root._isSearch && !root._loading
            }
        }
    }

    ListModel { id: resultsModel }
}
