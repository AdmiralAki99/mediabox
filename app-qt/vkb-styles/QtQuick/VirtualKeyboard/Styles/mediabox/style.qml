import QtQuick
import QtQuick.VirtualKeyboard.Styles

// Nothing-themed Qt Virtual Keyboard style.
// Only defines properties that exist in Qt 6 VirtualKeyboard — symbolKey and
// hideKey were Qt 5-only and cause a fatal "non-existent property" error in Qt 6.
KeyboardStyle {
    id: currentStyle

    // ── Design canvas ─────────────────────────────────────────────────────────
    keyboardDesignWidth:          2560
    keyboardDesignHeight:          800
    keyboardRelativeLeftMargin:    80  / keyboardDesignWidth
    keyboardRelativeRightMargin:   80  / keyboardDesignWidth
    keyboardRelativeTopMargin:     20  / keyboardDesignHeight
    keyboardRelativeBottomMargin:  60  / keyboardDesignHeight

    // ── Keyboard background ───────────────────────────────────────────────────
    keyboardBackground: Rectangle {
        color: "#000000"
        Rectangle {
            anchors.top: parent.top
            width: parent.width; height: 1
            color: "#1A1A1A"
        }
    }

    // ── Normal character keys (dot-matrix) ────────────────────────────────────
    normalKey: KeyPanel {
        Rectangle {
            anchors.fill: parent; anchors.margins: 5
            radius: 6
            color: control.pressed     ? "#8B5CF6"
                 : control.highlighted ? "#1E1245"
                 : "#0E0E0E"
            border.color: control.pressed ? "#8B5CF6" : "#1C1C1C"
            border.width: 1
            Behavior on color { ColorAnimation { duration: 60 } }

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.family: "Doto"
                font.pixelSize: 48
                color: control.highlighted ? "#C4B5FD" : "#FFFFFF"
            }
        }
    }

    // ── Shift key ─────────────────────────────────────────────────────────────
    shiftKey: KeyPanel {
        Rectangle {
            anchors.fill: parent; anchors.margins: 5
            radius: 6
            color: control.pressed ? "#8B5CF6"
                 : control.checked ? "#1E1245"
                 : "#141414"
            border.color: control.checked ? "#8B5CF6" : "#1C1C1C"
            border.width: 1
            Behavior on color { ColorAnimation { duration: 60 } }

            Canvas {
                anchors.centerIn: parent
                width: 48; height: 48
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = control.checked
                        ? "#C4B5FD"
                        : (control.pressed ? "#FFFFFF" : "#888888")
                    ctx.lineWidth = 4
                    ctx.lineCap  = "round"
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    ctx.moveTo(width / 2, height * 0.78)
                    ctx.lineTo(width / 2, height * 0.32)
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.moveTo(width * 0.26, height * 0.54)
                    ctx.lineTo(width / 2,    height * 0.27)
                    ctx.lineTo(width * 0.74, height * 0.54)
                    ctx.stroke()
                }
                Component.onCompleted: requestPaint()
                Connections {
                    target: control
                    function onPressedChanged() { parent.requestPaint() }
                    function onCheckedChanged()  { parent.requestPaint() }
                }
            }
        }
    }

    // ── Backspace key ─────────────────────────────────────────────────────────
    backspaceKey: KeyPanel {
        Rectangle {
            anchors.fill: parent; anchors.margins: 5
            radius: 6
            color: control.pressed ? "#8B5CF6" : "#141414"
            border.color: "#1C1C1C"; border.width: 1
            Behavior on color { ColorAnimation { duration: 60 } }

            Canvas {
                anchors.centerIn: parent
                width: 68; height: 48
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = control.pressed ? "#FFFFFF" : "#888888"
                    ctx.lineWidth   = 4
                    ctx.lineCap     = "round"
                    ctx.lineJoin    = "round"
                    ctx.beginPath()
                    ctx.moveTo(width * 0.82, height * 0.50)
                    ctx.lineTo(width * 0.20, height * 0.50)
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.moveTo(width * 0.40, height * 0.26)
                    ctx.lineTo(width * 0.18, height * 0.50)
                    ctx.lineTo(width * 0.40, height * 0.74)
                    ctx.stroke()
                }
                Component.onCompleted: requestPaint()
                Connections {
                    target: control
                    function onPressedChanged() { parent.requestPaint() }
                }
            }
        }
    }

    // ── Enter key ─────────────────────────────────────────────────────────────
    enterKey: KeyPanel {
        Rectangle {
            anchors.fill: parent; anchors.margins: 5
            radius: 6
            color: control.pressed ? "#8B5CF6" : "#1E1245"
            border.color: "#8B5CF6"; border.width: 1
            Behavior on color { ColorAnimation { duration: 60 } }

            Text {
                anchors.centerIn: parent
                text: control.actionType === 8 ? "SEARCH"
                    : control.actionType === 4 ? "NEXT"
                    : control.actionType === 6 ? "SEND"
                    : "RETURN"
                font.family: "Doto"
                font.pixelSize: 34
                color: control.pressed ? "#FFFFFF" : "#8B5CF6"
                Behavior on color { ColorAnimation { duration: 60 } }
            }
        }
    }

    // ── Space bar ─────────────────────────────────────────────────────────────
    spaceKey: KeyPanel {
        Rectangle {
            anchors.fill: parent; anchors.margins: 5
            radius: 6
            color: control.pressed ? "#8B5CF6" : "#090909"
            border.color: "#1C1C1C"; border.width: 1
            Behavior on color { ColorAnimation { duration: 60 } }

            Rectangle {
                anchors.centerIn: parent
                width: 56; height: 2; radius: 1
                color: control.pressed ? "#FFFFFF" : "#2A2A2A"
                Behavior on color { ColorAnimation { duration: 60 } }
            }
        }
    }

    // ── Selection handles ─────────────────────────────────────────────────────
    selectionHandle: Canvas {
        implicitWidth:  20
        implicitHeight: 20
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = "#8B5CF6"
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, width / 2, 0, 2 * Math.PI)
            ctx.fill()
        }
    }

    // ── Full-screen input ─────────────────────────────────────────────────────
    fullScreenInputContainerBackground: Rectangle {
        color: "#000000"
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width; height: 1; color: "#1A1A1A"
        }
    }

    fullScreenInputBackground: Rectangle { color: "#000000" }
    fullScreenInputMargins: 20
    fullScreenInputPadding: 12

    fullScreenInputCursor: Rectangle {
        width: 2; color: "#8B5CF6"
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            NumberAnimation { to: 0;   duration: 500 }
            NumberAnimation { to: 1.0; duration: 500 }
        }
    }

    fullScreenInputFont.family:    "Doto"
    fullScreenInputFont.pixelSize: 52
}
