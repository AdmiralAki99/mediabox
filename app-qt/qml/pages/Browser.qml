import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtWebEngine

Rectangle {
    id: root
    color: "#0A0A0A"

    property string homeUrl: "https://www.google.com"

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true; height: 48
            color: "#111111"; border.color: "#1E1E1E"; border.width: 1

            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 6

                // Back / Forward / Reload
                Rectangle {
                    width: 34; height: 34; radius: 8; color: backArea.pressed ? "#2a2a2a" : "#1E1E1E"
                    Text { anchors.centerIn: parent; text: "‹"; color: webView.canGoBack ? "#FFF" : "#444"; font.pixelSize: 20 }
                    MouseArea { id: backArea; anchors.fill: parent; onClicked: webView.goBack() }
                }
                Rectangle {
                    width: 34; height: 34; radius: 8; color: fwdArea.pressed ? "#2a2a2a" : "#1E1E1E"
                    Text { anchors.centerIn: parent; text: "›"; color: webView.canGoForward ? "#FFF" : "#444"; font.pixelSize: 20 }
                    MouseArea { id: fwdArea; anchors.fill: parent; onClicked: webView.goForward() }
                }
                Rectangle {
                    width: 34; height: 34; radius: 8; color: relArea.pressed ? "#2a2a2a" : "#1E1E1E"
                    Text { anchors.centerIn: parent; text: webView.loading ? "✕" : "↻"; color: "#FFF"; font.pixelSize: 16 }
                    MouseArea { id: relArea; anchors.fill: parent; onClicked: webView.loading ? webView.stop() : webView.reload() }
                }

                // URL bar
                Rectangle {
                    Layout.fillWidth: true; height: 34; radius: 8
                    color: "#1E1E1E"; border.color: urlField.activeFocus ? "#8B5CF6" : "#333"; border.width: 1
                    TextField {
                        id: urlField
                        anchors.fill: parent; anchors.margins: 6
                        text: webView.url.toString()
                        color: "#FFFFFF"; font.pixelSize: 12; background: null
                        placeholderText: "Enter URL…"; placeholderTextColor: "#555"
                        inputMethodHints: Qt.ImhUrlCharactersOnly
                        onAccepted: {
                            var u = text.trim()
                            if (!u.startsWith("http")) u = "https://" + u
                            webView.url = u
                        }
                    }
                }

                // Loading progress indicator
                Rectangle {
                    visible: webView.loading
                    width: 34; height: 34; radius: 8; color: "#1E1E1E"
                    Text { anchors.centerIn: parent; text: Math.round(webView.loadProgress) + "%"; color: "#8B5CF6"; font.pixelSize: 10 }
                }
            }
        }

        WebEngineView {
            id: webView
            Layout.fillWidth: true
            Layout.fillHeight: true
            url: root.homeUrl

            // Qt Virtual Keyboard works here automatically — no preload scripts needed
            settings.javascriptEnabled: true
            settings.pluginsEnabled:    true
        }
    }
}
