import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root; color: "#0A0A0A"

    property string bookJson: ""

    property string _title:    ""
    property string _author:   ""
    property string _year:     ""
    property string _cover:    ""
    property string _source:   ""   // "zlib" | "gutenberg"
    property string _id:       ""   // "zlib:{id}" | "gutenberg:{id}"
    property var    _formats:  []   // [{format, size_mb, download_url}]

    property string _infoReqId:   ""
    property string _description: ""
    property real   _rating:      0
    property int    _ratingsCount: 0
    property var    _categories:  []
    property var    _toc:            []
    property string _reviewSnippet: ""
    property string _reviewUrl:     ""
    property string _reviewByline:  ""
    property bool   _infoLoaded:    false

    property string _readReqId:     ""
    property int    _readFmtIndex:  -1
    property bool   _reading:       false

    property string _dlReqId:    ""
    property int    _dlFmtIndex: -1
    property bool   _dlRunning:  false

    property string _findReqId:   ""
    property bool   _finding:     false
    property bool   _findDone:    false   // true once search completed (hit or miss)

    property string _bmReqId:       ""
    property string _bookmarkCfi:   ""
    property real   _bookmarkProgress: 0.0  // 0.0–1.0

    Component.onCompleted: {
        if (!root.bookJson) return
        var b = JSON.parse(root.bookJson)
        root._title    = b.title    || ""
        root._author   = b.author   || ""
        root._year     = b.year     ? String(b.year) : ""
        root._cover    = b.cover_url || ""
        root._source   = b.source   || ""
        root._id       = b.id       || ""
        root._formats  = b.formats  || []

        root._infoReqId = "binfo_" + Date.now()
        api.fetch(root._infoReqId, "/books/info",
                  JSON.stringify({ title: root._title, author: root._author }))

        // Load saved bookmark (if any) to show the Resume button
        root._bmReqId = "bbm_" + Date.now()
        api.fetch(root._bmReqId, "/books/bookmark", JSON.stringify({ book_id: root._id }))

        // Discovery sources (NYT Best Sellers, Open Library trending) carry no
        // download formats. Auto-search Z-Library so the user can read directly.
        if (root._formats.length === 0 &&
            (root._source === "nyt" || root._source === "openlibrary")) {
            root._finding = true
            var q = root._title + (root._author ? " " + root._author : "")
            root._findReqId = "bfind_" + Date.now()
            api.fetch(root._findReqId, "/books/search",
                      JSON.stringify({ q: q, limit: 5 }))
        }
    }

    Connections {
        target: api
        function onFetched(id, data) {
            // Info response
            if (id === root._infoReqId) {
                root._infoLoaded = true
                var info = JSON.parse(data)
                if (!info.error) {
                    root._description   = info.description        || ""
                    root._rating        = info.rating             || 0
                    root._ratingsCount  = info.ratings_count      || 0
                    root._categories    = info.categories         || []
                    root._toc           = info.table_of_contents  || []
                    root._reviewSnippet = info.review_snippet     || ""
                    root._reviewUrl     = info.review_url         || ""
                    root._reviewByline  = info.review_byline      || ""
                }
                return
            }
            // Read resolve response
            if (id === root._readReqId) {
                root._reading = false
                var res = JSON.parse(data)
                if (res.error || !res.url) return
                var fmt = root._formats[root._readFmtIndex]
                var fileUrl = "http://localhost:8000/books/file?url="
                              + encodeURIComponent(res.url)
                root.StackView.view.push(Qt.resolvedUrl("BookReader.qml"), {
                    readUrl: fileUrl, bookTitle: root._title,
                    bookFormat: fmt ? fmt.format : "", bookId: root._id
                })
                return
            }
            // Download resolve response
            if (id === root._dlReqId) {
                root._dlRunning = false
                var dres = JSON.parse(data)
                if (dres.error || !dres.url) return
                Qt.openUrlExternally(dres.url)
                return
            }
            // Bookmark load response
            if (id === root._bmReqId) {
                var bm = JSON.parse(data)
                if (bm && !bm.error && bm.cfi && bm.cfi !== "") {
                    root._bookmarkCfi      = bm.cfi
                    root._bookmarkProgress = bm.progress || 0
                }
                return
            }
            // Z-Library auto-find response (for discovery-source books)
            if (id === root._findReqId) {
                root._finding  = false
                root._findDone = true
                var found = JSON.parse(data)
                if (!Array.isArray(found)) return
                // Pick the first result that has at least one format
                var titleLower = root._title.toLowerCase()
                var best = null
                for (var i = 0; i < found.length; i++) {
                    var r = found[i]
                    if (!r.formats || r.formats.length === 0) continue
                    if (!best) best = r
                    // Prefer a result whose title contains our title string
                    if ((r.title || "").toLowerCase().indexOf(titleLower) !== -1) {
                        best = r; break
                    }
                }
                if (best) root._formats = best.formats
                return
            }
        }
    }

    function startRead(index) {
        if (root._reading) return
        var fmt = root._formats[index]
        if (!fmt) return

        // Save full metadata bookmark (fire-and-forget) so the reader can update position
        api.postAsync("bbmeta_" + Date.now(), "/books/bookmark", JSON.stringify({
            book_id:   root._id,
            title:     root._title,
            author:    root._author,
            cover_url: root._cover,
            book_json: root.bookJson,
            format:    fmt.format
        }))

        var resolveUrl = fmt.resolve_url || ""
        var dl = fmt.download_url || ""
        if (resolveUrl !== "") {
            // Needs a resolve step to get the actual CDN URL (e.g. Z-Library)
            root._reading = true
            root._readFmtIndex = index
            root._readReqId = "bres_" + Date.now()
            api.fetch(root._readReqId, "/books/resolve",
                      JSON.stringify({ url: resolveUrl }))
        } else if (dl !== "") {
            var fileUrl = "http://localhost:8000/books/file?url=" + encodeURIComponent(dl)
            root.StackView.view.push(Qt.resolvedUrl("BookReader.qml"), {
                readUrl: fileUrl, bookTitle: root._title,
                bookFormat: fmt.format, bookId: root._id
            })
        }
    }

    function startDownload(index) {
        if (root._dlRunning) return
        var fmt = root._formats[index]
        if (!fmt) return
        var resolveUrl = fmt.resolve_url || ""
        var dl = fmt.download_url || ""
        if (resolveUrl !== "") {
            root._dlRunning = true
            root._dlFmtIndex = index
            root._dlReqId = "bdl_" + Date.now()
            api.fetch(root._dlReqId, "/books/resolve",
                      JSON.stringify({ url: resolveUrl }))
        } else if (dl !== "") {
            Qt.openUrlExternally(dl)
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: contentCol.implicitHeight + 32
        clip: true

        Column {
            id: contentCol
            width: parent.width
            spacing: 0

            Rectangle {
                width: parent.width; height: 56; color: "#0A0A0A"
                BackButton {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left; anchors.leftMargin: 12
                    onClicked: root.StackView.view.pop()
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left; anchors.leftMargin: 60
                    anchors.right: parent.right; anchors.rightMargin: 16
                    text: "Book Details"; color: "#FFF"; font.pixelSize: 17
                    font.weight: Font.Bold; elide: Text.ElideRight
                }
            }

            Row {
                width: parent.width; spacing: 16
                leftPadding: 16; rightPadding: 16; bottomPadding: 20

                // Cover
                Rectangle {
                    width: 96; height: 144; radius: 10; color: "#1A1A1A"; clip: true
                    Image {
                        id: detailCover
                        anchors.fill: parent
                        source: root._cover !== ""
                                ? ("http://localhost:8000/books/cover?url="
                                   + encodeURIComponent(root._cover))
                                : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    // Placeholder icon when no cover or load error
                    Text {
                        anchors.centerIn: parent
                        visible: root._cover === "" || detailCover.status === Image.Error
                        text: "📖"; font.pixelSize: 32; opacity: 0.4
                    }
                    // Live sheen
                    Item {
                        anchors.fill: parent; clip: true
                        visible: detailCover.status === Image.Ready
                        Rectangle {
                            id: detailSheen
                            width: parent.width * 0.45; height: parent.height * 3
                            y: -parent.height; rotation: -22; x: -parent.width
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 0.5; color: Qt.rgba(1,1,1,0.09) }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                            SequentialAnimation on x {
                                id: detailSheenAnim; running: false; loops: Animation.Infinite
                                NumberAnimation {
                                    from: -detailSheen.parent.width * 0.5
                                    to:    detailSheen.parent.width * 1.3
                                    duration: 1100; easing.type: Easing.InOutQuad
                                }
                                PauseAnimation { duration: 4500 }
                            }
                        }
                        Component.onCompleted: {
                            detailSheenTimer.interval = 600
                            detailSheenTimer.start()
                        }
                        Timer {
                            id: detailSheenTimer
                            onTriggered: detailSheenAnim.running = true
                        }
                    }
                }

                // Info column
                Column {
                    width: parent.width - 96 - 16 - 32
                    spacing: 6; topPadding: 4

                    Text {
                        width: parent.width
                        text: root._title; color: "#FFF"
                        font.pixelSize: 15; font.weight: Font.Bold
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        visible: root._author !== ""
                        text: root._author; color: "#AAA"; font.pixelSize: 12
                        wrapMode: Text.WordWrap; width: parent.width
                    }
                    Text {
                        visible: root._year !== ""
                        text: root._year; color: "#666"; font.pixelSize: 11
                    }

                    // Source badge
                    Rectangle {
                        height: 18; radius: 9
                        width: srcLabel.implicitWidth + 14
                        color: root._source === "gutenberg"   ? "#0D3320"
                             : root._source === "nyt"         ? "#1A0D00"
                             : root._source === "openlibrary" ? "#0D1A2A"
                             : "#0D2020"
                        Text {
                            id: srcLabel; anchors.centerIn: parent
                            text: root._source === "gutenberg"   ? "Project Gutenberg"
                                : root._source === "nyt"         ? "NYT Best Sellers"
                                : root._source === "openlibrary" ? "Open Library"
                                : "Z-Library"
                            color: root._source === "gutenberg"   ? "#4CAF50"
                                 : root._source === "nyt"         ? "#8B5CF6"
                                 : root._source === "openlibrary" ? "#42A5F5"
                                 : "#26C6DA"
                            font.pixelSize: 9; font.weight: Font.Bold
                        }
                    }

                    // Rating (shown once info loads)
                    Row {
                        visible: root._rating > 0
                        spacing: 4; topPadding: 2

                        Row {
                            spacing: 1
                            Repeater {
                                model: 5
                                Text {
                                    text: index < Math.round(root._rating) ? "★" : "☆"
                                    color: "#8B5CF6"; font.pixelSize: 13
                                }
                            }
                        }
                        Text {
                            text: root._rating.toFixed(1)
                                  + (root._ratingsCount > 0
                                     ? " (" + root._ratingsCount.toLocaleString() + ")" : "")
                            color: "#888"; font.pixelSize: 11
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            Flow {
                visible: root._categories.length > 0
                width: parent.width - 32
                x: 16; spacing: 6; bottomPadding: 16

                Repeater {
                    model: root._categories
                    Rectangle {
                        height: 20; radius: 4; color: "#1E1E1E"
                        border.color: "#333"; border.width: 1
                        width: catText.implicitWidth + 12
                        Text {
                            id: catText; anchors.centerIn: parent
                            text: modelData; color: "#888"; font.pixelSize: 10
                        }
                    }
                }
            }

            Rectangle {
                visible: root._description !== ""
                width: parent.width - 32; x: 16
                radius: 10; color: "#120D08"
                border.color: "#2A1E10"; border.width: 1
                height: descCol.implicitHeight + 24

                Column {
                    id: descCol
                    width: parent.width - 24; x: 12; y: 12
                    spacing: 8

                    Text {
                        text: "About"; color: "#8B5CF6"
                        font.pixelSize: 11; font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width
                        text: root._description
                        color: "#C8B89A"; font.pixelSize: 13
                        wrapMode: Text.WordWrap; lineHeight: 1.5
                    }
                }
            }
            Item { width: 1; height: root._description !== "" ? 16 : 0 }

            Rectangle {
                visible: root._reviewSnippet !== ""
                width: parent.width - 32; x: 16
                radius: 10; color: "#0D0A00"
                border.color: "#8B5CF633"; border.width: 1
                height: reviewCol.implicitHeight + 24

                Column {
                    id: reviewCol
                    width: parent.width - 24; x: 12; y: 12
                    spacing: 6

                    Row {
                        spacing: 6
                        Text {
                            text: "NYT Review"; color: "#8B5CF6"
                            font.pixelSize: 11; font.weight: Font.Bold
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            visible: root._reviewByline !== ""
                            text: root._reviewByline !== "" ? "· " + root._reviewByline : ""
                            color: "#664400"; font.pixelSize: 10
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Text {
                        width: parent.width
                        text: root._reviewSnippet
                        color: "#C8A870"; font.pixelSize: 13
                        wrapMode: Text.WordWrap; lineHeight: 1.5; font.italic: true
                    }
                    Text {
                        visible: root._reviewUrl !== ""
                        text: "Read full review →"
                        color: "#8B5CF6"; font.pixelSize: 11
                        topPadding: 2
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Qt.openUrlExternally(root._reviewUrl)
                        }
                    }
                }
            }
            Item { width: 1; height: root._reviewSnippet !== "" ? 16 : 0 }

            Column {
                visible: root._toc.length > 0
                width: parent.width - 32; x: 16
                spacing: 0; bottomPadding: 16

                Text {
                    text: "Table of Contents"; color: "#8B5CF6"
                    font.pixelSize: 11; font.weight: Font.Bold
                    bottomPadding: 10
                }

                Repeater {
                    model: root._toc
                    Row {
                        width: parent.width; spacing: 8; bottomPadding: 6

                        Text {
                            text: (index + 1) + "."
                            color: "#555"; font.pixelSize: 12
                            width: 24
                        }
                        Text {
                            width: parent.width - 32
                            text: modelData; color: "#AAA"; font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            Text {
                visible: !root._infoLoaded
                x: 16
                text: "Loading book info…"; color: "#444"; font.pixelSize: 12
                bottomPadding: 16
            }

            Rectangle {
                width: parent.width - 32; height: 1; color: "#1E1E1E"; x: 16
            }

            Column {
                width: parent.width - 32; x: 16
                spacing: 10; topPadding: 20; bottomPadding: 8

                Text {
                    text: "Available Formats"; color: "#666"
                    font.pixelSize: 10; font.weight: Font.Bold
                    bottomPadding: 2
                }

                Rectangle {
                    visible: root._bookmarkProgress > 0
                    width: parent.width; height: 52; radius: 12
                    color: "#0D1A0D"; border.color: "#2E7D32"; border.width: 1

                    Item {
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28; height: resumeCol.implicitHeight

                        Column {
                            id: resumeCol
                            spacing: 2
                            Text {
                                text: "▶  Resume reading"
                                color: "#4CAF50"; font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                            Row {
                                spacing: 6
                                Rectangle {
                                    width: 120 * root._bookmarkProgress; height: 3; radius: 2
                                    color: "#4CAF50"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Rectangle {
                                    width: 120 * (1 - root._bookmarkProgress); height: 3; radius: 2
                                    color: "#1A3A1A"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: Math.round(root._bookmarkProgress * 100) + "% complete"
                                    color: "#2E7D32"; font.pixelSize: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }

                    MouseArea { anchors.fill: parent; onClicked: root.startRead(0) }
                }

                Repeater {
                    model: root._formats.length > 0 ? root._formats.length : 0
                    delegate: Rectangle {
                        id: fmtRow
                        width: parent.width; height: 52; radius: 12
                        color: "#111"; border.color: "#222"; border.width: 1

                        property var fmt: root._formats[index] || {}
                        property bool isReading:     root._reading    && root._readFmtIndex === index
                        property bool isDownloading: root._dlRunning  && root._dlFmtIndex  === index

                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            // Format badge
                            Rectangle {
                                height: 24; radius: 6; color: "#1F1508"
                                border.color: "#8B5CF6"; border.width: 1
                                width: badgeText.implicitWidth + 14
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    id: badgeText; anchors.centerIn: parent
                                    text: (fmtRow.fmt.format || "").toUpperCase()
                                    color: "#8B5CF6"; font.pixelSize: 11; font.weight: Font.Bold
                                }
                            }

                            // Size
                            Text {
                                visible: fmtRow.fmt.size_mb !== undefined && fmtRow.fmt.size_mb !== null
                                text: {
                                    var s = fmtRow.fmt.size_mb || 0
                                    return s < 1 ? Math.round(s * 1024) + " KB" : s.toFixed(1) + " MB"
                                }
                                color: "#555"; font.pixelSize: 12
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Action buttons
                        Row {
                            anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            // Read button
                            Rectangle {
                                width: 80; height: 34; radius: 10
                                color: fmtRow.isReading ? "#6D3EC8" : "#8B5CF6"
                                opacity: root._reading && !fmtRow.isReading ? 0.5 : 1.0
                                Row {
                                    anchors.centerIn: parent; spacing: 5
                                    Text {
                                        text: fmtRow.isReading ? "⌛" : "📖"
                                        font.pixelSize: 13
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: fmtRow.isReading ? "Loading" : "Read"
                                        color: "#FFF"; font.pixelSize: 13; font.weight: Font.DemiBold
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.startRead(index)
                                }
                            }

                            // Download button
                            Rectangle {
                                width: 34; height: 34; radius: 10
                                color: "#1E1E1E"
                                border.color: fmtRow.isDownloading ? "#8B5CF6" : "#333"
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: fmtRow.isDownloading ? "⌛" : "⬇"
                                    font.pixelSize: 15; color: "#AAA"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.startDownload(index)
                                }
                            }
                        }
                    }
                }

                // Searching Z-Library…
                Row {
                    visible: root._finding
                    spacing: 8
                    Text {
                        text: "⌛"; font.pixelSize: 13
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Searching Z-Library…"; color: "#555"; font.pixelSize: 13
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Not found after search completed
                Text {
                    visible: !root._finding && root._findDone && root._formats.length === 0
                    text: "Not found on Z-Library or Gutenberg"
                    color: "#444"; font.pixelSize: 13
                }

                // Static sources with no formats and no auto-search
                Text {
                    visible: !root._finding && !root._findDone && root._formats.length === 0
                    text: "No formats available"; color: "#444"; font.pixelSize: 13
                }
            }
        }
    }
}
