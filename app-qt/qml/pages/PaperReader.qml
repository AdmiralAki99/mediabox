import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Pdf
import QtWebEngine
import "../components"

Rectangle {
    id: root
    color: "#121212"

    property string paperId:    ""
    property string paperTitle: ""
    property string _reqId:     ""
    property string _mode:      "pdf"   // "pdf" | "html"

    property string _pdfFileUrl: ""
    property real   _zoom:       1.0
    property real   _zoomStart:  1.0    // captured when pinch begins

    Connections {
        target: api
        function onPdfReady(reqId, fileUrl) {
            if (reqId !== root._reqId) return
            if (!fileUrl) { statusText.text = "Failed to load PDF"; return }
            root._pdfFileUrl = fileUrl
            doc.source = fileUrl
            statusText.text = ""
        }
    }

    Component.onCompleted: {
        root._reqId = "pdf_" + Date.now()
        statusText.text = "Loading…"
        api.downloadPdf(root._reqId, "http://localhost:8000/arxiv/pdf/" + root.paperId)
    }

    PdfDocument { id: doc }

    Timer { id: hideTimer; interval: 3000; onTriggered: root.controlsVisible = false }
    property bool controlsVisible: true

    Flickable {
        id: pdfFlickable
        anchors.fill: parent
        // Pages render at their actual zoomed pixel size — no scale transform needed
        contentWidth:  pdfColumn.width
        contentHeight: pdfColumn.implicitHeight + 24
        clip: true
        visible: root._mode === "pdf"
        flickableDirection: root._zoom > 1.0 ? Flickable.AutoFlickDirection
                                              : Flickable.VerticalFlick

        Column {
            id: pdfColumn
            // Width drives the render resolution — larger = crisper text
            width: pdfFlickable.width * root._zoom
            spacing: 8
            topPadding: 8; bottomPadding: 8

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
                    color: "white"

                    PdfPageImage {
                        anchors.fill: parent
                        document: doc
                        currentFrame: index
                        fillMode: Image.Stretch
                        smooth: true
                        focus: false
                        // Render at 2× physical pixels so text is crisp (like PDF.js at devicePixelRatio)
                        sourceSize.width:  parent.width  * 2
                        sourceSize.height: parent.height * 2
                    }
                }
            }
        }

        PinchHandler {
            id: pinchHandler
            target: null

            onActiveChanged: {
                if (active) root._zoomStart = root._zoom
            }

            onActiveScaleChanged: {
                var newZoom = Math.max(1.0, Math.min(4.0, root._zoomStart * activeScale))
                var ratio   = newZoom / root._zoom
                var cx = centroid.position.x
                var cy = centroid.position.y
                // Content pixels grow with zoom, so scroll offsets scale proportionally;
                // subtract the pinch centre so that point stays fixed on screen.
                pdfFlickable.contentX = Math.max(0, pdfFlickable.contentX * ratio + cx * (ratio - 1))
                pdfFlickable.contentY = Math.max(0, pdfFlickable.contentY * ratio + cy * (ratio - 1))
                root._zoom = newZoom
            }
        }

        TapHandler {
            onTapped: {
                root.controlsVisible = !root.controlsVisible
                if (root.controlsVisible) hideTimer.restart()
            }
        }
    }

    WebEngineView {
        id: htmlView
        anchors.fill: parent
        visible: root._mode === "html"
        url: root._mode === "html"
             ? "http://localhost:8000/arxiv/html/" + root.paperId : ""
        settings.javascriptEnabled: true

        onLoadingChanged: function(req) {
            if (req.status === WebEngineLoadingInfo.LoadFailedStatus)
                statusText.text = "HTML unavailable — try PDF"
        }

        TapHandler {
            onTapped: {
                root.controlsVisible = !root.controlsVisible
                if (root.controlsVisible) hideTimer.restart()
            }
        }
    }

    Text {
        id: statusText
        anchors.centerIn: parent
        visible: text !== ""
        color: "#888"; font.pixelSize: 14
    }

    Rectangle {
        visible: root.controlsVisible
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: 46
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#EE000000" }
            GradientStop { position: 1.0; color: "transparent" }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin: 70
            anchors.right: parent.right; anchors.rightMargin: 16
            text: root.paperTitle; color: "#FFF"; font.pixelSize: 13
            elide: Text.ElideRight; opacity: 0.85
        }
    }

    Column {
        visible: root.controlsVisible
        anchors.left: parent.left; anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        // Scroll up
        Rectangle {
            width: 44; height: 44; radius: 22; color: "#AA000000"
            Text { anchors.centerIn: parent; text: "↑"; color: "#FFF"; font.pixelSize: 22 }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (root._mode === "pdf")
                        pdfFlickable.contentY = Math.max(0, pdfFlickable.contentY - 400)
                    else if (root._mode === "html")
                        htmlView.runJavaScript("window.scrollBy(0, -400)")
                    hideTimer.restart()
                }
            }
        }

        // Back
        Rectangle {
            width: 44; height: 44; radius: 22; color: "#AA000000"
            Text { anchors.centerIn: parent; text: "←"; color: "#FFF"; font.pixelSize: 20 }
            MouseArea { anchors.fill: parent; onClicked: root.StackView.view.pop() }
        }

        // Scroll down
        Rectangle {
            width: 44; height: 44; radius: 22; color: "#AA000000"
            Text { anchors.centerIn: parent; text: "↓"; color: "#FFF"; font.pixelSize: 22 }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (root._mode === "pdf")
                        pdfFlickable.contentY = Math.min(
                            pdfFlickable.contentHeight - pdfFlickable.height,
                            pdfFlickable.contentY + 400)
                    else if (root._mode === "html")
                        htmlView.runJavaScript("window.scrollBy(0, 400)")
                    hideTimer.restart()
                }
            }
        }
    }

    Rectangle {
        visible: root.controlsVisible
        anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
        height: 52
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: "#EE000000" }
        }

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12; bottomMargin: 8 }
            spacing: 8

            // Page counter (PDF mode only)
            Text {
                visible: root._mode === "pdf" && doc.pageCount > 0
                text: {
                    if (doc.pageCount <= 0) return ""
                    var approx = Math.floor(
                        pdfFlickable.contentY / pdfFlickable.contentHeight * doc.pageCount) + 1
                    return Math.min(approx, doc.pageCount) + " / " + doc.pageCount
                }
                color: "#AAA"; font.pixelSize: 12
            }

            Item { Layout.fillWidth: true }

            // Zoom out
            Rectangle {
                visible: root._mode === "pdf"
                width: 38; height: 32; radius: 8
                color: "#1E1E1E"; border.color: "#444"; border.width: 1
                Text { anchors.centerIn: parent; text: "−"; color: "#FFF"; font.pixelSize: 18 }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        var newZoom = Math.max(1.0, root._zoom - 0.25)
                        var ratio = newZoom / root._zoom
                        var cx = pdfFlickable.width  / 2
                        var cy = pdfFlickable.height / 2
                        pdfFlickable.contentX = Math.max(0, pdfFlickable.contentX * ratio + cx * (ratio - 1))
                        pdfFlickable.contentY = Math.max(0, pdfFlickable.contentY * ratio + cy * (ratio - 1))
                        root._zoom = newZoom
                        hideTimer.restart()
                    }
                }
            }

            // Zoom label
            Text {
                visible: root._mode === "pdf"
                text: Math.round(root._zoom * 100) + "%"
                color: "#888"; font.pixelSize: 11
                Layout.minimumWidth: 36
                horizontalAlignment: Text.AlignHCenter
            }

            // Zoom in
            Rectangle {
                visible: root._mode === "pdf"
                width: 38; height: 32; radius: 8
                color: "#1E1E1E"; border.color: "#444"; border.width: 1
                Text { anchors.centerIn: parent; text: "+"; color: "#FFF"; font.pixelSize: 18 }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        var newZoom = Math.min(4.0, root._zoom + 0.25)
                        var ratio = newZoom / root._zoom
                        var cx = pdfFlickable.width  / 2
                        var cy = pdfFlickable.height / 2
                        pdfFlickable.contentX = Math.max(0, pdfFlickable.contentX * ratio + cx * (ratio - 1))
                        pdfFlickable.contentY = Math.max(0, pdfFlickable.contentY * ratio + cy * (ratio - 1))
                        root._zoom = newZoom
                        hideTimer.restart()
                    }
                }
            }

            // PDF toggle
            Rectangle {
                width: 52; height: 32; radius: 8
                color: root._mode === "pdf" ? "#8B5CF6" : "#1E1E1E"
                border.color: "#8B5CF6"; border.width: 1
                Text { anchors.centerIn: parent; text: "PDF"; color: "#FFF"; font.pixelSize: 13; font.weight: Font.Medium }
                MouseArea { anchors.fill: parent; onClicked: { root._mode = "pdf"; hideTimer.restart() } }
            }

            // HTML toggle
            Rectangle {
                width: 52; height: 32; radius: 8
                color: root._mode === "html" ? "#8B5CF6" : "#1E1E1E"
                border.color: "#8B5CF6"; border.width: 1
                Text { anchors.centerIn: parent; text: "HTML"; color: "#FFF"; font.pixelSize: 13; font.weight: Font.Medium }
                MouseArea { anchors.fill: parent; onClicked: { root._mode = "html"; hideTimer.restart() } }
            }
        }
    }
}
