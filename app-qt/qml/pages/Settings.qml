import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    color: "#0A0A0A"

    property string _status: ""
    property bool   _statusOk: false

    function _loadConfig() {
        var cfg = JSON.parse(api.getConfig())
        urlField.text  = cfg.api_url      || "http://localhost:8000"
        nameField.text = cfg.display_name || ""
    }

    Component.onCompleted: _loadConfig()

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 40
        clip: true

        Column {
            id: col
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 24; anchors.rightMargin: 24
            anchors.topMargin: 32
            y: 32
            spacing: 28

            Text {
                text: "Settings"
                color: "#FFF"; font.pixelSize: 24; font.weight: Font.Bold
            }

            Column {
                width: parent.width; spacing: 12

                Text { text: "SERVER"; color: "#555"; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.5 }

                Column {
                    width: parent.width; spacing: 6

                    Text { text: "API URL"; color: "#888"; font.pixelSize: 12 }
                    TextField {
                        id: urlField
                        width: parent.width; height: 46
                        placeholderText: "http://localhost:8000"
                        background: Rectangle { color: "#141414"; radius: 10; border.color: "#2A2A2A"; border.width: 1 }
                        color: "#FFF"; font.pixelSize: 14; leftPadding: 14
                        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                    }
                    Text {
                        color: "#555"; font.pixelSize: 11
                        text: "Local: http://192.168.x.x:8000\nInternet: https://xxx.trycloudflare.com"
                        lineHeight: 1.5
                    }
                }

                // Test + Save row
                Row {
                    width: parent.width; spacing: 10

                    Rectangle {
                        width: 120; height: 42; radius: 10; color: "#1C1C1C"
                        border.color: "#2A2A2A"; border.width: 1
                        Text { anchors.centerIn: parent; text: "Test Connection"; color: "#AAA"; font.pixelSize: 12 }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root._status = "Testing…"
                                root._statusOk = false
                                var r = JSON.parse(api.testConnection())
                                if (r.ok) {
                                    root._status = "Connected ✓"
                                    root._statusOk = true
                                } else {
                                    root._status = "Failed: " + (r.error || "unknown")
                                    root._statusOk = false
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width - 130; height: 42; radius: 10; color: "#8B5CF6"
                        Text { anchors.centerIn: parent; text: "Save"; color: "#FFF"; font.pixelSize: 14; font.weight: Font.Medium }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                api.setApiUrl(urlField.text.trim())
                                root._status = "Saved ✓"
                                root._statusOk = true
                            }
                        }
                    }
                }

                // Status text
                Text {
                    visible: root._status !== ""
                    text: root._status
                    color: root._statusOk ? "#4CAF50" : "#8B5CF6"
                    font.pixelSize: 12
                }
            }

            Rectangle { width: parent.width; height: 1; color: "#1A1A1A" }

            Column {
                width: parent.width; spacing: 12

                Text { text: "PROFILE"; color: "#555"; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.5 }

                Column {
                    width: parent.width; spacing: 6
                    Text { text: "Display name"; color: "#888"; font.pixelSize: 12 }
                    TextField {
                        id: nameField
                        width: parent.width; height: 46
                        placeholderText: "Your name"
                        background: Rectangle { color: "#141414"; radius: 10; border.color: "#2A2A2A"; border.width: 1 }
                        color: "#FFF"; font.pixelSize: 14; leftPadding: 14
                    }
                }

                Rectangle {
                    width: parent.width; height: 42; radius: 10; color: "#8B5CF6"
                    Text { anchors.centerIn: parent; text: "Save"; color: "#FFF"; font.pixelSize: 14; font.weight: Font.Medium }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            api.setDisplayName(nameField.text.trim())
                            root._status = "Saved ✓"
                            root._statusOk = true
                        }
                    }
                }
            }

            Item { height: 20 }
        }
    }
}
