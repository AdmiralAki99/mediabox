import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Pdf
import QtWebEngine
import "../components"

Rectangle {
    id: root
    color: "#f4ead8"   // sepia default (matches epub.js reader)

    property string readUrl:    ""    // http://localhost:8000/books/file?url=...
    property string bookTitle:  ""
    property string bookFormat: ""    // "epub" | "pdf" | other
    property string bookId:     ""    // EbookResult.id — used for bookmark save/resume

    property string _pdfReqId:  ""
    property real   _zoom:      1.0
    property real   _zoomStart: 1.0

    Timer { id: hideTimer; interval: 3000; onTriggered: root.controlsVisible = false }
    property bool controlsVisible: true

    PdfDocument { id: doc }

    Component.onCompleted: {
        if (root.bookFormat === "pdf") {
            root._pdfReqId = "bpdf_" + Date.now()
            statusText.text = "Loading…"
            api.downloadPdf(root._pdfReqId, root.readUrl)
        }
    }

    Connections {
        target: api
        function onPdfReady(reqId, fileUrl) {
            if (reqId !== root._pdfReqId) return
            if (!fileUrl) { statusText.text = "Failed to load PDF"; return }
            doc.source = fileUrl
            statusText.text = ""
        }
    }

    WebEngineView {
        id: epubView
        anchors.fill: parent
        visible: root.bookFormat === "epub"
        url: root.bookFormat === "epub"
             ? ("http://localhost:8000/books/reader"
                + "?url="     + encodeURIComponent(root.readUrl)
                + "&title="   + encodeURIComponent(root.bookTitle)
                + "&book_id=" + encodeURIComponent(root.bookId))
             : ""
        settings.javascriptEnabled: true
        settings.localStorageEnabled: true
        settings.allowRunningInsecureContent: true

        onLoadingChanged: function(req) {
            if (req.status === WebEngineLoadingInfo.LoadFailedStatus)
                statusText.text = "Failed to load book"
        }

        onJavaScriptConsoleMessage: function(level, msg, line, src) {
            console.log("[epub] " + msg + " (" + src + ":" + line + ")")
        }
    }

    Flickable {
        id: pdfFlickable
        anchors.fill: parent
        contentWidth:  pdfColumn.width
        contentHeight: pdfColumn.implicitHeight + 24
        clip: true
        visible: root.bookFormat === "pdf"
        flickableDirection: root._zoom > 1.0 ? Flickable.AutoFlickDirection
                                              : Flickable.VerticalFlick

        Column {
            id: pdfColumn
            width: pdfFlickable.width * root._zoom
            spacing: 8; topPadding: 8; bottomPadding: 8

            Repeater {
                model: doc.pageCount
                delegate: Rectangle {
                    width: pdfColumn.width
                    height: {
                        var ps = doc.pagePointSize(index)
                        return ps.width > 0
                            ? Math.round(width * ps.height / ps.width)
                            : Math.round(width * 1.414)
                    }
                    color: "#f4ead8"

                    PdfPageImage {
                        anchors.fill: parent
                        document: doc; currentFrame: index
                        fillMode: Image.Stretch; smooth: true; focus: false
                        sourceSize.width:  parent.width  * 2
                        sourceSize.height: parent.height * 2
                    }
                }
            }
        }

        PinchHandler {
            target: null
            onActiveChanged: if (active) root._zoomStart = root._zoom
            onActiveScaleChanged: {
                var newZoom = Math.max(1.0, Math.min(4.0, root._zoomStart * activeScale))
                var ratio   = newZoom / root._zoom
                var cx = centroid.position.x; var cy = centroid.position.y
                pdfFlickable.contentX = Math.max(0, pdfFlickable.contentX * ratio + cx * (ratio - 1))
                pdfFlickable.contentY = Math.max(0, pdfFlickable.contentY * ratio + cy * (ratio - 1))
                root._zoom = newZoom
            }
        }

        TapHandler {
            onTapped: { root.controlsVisible = !root.controlsVisible
                        if (root.controlsVisible) hideTimer.restart() }
        }
    }

    Rectangle {
        anchors.fill: parent; color: "#1a1008"
        visible: root.bookFormat !== "epub" && root.bookFormat !== "pdf"
        Column {
            anchors.centerIn: parent; spacing: 12
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "📚"; font.pixelSize: 48; opacity: 0.4
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "In-app reading supports EPUB and PDF.\nFormat: " + root.bookFormat
                color: "#AAA"; font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120; height: 40; radius: 10; color: "#1E1E1E"
                border.color: "#444"; border.width: 1
                Text { anchors.centerIn: parent; text: "← Back"; color: "#FFF"; font.pixelSize: 14 }
                MouseArea { anchors.fill: parent; onClicked: root.StackView.view.pop() }
            }
        }
    }

    Text {
        id: statusText
        anchors.centerIn: parent
        visible: text !== "" && root.bookFormat === "pdf"
        color: "#888"; font.pixelSize: 14
    }

    // Always shown for EPUB (no tap-to-hide since epub.js is fullscreen);
    // auto-hides for PDF
    Rectangle {
        visible: root.bookFormat === "epub" || root.controlsVisible
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: 48
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#EE000000" }
            GradientStop { position: 1.0; color: "transparent" }
        }

        Rectangle {
            anchors.left: parent.left; anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 36; height: 36; radius: 18; color: "#AA000000"
            Text { anchors.centerIn: parent; text: "←"; color: "#FFF"; font.pixelSize: 18 }
            MouseArea { anchors.fill: parent; onClicked: root.StackView.view.pop() }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin: 56
            anchors.right: parent.right; anchors.rightMargin: 12
            text: root.bookTitle; color: "#FFF"; font.pixelSize: 13
            elide: Text.ElideRight; opacity: 0.85
        }
    }

    Column {
        visible: root.controlsVisible && root.bookFormat === "pdf"
        anchors.left: parent.left; anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Rectangle {
            width: 44; height: 44; radius: 22; color: "#AA000000"
            Text { anchors.centerIn: parent; text: "↑"; color: "#FFF"; font.pixelSize: 22 }
            MouseArea {
                anchors.fill: parent
                onClicked: { pdfFlickable.contentY = Math.max(0, pdfFlickable.contentY - 400)
                             hideTimer.restart() }
            }
        }

        Rectangle {
            width: 44; height: 44; radius: 22; color: "#AA000000"
            Text { anchors.centerIn: parent; text: "↓"; color: "#FFF"; font.pixelSize: 22 }
            MouseArea {
                anchors.fill: parent
                onClicked: { pdfFlickable.contentY = Math.min(
                                 pdfFlickable.contentHeight - pdfFlickable.height,
                                 pdfFlickable.contentY + 400)
                             hideTimer.restart() }
            }
        }
    }

    Rectangle {
        visible: root.controlsVisible && root.bookFormat === "pdf"
        anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
        height: 52
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: "#EE000000" }
        }

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12; bottomMargin: 8 }
            spacing: 8

            Text {
                visible: doc.pageCount > 0
                text: {
                    if (doc.pageCount <= 0) return ""
                    var approx = Math.floor(pdfFlickable.contentY
                                            / pdfFlickable.contentHeight * doc.pageCount) + 1
                    return Math.min(approx, doc.pageCount) + " / " + doc.pageCount
                }
                color: "#AAA"; font.pixelSize: 12
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 38; height: 32; radius: 8; color: "#1E1E1E"
                border.color: "#444"; border.width: 1
                Text { anchors.centerIn: parent; text: "−"; color: "#FFF"; font.pixelSize: 18 }
                MouseArea { anchors.fill: parent; onClicked: {
                    var nz = Math.max(1.0, root._zoom - 0.25); var r = nz / root._zoom
                    var cx = pdfFlickable.width/2; var cy = pdfFlickable.height/2
                    pdfFlickable.contentX = Math.max(0, pdfFlickable.contentX * r + cx * (r-1))
                    pdfFlickable.contentY = Math.max(0, pdfFlickable.contentY * r + cy * (r-1))
                    root._zoom = nz; hideTimer.restart()
                }}
            }
            Text {
                text: Math.round(root._zoom * 100) + "%"
                color: "#888"; font.pixelSize: 11; Layout.minimumWidth: 36
                horizontalAlignment: Text.AlignHCenter
            }
            Rectangle {
                width: 38; height: 32; radius: 8; color: "#1E1E1E"
                border.color: "#444"; border.width: 1
                Text { anchors.centerIn: parent; text: "+"; color: "#FFF"; font.pixelSize: 18 }
                MouseArea { anchors.fill: parent; onClicked: {
                    var nz = Math.min(4.0, root._zoom + 0.25); var r = nz / root._zoom
                    var cx = pdfFlickable.width/2; var cy = pdfFlickable.height/2
                    pdfFlickable.contentX = Math.max(0, pdfFlickable.contentX * r + cx * (r-1))
                    pdfFlickable.contentY = Math.max(0, pdfFlickable.contentY * r + cy * (r-1))
                    root._zoom = nz; hideTimer.restart()
                }}
            }
        }
    }
}
