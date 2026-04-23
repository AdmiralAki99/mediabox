import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtMultimedia
import "../components"

Rectangle {
    id: root
    color: "#000000"

    property string streamUrl: ""
    property string referrer:  ""
    property string title:     ""
    property var    subtitles: []
    property var    stackView: null

    property bool controlsVisible: true

    // Qt 6 FFmpeg/HLS backend quirks for fMP4/CMAF streams:
    //   1. play() can't resume a paused network HLS stream — need stop()+reload.
    //   2. setPosition() freezes video because FFmpeg doesn't re-fetch the
    //      #EXT-X-MAP init segment after a seek.
    //   3. player.position doesn't advance reliably during initial CMAF playback
    //      (stays near 0 until the player has seen an explicit seek/reload).
    //
    // Workarounds:
    //   • Seeking: stop()+reload a server-trimmed manifest (_seek_ms proxy param)
    //     so FFmpeg starts at the right segment naturally — no setPosition needed.
    //   • Position tracking: wall-clock timer (_wallStart / _wallBase) so pause
    //     saves an accurate position even when player.position misbehaves.
    //   • _seekBaseMs: absolute ms of the start of the currently loaded manifest
    //     (player.position is relative to this after each reload).
    property int  _pausedAt:      -1     // absolute ms at pause/seek; -1 = playing
    property real _savedDuration:  0     // survives stop() (player.duration resets)
    property bool _seekViaReload: false  // trim-seek reload in flight
    property int  _seekBaseMs:     0     // absolute offset of current manifest start

    // Wall-clock position tracker — more reliable than player.position for CMAF.
    // Reset at each play-start event; used by _absPos().
    property double _wallStart:    0     // Date.now() when wall clock was last reset
    property int    _wallBase:     0     // _seekBaseMs value at that moment

    // Absolute position in the original stream's timeline (ms).
    // Uses wall clock when the player is actively playing (reliable for CMAF).
    function _absPos() {
        if (root._wallStart > 0 && player.playbackState === MediaPlayer.PlayingState)
            return root._wallBase + Math.max(0, Math.floor(Date.now() - root._wallStart))
        return root._seekBaseMs + player.position   // fallback
    }

    function _pause() {
        if (root._pausedAt >= 0) return
        root._pausedAt = _absPos()
        root._wallStart = 0          // stop wall clock
        player.stop()
    }

    function _play() {
        // Reload with a server-trimmed manifest starting at _pausedAt.
        // player.stop() freezes on the last frame (no black flash).
        // _seekViaReload suppresses setPosition() in onMediaStatusChanged.
        // _seekBaseMs is set now so onDurationChanged captures the right total.
        var u   = root.streamUrl
        var sep = (u.indexOf("?") >= 0) ? "&" : "?"
        var bust = sep + "_t=" + Date.now()
        if (root._pausedAt >= 0) {
            root._seekBaseMs    = root._pausedAt
            root._seekViaReload = true
            bust += "&_seek_ms=" + Math.floor(root._pausedAt)
        }
        root._wallStart = 0          // wall clock restarted at BufferedMedia
        player.stop()
        player.source = u + bust
        if (root._pausedAt >= 0)
            loadWatchdog.restart()
        player.play()
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
    }

    MediaPlayer {
        id: player
        videoOutput: videoOutput
        audioOutput: AudioOutput {}
        source: root.streamUrl
        autoPlay: true

        onErrorOccurred: (err, msg) => console.log("[player] error", err, msg)

        // _seekBaseMs is set before each reload so total = base + remaining. ✓
        onDurationChanged: {
            if (duration > 0) root._savedDuration = root._seekBaseMs + duration
        }

        onPlaybackStateChanged: {
            if (playbackState === MediaPlayer.PlayingState) {
                // Start wall clock only for plain play (not mid-seek reload).
                // For seek reloads, wall clock is reset at BufferedMedia instead,
                // after buffering delay is absorbed.
                if (!root._seekViaReload) {
                    root._wallStart = Date.now()
                    root._wallBase  = root._seekBaseMs
                }
                hideTimer.restart()
            }
        }

        // After a trim-seek reload the manifest already starts at the right
        // segment — no setPosition() needed (it freezes fMP4/CMAF video).
        onMediaStatusChanged: {
            if (root._pausedAt >= 0 && mediaStatus === MediaPlayer.BufferedMedia) {
                console.log("[player] buffered seekBase=", root._seekBaseMs,
                            " pausedAt=", root._pausedAt,
                            " seekViaReload=", root._seekViaReload)
                if (!root._seekViaReload)
                    player.setPosition(root._pausedAt)
                // Reset wall clock NOW (after buffering delay) so elapsed time
                // is counted from when the video actually starts rendering.
                root._wallStart = Date.now()
                root._wallBase  = root._seekBaseMs
                root._pausedAt      = -1
                root._seekViaReload = false
                loadWatchdog.stop()
            }
            if (mediaStatus === MediaPlayer.InvalidMedia || mediaStatus === MediaPlayer.NoMedia) {
                if (root._pausedAt >= 0) loadWatchdog.restart()
            }
        }
    }

    // Watchdog: single retry if reload hasn't buffered within 12 s.
    Timer {
        id: loadWatchdog
        interval: 12000; repeat: false
        onTriggered: {
            if (root._pausedAt < 0) return
            if (player.playbackState === MediaPlayer.PlayingState) return
            console.log("[player] watchdog retry")
            var pos = root._pausedAt
            var u   = root.streamUrl
            var sep = (u.indexOf("?") >= 0) ? "&" : "?"
            root._seekBaseMs    = pos
            root._seekViaReload = true
            root._wallStart     = 0
            player.stop()
            player.source = u + sep + "_t=" + Date.now() + "&_seek_ms=" + Math.floor(pos)
            root._pausedAt = pos
            player.play()
        }
    }

    Timer {
        id: positionTimer
        interval: 500; running: true; repeat: true
        onTriggered: {
            if (seekBar.pressed) return
            if (seekDebounce.running) return
            seekBar.value = root._pausedAt >= 0 ? root._pausedAt : _absPos()
        }
    }

    Timer {
        id: seekDebounce; interval: 400
        onTriggered: {
            var target = seekBar.value   // absolute (set from _absPos() or user drag)
            if (root._pausedAt >= 0) {
                root._pausedAt = target
            } else {
                root._pausedAt      = target
                root._seekBaseMs    = target
                root._seekViaReload = true
                root._wallStart     = 0
                var u   = root.streamUrl
                var sep = (u.indexOf("?") >= 0) ? "&" : "?"
                player.stop()
                player.source = u + sep + "_t=" + Date.now() + "&_seek_ms=" + Math.floor(target)
                loadWatchdog.restart()
                player.play()
            }
        }
    }

    Timer {
        id: hideTimer; interval: 3500
        onTriggered: root.controlsVisible = false
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.controlsVisible = !root.controlsVisible
            if (root.controlsVisible) hideTimer.restart()
        }
    }

    Rectangle {
        visible: root.controlsVisible
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: 56
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#CC000000" }
            GradientStop { position: 1.0; color: "transparent" }
        }

        BackButton {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin: 12
            onClicked: { player.stop(); root._pop() }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin: 64
            anchors.right: parent.right; anchors.rightMargin: 16
            text: root.title; color: "#FFF"; font.pixelSize: 14; font.weight: Font.Medium
            elide: Text.ElideRight
        }
    }

    Rectangle {
        visible: root.controlsVisible
        anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
        height: 64
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: "#CC000000" }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12; anchors.rightMargin: 12; anchors.bottomMargin: 10
            spacing: 10

            Text {
                text: formatTime(seekBar.value)
                color: "#FFF"; font.pixelSize: 11; font.weight: Font.Medium
            }

            Slider {
                id: seekBar
                Layout.fillWidth: true
                from: 0
                to: Math.max(root._savedDuration > 0
                             ? root._savedDuration
                             : root._seekBaseMs + player.duration, 1)
                onMoved: seekDebounce.restart()

                background: Rectangle {
                    x: seekBar.leftPadding
                    y: seekBar.topPadding + seekBar.availableHeight / 2 - height / 2
                    width: seekBar.availableWidth; height: 3; radius: 2; color: "#444"
                    Rectangle {
                        width: seekBar.visualPosition * parent.width
                        height: parent.height; radius: 2; color: "#8B5CF6"
                    }
                }
                handle: Rectangle {
                    x: seekBar.leftPadding + seekBar.visualPosition * (seekBar.availableWidth - width)
                    y: seekBar.topPadding + seekBar.availableHeight / 2 - height / 2
                    width: 14; height: 14; radius: 7; color: "#8B5CF6"
                }
            }

            Text {
                text: formatTime(root._savedDuration > 0
                                 ? root._savedDuration
                                 : root._seekBaseMs + player.duration)
                color: "#AAA"; font.pixelSize: 11
            }

            Rectangle {
                width: 34; height: 34; radius: 7; color: "#33FFFFFF"
                Text {
                    anchors.centerIn: parent
                    text: (player.playbackState === MediaPlayer.PlayingState && root._pausedAt < 0)
                          ? "⏸" : "▶"
                    color: "#FFF"; font.pixelSize: 14
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (player.playbackState === MediaPlayer.PlayingState && root._pausedAt < 0)
                            root._pause()
                        else
                            root._play()
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        hideTimer.restart()
        Qt.callLater(function() { if (root.streamUrl) player.play() })
    }

    function _pop() {
        var sv = root.stackView || root.StackView.view
        if (sv) sv.pop()
    }

    function formatTime(ms) {
        var s = Math.floor(ms / 1000)
        var m = Math.floor(s / 60); s = s % 60
        var h = Math.floor(m / 60); m = m % 60
        if (h > 0) return h + ":" + pad(m) + ":" + pad(s)
        return m + ":" + pad(s)
    }
    function pad(n) { return n < 10 ? "0" + n : "" + n }
}
