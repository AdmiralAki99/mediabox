import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#000000"   // OLED black
    signal navRequested(int pageIndex)

    property string _wxReqId:   ""
    property int    _wxTemp:    0
    property int    _wxHumidity: 0
    property int    _wxWind:    0
    property int    _wxUv:      0
    property string _wxCity:    ""
    property string _wxNextLabel: ""
    property var    _wxHourly:  []
    property int    _wxCurHour: 0
    property bool   _wxLoaded:    false
    property string _wxCondition: ""
    property string _wxSunrise:   ""
    property string _wxSunset:    ""
    property bool   _wxCelsius:   false   // toggle state

    function _toDisplay(f) {
        // Convert stored °F value to display value in current unit
        if (!root._wxCelsius) return Math.round(f)
        return Math.round((f - 32) * 5 / 9)
    }
    function _nextLabel() {
        if (!root._wxLoaded || root._wxNextLabel === "") return root._wxNextLabel
        // rebuild label with converted temp
        var raw = root._wxNextLabel   // "NEXT CHANGE · NN° AT ..."
        var match = raw.match(/·\s*(-?\d+)°/)
        if (!match) return raw
        var fVal = parseInt(match[1])
        var conv = root._toDisplay(fVal)
        return raw.replace(/·\s*(-?\d+)°/, "· " + conv + "°")
    }

    function loadWeather() {
        root._wxReqId = "home_wx_" + Date.now()
        api.fetch(root._wxReqId, "/weather", "{}")
    }

    property string _movReqId:    ""
    property string _serReqId:    ""
    property string _movTicker:   ""   // "Title A  ·  Title B  ·  ..."
    property string _serTicker:   ""

    function loadTickers() {
        root._movReqId = "home_mov_" + Date.now()
        api.fetch(root._movReqId, "/movies/trending", "{}")
        root._serReqId = "home_ser_" + Date.now()
        api.fetch(root._serReqId, "/series/trending", "{}")
    }

    property string _aniReqId:   ""
    property int    _aniToday:   0    // count of episodes airing today

    function loadAiringToday() {
        root._aniReqId = "home_ani_" + Date.now()
        api.fetch(root._aniReqId, "/anime/schedule", JSON.stringify({ offset_days: 0 }))
    }

    property string _bkReqId:    ""
    property string _bkTitle:    ""
    property string _bkAuthor:   ""

    function loadTopBook() {
        root._bkReqId = "home_bk_" + Date.now()
        api.fetch(root._bkReqId, "/books/bestsellers", JSON.stringify({ list_name: "fiction" }))
    }

    property string _histReqId: ""
    property bool   _histLoaded: false

    ListModel { id: historyModel }
    ListModel { id: readingModel }
    property bool   _readLoaded: false

    property var    _movItems:    []    // [{title, year, vote}] top 5 trending movies
    property int    _movSpotIdx:  0

    property var    _aniEntries:      []   // upcoming entries sorted by airing_at
    property string _aniCountdownStr: ""   // e.g. "1H 23M" or "LIVE NOW"
    property string _aniNextInfo:     ""   // "TITLE · EP 5"

    property real   _dayProgress: 0.0   // 0–1 position between sunrise and sunset

    function loadHistory() {
        root._histReqId = "home_hist_" + Date.now()
        api.fetch(root._histReqId, "/history", JSON.stringify({ limit: 20 }))
    }

    function _parseHours(str) {
        // "7:30 AM" → 7.5,  "6:45 PM" → 18.75
        if (!str) return -1
        var m = str.match(/(\d+):(\d+)\s*(AM|PM)/i)
        if (!m) return -1
        var h = parseInt(m[1]), mn = parseInt(m[2])
        var ap = m[3].toUpperCase()
        if (ap === "PM" && h !== 12) h += 12
        if (ap === "AM" && h === 12) h = 0
        return h + mn / 60
    }

    function _moonPhase() {
        // Returns 0.0 (new moon) → 0.5 (full moon) → 1.0 (back to new)
        var epoch = 947180040000   // known new moon: Jan 6, 2000 18:14 UTC
        var cycle = 29.53058867 * 24 * 3600 * 1000
        var age = (Date.now() - epoch) % cycle
        if (age < 0) age += cycle
        return age / cycle
    }

    function _moonLabel() {
        var p = _moonPhase()
        if (p < 0.0625 || p >= 0.9375) return "NEW MOON"
        if (p < 0.1875) return "WAX CRESCENT"
        if (p < 0.3125) return "FIRST QTR"
        if (p < 0.4375) return "WAX GIBBOUS"
        if (p < 0.5625) return "FULL MOON"
        if (p < 0.6875) return "WAN GIBBOUS"
        if (p < 0.8125) return "LAST QTR"
        return "WAN CRESCENT"
    }

    function _countdownStr(targetSecs) {
        var diffS = Math.max(0, Math.floor(targetSecs - Date.now() / 1000))
        if (diffS === 0) return "LIVE NOW"
        var hh = Math.floor(diffS / 3600)
        var mm = Math.floor((diffS % 3600) / 60)
        var ss = diffS % 60
        if (hh > 0) return hh + "H " + mm + "M"
        if (mm > 0) return mm + "M " + ss + "S"
        return ss + "S"
    }

    function timeAgo(isoStr) {
        if (!isoStr) return ""
        var then = new Date(isoStr)
        var diff = (Date.now() - then.getTime()) / 1000
        if (diff < 60)    return "NOW"
        if (diff < 3600)  return Math.floor(diff / 60) + "M"
        if (diff < 86400) return Math.floor(diff / 3600) + "H"
        return Math.floor(diff / 86400) + "D"
    }

    Connections {
        target: api
        function onFetched(id, data) {
            if (id === root._movReqId || id === root._serReqId) {
                var res = JSON.parse(data)
                var items = res.results || []
                var names = items.slice(0, 10).map(function(i) { return i.title || i.name || "" })
                var ticker = names.join("  ·  ") + "  ·  "
                // Double it so the marquee loops seamlessly
                ticker = ticker + ticker
                if (id === root._movReqId) {
                    root._movTicker = ticker
                    root._movItems = items.slice(0, 5).map(function(i) {
                        return {
                            title: i.title || i.name || "",
                            year:  (i.release_date || "").substring(0, 4),
                            vote:  i.vote_average ? i.vote_average.toFixed(1) : ""
                        }
                    })
                } else {
                    root._serTicker = ticker
                }
                return
            }
            if (id === root._aniReqId) {
                var entries = JSON.parse(data)
                if (Array.isArray(entries)) {
                    root._aniToday = entries.length
                    var now_s0 = Date.now() / 1000
                    var future = entries
                        .filter(function(e) { return e.airing_at > now_s0 - 60 })
                        .sort(function(a, b) { return a.airing_at - b.airing_at })
                    root._aniEntries = future
                }
                return
            }
            if (id === root._bkReqId) {
                var bkRes = JSON.parse(data)
                var books = bkRes.results || []
                if (books.length > 0) {
                    root._bkTitle  = books[0].title  || ""
                    root._bkAuthor = books[0].author || ""
                }
                return
            }
            if (id === root._wxReqId) {
                var wx = JSON.parse(data)
                if (wx.temp !== undefined) {
                    root._wxTemp     = wx.temp
                    root._wxHumidity = wx.humidity
                    root._wxWind     = wx.wind_mph
                    root._wxUv       = wx.uv_index
                    root._wxCity     = wx.city || ""
                    root._wxHourly   = wx.hourly_temps || []
                    root._wxCurHour  = wx.current_hour || 0
                    if (wx.next_change_hour !== null && wx.next_change_hour !== undefined) {
                        var h = wx.next_change_hour
                        var ampm = h >= 12 ? "PM" : "AM"
                        var h12  = h % 12 || 12
                        root._wxNextLabel = "NEXT CHANGE · " + wx.next_change_temp + "° AT " + h12 + ampm
                    } else {
                        root._wxNextLabel = ""
                    }
                    root._wxCondition = wx.condition  || ""
                    root._wxSunrise   = wx.sunrise    || ""
                    root._wxSunset    = wx.sunset     || ""
                    root._wxLoaded = true
                }
                return
            }
            if (id !== root._histReqId) return
            var list = JSON.parse(data)
            if (!Array.isArray(list)) return
            historyModel.clear()
            readingModel.clear()
            var wc = 0, rc = 0
            list.forEach(function(item) {
                var t = item.media_type || ""
                var isRead = (t === "manga" || t === "comic")
                if (!isRead && wc < 5) {
                    historyModel.append({
                        title:            item.title            || "Unknown",
                        media_type:       t,
                        watched_at:       item.watched_at       || "",
                        progress_seconds: item.progress_seconds || 0,
                        completed:        item.completed        || false,
                        season_num:       item.season_num       || 0,
                        episode_num:      item.episode_num      || 0,
                    })
                    wc++
                } else if (isRead && rc < 5) {
                    readingModel.append({
                        title:       item.title       || "Unknown",
                        media_type:  t,
                        watched_at:  item.watched_at  || "",
                        chapter_num: item.episode_num || 0,
                        completed:   item.completed   || false,
                    })
                    rc++
                }
            })
            root._histLoaded = historyModel.count > 0
            root._readLoaded = readingModel.count > 0
        }
    }

    Component.onCompleted: { loadHistory(); loadWeather(); loadTickers(); loadAiringToday(); loadTopBook() }

    property string _timeH:    ""   // hours part only
    property string _timeM:    ""   // minutes part only
    property string _ampm:     ""
    property string _dateStr:  ""
    property bool   _colonOn:  true
    property real   _ch: 0
    property real   _cm: 0
    property real   _cs: 0

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            var d  = new Date()
            var h  = d.getHours(), m = d.getMinutes(), s = d.getSeconds()
            root._ampm    = h >= 12 ? "PM" : "AM"
            var h12       = h % 12 || 12
            root._timeH   = String(h12)
            root._timeM   = (m < 10 ? "0" : "") + m
            root._colonOn = !root._colonOn
            var days   = ["SUNDAY","MONDAY","TUESDAY","WEDNESDAY","THURSDAY","FRIDAY","SATURDAY"]
            var months = ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"]
            root._dateStr = days[d.getDay()] + " · " + months[d.getMonth()] + " " + d.getDate()
            root._ch = h % 12 + m / 60
            root._cm = m + s / 60
            root._cs = s

            // Day progress (sunrise → sunset)
            if (root._wxSunrise !== "" && root._wxSunset !== "") {
                var riseHrs = root._parseHours(root._wxSunrise)
                var setHrs  = root._parseHours(root._wxSunset)
                var nowHrs  = h + m / 60
                if (riseHrs >= 0 && setHrs > riseHrs)
                    root._dayProgress = Math.max(0, Math.min(1, (nowHrs - riseHrs) / (setHrs - riseHrs)))
            }

            // Anime countdown (find nearest upcoming episode)
            if (root._aniEntries.length > 0) {
                var now_s = Date.now() / 1000
                var nextE = null
                for (var kk = 0; kk < root._aniEntries.length; kk++) {
                    if (root._aniEntries[kk].airing_at > now_s - 60) { nextE = root._aniEntries[kk]; break }
                }
                if (nextE) {
                    root._aniCountdownStr = root._countdownStr(nextE.airing_at)
                    var shortTitle = (nextE.title || "").toUpperCase()
                    if (shortTitle.length > 16) shortTitle = shortTitle.substring(0, 16) + "…"
                    root._aniNextInfo = shortTitle + " · EP " + (nextE.episode || "?")
                } else {
                    root._aniCountdownStr = ""; root._aniNextInfo = ""
                }
            }

            clock.requestPaint()
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + 24
        clip: true
        flickDeceleration: 700
        maximumFlickVelocity: 2800

        ScrollBar.vertical: ScrollBar {
            width: 2
            contentItem: Rectangle {
                radius: 1; color: "#FFFFFF"
                opacity: parent.active ? 0.12 : 0.0
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }
            background: Item {}
        }

        Column {
            id: col
            width: parent.width
            spacing: 0
            topPadding: 14
            bottomPadding: 24

            // Primary: time display.  Surprise: one circular element (the clock face).
            Item {
                width: col.width; height: 108
                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    anchors.topMargin: 0; anchors.bottomMargin: 6
                    color: "#111111"; radius: 12
                    border.color: "#222222"; border.width: 1

                    // Left: Doto/Space Mono time (hero moment)
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.leftMargin: 20
                        spacing: 4

                        Row {
                            spacing: 0
                            Text {
                                text: root._timeH
                                color: "#FFFFFF"; font.family: "Doto"; font.pixelSize: 46
                            }
                            Text {
                                text: ":"
                                color: "#FFFFFF"; font.family: "Doto"; font.pixelSize: 46
                                opacity: root._colonOn ? 1.0 : 0.15
                                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                            Text {
                                text: root._timeM
                                color: "#FFFFFF"; font.family: "Doto"; font.pixelSize: 46
                            }
                            Text {
                                text: " " + root._ampm
                                color: "#444444"; font.family: "Space Mono"; font.pixelSize: 11
                                font.letterSpacing: 0.5
                                anchors.baseline: parent.bottom; baselineOffset: -10
                            }
                        }
                        Text {
                            text: root._dateStr + "    " + root._moonLabel()
                            color: "#444444"
                            font.family: "Space Mono"
                            font.pixelSize: 10
                            font.letterSpacing: 0.5
                        }
                    }

                    // Right: analog clock (the ONE circular element — the surprise)
                    Canvas {
                        id: clock
                        width: 60; height: 60
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right; anchors.rightMargin: 20
                        onPaint: {
                            var ctx = getContext("2d")
                            var cx = width / 2, cy = height / 2, r = cx - 2
                            ctx.clearRect(0, 0, width, height)

                            // Sun arc: thin 24-hour ring showing sunrise→sunset window
                            if (root._wxSunrise !== "" && root._wxSunset !== "") {
                                var srH = root._parseHours(root._wxSunrise)
                                var ssH = root._parseHours(root._wxSunset)
                                if (srH >= 0 && ssH > srH) {
                                    var arcR = r - 4
                                    var srA = srH / 24 * Math.PI * 2 - Math.PI / 2
                                    var ssA = ssH / 24 * Math.PI * 2 - Math.PI / 2
                                    ctx.beginPath()
                                    ctx.arc(cx, cy, arcR, srA, ssA)
                                    ctx.strokeStyle = "#2A1C00"
                                    ctx.lineWidth = 2
                                    ctx.lineCap = "round"
                                    ctx.stroke()
                                    // Current-time dot on arc (only while daytime)
                                    var nowHr = new Date().getHours() + new Date().getMinutes() / 60
                                    if (nowHr >= srH && nowHr <= ssH) {
                                        var nowA = nowHr / 24 * Math.PI * 2 - Math.PI / 2
                                        ctx.beginPath()
                                        ctx.arc(cx + arcR * Math.cos(nowA),
                                                cy + arcR * Math.sin(nowA), 2, 0, 2 * Math.PI)
                                        ctx.fillStyle = "#7A5A00"
                                        ctx.fill()
                                    }
                                }
                            }

                            // Tick marks only — no filled face, no background
                            for (var i = 0; i < 12; i++) {
                                var a   = i * Math.PI / 6
                                var big = (i % 3 === 0)
                                ctx.beginPath()
                                ctx.moveTo(cx + (r - (big ? 7 : 5)) * Math.sin(a),
                                           cy - (r - (big ? 7 : 5)) * Math.cos(a))
                                ctx.lineTo(cx + (r - 1) * Math.sin(a),
                                           cy - (r - 1) * Math.cos(a))
                                ctx.strokeStyle = big ? "#333333" : "#1F1F1F"
                                ctx.lineWidth = big ? 1.5 : 1
                                ctx.stroke()
                            }
                            function hand(ang, len, w, col) {
                                ctx.beginPath(); ctx.moveTo(cx, cy)
                                ctx.lineTo(cx + len * Math.sin(ang), cy - len * Math.cos(ang))
                                ctx.strokeStyle = col; ctx.lineWidth = w
                                ctx.lineCap = "round"; ctx.stroke()
                            }
                            hand(root._ch * Math.PI / 6,  r * 0.44, 2.0, "#AAAAAA")
                            hand(root._cm * Math.PI / 30, r * 0.62, 1.5, "#666666")
                            hand(root._cs * Math.PI / 30, r * 0.70, 1.0, "#8B5CF6")
                            ctx.beginPath(); ctx.arc(cx, cy, 2, 0, 2 * Math.PI)
                            ctx.fillStyle = "#FFFFFF"; ctx.fill()
                        }
                    }
                }
            }

            Item {
                width: col.width; height: 230

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    anchors.topMargin: 6; anchors.bottomMargin: 0
                    color: "#111111"; radius: 12
                    border.color: "#222222"; border.width: 1

                    // Section label + city + condition
                    Row {
                        anchors.top: parent.top; anchors.left: parent.left
                        anchors.topMargin: 14; anchors.leftMargin: 18
                        spacing: 8
                        Text {
                            text: "WEATHER"
                            color: "#444444"; font.family: "Space Mono"
                            font.pixelSize: 10; font.letterSpacing: 0.8
                        }
                        Text {
                            visible: root._wxCity !== ""
                            text: "· " + root._wxCity.toUpperCase()
                            color: "#2A2A2A"; font.family: "Space Mono"
                            font.pixelSize: 10; font.letterSpacing: 0.8
                        }
                        Text {
                            visible: root._wxCondition !== ""
                            text: "· " + root._wxCondition
                            color: "#8B5CF6"; font.family: "Space Mono"
                            font.pixelSize: 10; font.letterSpacing: 0.8
                        }
                    }

                    // °F / °C toggle pill — top right
                    Rectangle {
                        anchors.top: parent.top; anchors.right: parent.right
                        anchors.topMargin: 10; anchors.rightMargin: 14
                        width: 56; height: 22; radius: 11
                        color: "#1A1A1A"; border.color: "#2A2A2A"; border.width: 1

                        Row {
                            anchors.centerIn: parent; spacing: 0

                            Repeater {
                                model: ["°F", "°C"]
                                Rectangle {
                                    width: 28; height: 22; radius: 11
                                    color: (index === 0) === !root._wxCelsius ? "#8B5CF6" : "transparent"
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Text {
                                        anchors.centerIn: parent; text: modelData
                                        font.family: "Space Mono"; font.pixelSize: 9
                                        color: (index === 0) === !root._wxCelsius ? "#FFFFFF" : "#555555"
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root._wxCelsius = (index === 1)
                                    }
                                }
                            }
                        }
                    }

                    // Big temperature — animates on unit switch
                    Row {
                        id: bigTemp
                        anchors.top: parent.top; anchors.left: parent.left
                        anchors.topMargin: 36; anchors.leftMargin: 18
                        spacing: 0

                        Text {
                            id: tempNumber
                            text: root._wxLoaded ? root._toDisplay(root._wxTemp) : "—"
                            color: "#FFFFFF"; font.family: "Space Mono"; font.pixelSize: 52

                            // Cross-fade the number when unit switches
                            Behavior on text {
                                SequentialAnimation {
                                    NumberAnimation { target: tempNumber; property: "opacity"; to: 0; duration: 100; easing.type: Easing.OutCubic }
                                    PropertyAction  {}
                                    NumberAnimation { target: tempNumber; property: "opacity"; to: 1; duration: 150; easing.type: Easing.InCubic }
                                }
                            }
                        }
                        Column {
                            anchors.bottom: parent.bottom; bottomPadding: 10; spacing: 0
                            Text { text: "°"; color: "#FFFFFF"; font.family: "Space Mono"; font.pixelSize: 22 }
                            Text {
                                text: root._wxCelsius ? "C" : "F"
                                color: "#444444"; font.family: "Space Mono"; font.pixelSize: 11
                                Behavior on text {
                                    SequentialAnimation {
                                        NumberAnimation { target: unitLabel; property: "opacity"; to: 0; duration: 100 }
                                        PropertyAction  {}
                                        NumberAnimation { target: unitLabel; property: "opacity"; to: 1; duration: 150 }
                                    }
                                }
                                id: unitLabel
                            }
                        }
                    }

                    // Next change sub-label (unit-converted)
                    Text {
                        anchors.top: bigTemp.bottom; anchors.left: parent.left
                        anchors.topMargin: 2; anchors.leftMargin: 18
                        text: root._wxLoaded ? root._nextLabel() : "LOADING…"
                        color: "#333333"; font.family: "Space Mono"
                        font.pixelSize: 9; font.letterSpacing: 0.4
                    }

                    // Right stat column
                    Column {
                        anchors.top: bigTemp.top; anchors.right: parent.right
                        anchors.rightMargin: 18
                        spacing: 10

                        Repeater {
                            model: [
                                { label: "HUMIDITY", value: root._wxLoaded ? root._wxHumidity + "%" : "—" },
                                { label: "WIND",     value: root._wxLoaded ? root._wxWind + " MPH"  : "—" },
                                { label: "UV INDEX", value: root._wxLoaded ? root._wxUv + ""        : "—" },
                            ]
                            Row {
                                spacing: 10; anchors.right: parent.right
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: "#333333"; font.family: "Space Mono"
                                    font.pixelSize: 9; font.letterSpacing: 0.5
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.value
                                    color: "#999999"; font.family: "Space Mono"
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }

                    // Sunrise / Sunset row + day progress bar
                    Item {
                        id: sunRow
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.bottomMargin: 10
                        anchors.leftMargin: 18; anchors.rightMargin: 18
                        height: 28
                        visible: root._wxSunrise !== ""

                        // Day progress bar (top half)
                        Item {
                            anchors.top: parent.top
                            anchors.left: parent.left; anchors.right: parent.right
                            height: 12

                            // Track
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left; anchors.right: parent.right
                                height: 3; radius: 2; color: "#1A1A1A"
                            }
                            // Elapsed fill
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                width: parent.width * Math.min(1, Math.max(0, root._dayProgress))
                                height: 3; radius: 2; color: "#3A2800"
                                Behavior on width { NumberAnimation { duration: 1000; easing.type: Easing.Linear } }
                            }
                            // Current-position dot
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: (parent.width - width) * Math.min(1, Math.max(0, root._dayProgress))
                                width: 7; height: 7; radius: 4
                                color: root._dayProgress > 0 && root._dayProgress < 1 ? "#8B6400" : "#222222"
                                Behavior on x { NumberAnimation { duration: 1000; easing.type: Easing.Linear } }
                            }
                        }

                        // Sunrise / sunset labels (bottom half)
                        Text {
                            anchors.left: parent.left; anchors.bottom: parent.bottom
                            text: "↑ " + root._wxSunrise
                            color: "#333333"; font.family: "Space Mono"
                            font.pixelSize: 9; font.letterSpacing: 0.5
                        }
                        Text {
                            anchors.right: parent.right; anchors.bottom: parent.bottom
                            text: "↓ " + root._wxSunset
                            color: "#333333"; font.family: "Space Mono"
                            font.pixelSize: 9; font.letterSpacing: 0.5
                        }
                    }

                    // Bar chart
                    Item {
                        id: barArea
                        anchors.bottom: sunRow.top
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.bottomMargin: 6
                        anchors.leftMargin: 14; anchors.rightMargin: 14
                        height: 56

                        property int activeBar: root._wxCurHour

                        // Normalise 24 hourly temps → bar heights 12–44px
                        property var barHeights: {
                            var temps = root._wxHourly
                            if (!temps || temps.length < 24)
                                return [20,22,24,26,28,30,32,34,36,38,40,42,40,38,36,34,32,30,28,26,24,22,20,18]
                            var mn = Math.min.apply(null, temps)
                            var mx = Math.max.apply(null, temps)
                            var rng = mx - mn || 1
                            return temps.map(function(t) { return Math.round(12 + (t - mn) / rng * 32) })
                        }

                        Row {
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 14
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 4

                            Repeater {
                                model: barArea.barHeights
                                Rectangle {
                                    width: 5; height: modelData; radius: 2
                                    anchors.bottom: parent.bottom
                                    color: index === barArea.activeBar ? "#8B5CF6" : "#1E1E1E"
                                }
                            }
                        }

                        // Hour labels aligned to real hours 0–23
                        property var hourLabels: {
                            var out = []
                            for (var i = 0; i < 24; i++) {
                                if (i % 3 === 0) {
                                    var h    = i % 12 || 12
                                    var ampm = i < 12 ? "A" : "P"
                                    out.push(h + ampm)
                                } else {
                                    out.push("")
                                }
                            }
                            return out
                        }

                        Row {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 0
                            Repeater {
                                model: barArea.hourLabels
                                Text {
                                    width: 9; text: modelData
                                    color: "#2A2A2A"; font.family: "Space Mono"
                                    font.pixelSize: 7; horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }

            // spacer
            Item { width: 1; height: 6 }

            Item {
                width: col.width; height: 150

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    spacing: 8

                    Rectangle {
                        width: (parent.width - 8) / 2; height: parent.height
                        color: "#111111"; radius: 12
                        border.color: "#222222"; border.width: 1

                        // MOVIES label (tertiary, Space Mono ALL CAPS)
                        Text {
                            anchors.top: parent.top; anchors.left: parent.left
                            anchors.topMargin: 14; anchors.leftMargin: 16
                            text: "MOVIES"
                            color: "#444444"; font.family: "Space Mono"
                            font.pixelSize: 10; font.letterSpacing: 0.8
                        }

                        // Icon (SVG asset, monochrome)
                        Image {
                            anchors.top: parent.top; anchors.right: parent.right
                            anchors.topMargin: 12; anchors.rightMargin: 14
                            source: Qt.resolvedUrl("../../assets/icons/movie_vector.svg")
                            sourceSize: Qt.size(20, 20); width: 20; height: 20
                            opacity: 0.25
                        }

                        // Primary: section name
                        Text {
                            anchors.bottom: parent.bottom; anchors.left: parent.left
                            anchors.bottomMargin: 28; anchors.leftMargin: 16
                            text: "Films"
                            color: "#FFFFFF"; font.family: "Space Grotesk"
                            font.pixelSize: 20; font.weight: Font.Medium
                        }

                        // Marquee ticker
                        Item {
                            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                            anchors.bottomMargin: 10; anchors.leftMargin: 16; anchors.rightMargin: 16
                            height: 14; clip: true
                            Text {
                                id: movTick
                                text: root._movTicker || "TRENDING  ·  NOW PLAYING  ·  UPCOMING  ·  "
                                color: "#2A2A2A"; font.family: "Space Mono"
                                font.pixelSize: 8; font.letterSpacing: 0.4
                                SequentialAnimation on x {
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0; to: -movTick.implicitWidth / 2; duration: 18000; easing.type: Easing.Linear }
                                    PropertyAction  { value: 0 }
                                }
                            }
                        }

                        scale: ma1.pressed ? 0.95 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius; color: "#FFFFFF"
                            opacity: ma1.pressed ? 0.04 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 80 } }
                        }
                        MouseArea { id: ma1; anchors.fill: parent; onClicked: root.navRequested(1) }
                    }

                    Rectangle {
                        width: (parent.width - 8) / 2; height: parent.height
                        color: "#111111"; radius: 12
                        border.color: "#222222"; border.width: 1

                        Text {
                            anchors.top: parent.top; anchors.left: parent.left
                            anchors.topMargin: 14; anchors.leftMargin: 16
                            text: "SERIES"
                            color: "#444444"; font.family: "Space Mono"
                            font.pixelSize: 10; font.letterSpacing: 0.8
                        }
                        Image {
                            anchors.top: parent.top; anchors.right: parent.right
                            anchors.topMargin: 12; anchors.rightMargin: 14
                            source: Qt.resolvedUrl("../../assets/icons/show_vector.svg")
                            sourceSize: Qt.size(20, 20); width: 20; height: 20
                            opacity: 0.25
                        }
                        Text {
                            anchors.bottom: parent.bottom; anchors.left: parent.left
                            anchors.bottomMargin: 28; anchors.leftMargin: 16
                            text: "TV Shows"
                            color: "#FFFFFF"; font.family: "Space Grotesk"
                            font.pixelSize: 20; font.weight: Font.Medium
                        }
                        // Marquee ticker
                        Item {
                            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                            anchors.bottomMargin: 10; anchors.leftMargin: 16; anchors.rightMargin: 16
                            height: 14; clip: true
                            Text {
                                id: serTick
                                text: root._serTicker || "TRENDING  ·  TOP RATED  ·  AIRING  ·  "
                                color: "#2A2A2A"; font.family: "Space Mono"
                                font.pixelSize: 8; font.letterSpacing: 0.4
                                SequentialAnimation on x {
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0; to: -serTick.implicitWidth / 2; duration: 18000; easing.type: Easing.Linear }
                                    PropertyAction  { value: 0 }
                                }
                            }
                        }

                        scale: ma2.pressed ? 0.95 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius; color: "#FFFFFF"
                            opacity: ma2.pressed ? 0.04 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 80 } }
                        }
                        MouseArea { id: ma2; anchors.fill: parent; onClicked: root.navRequested(2) }
                    }
                }
            }

            Item {
                width: col.width; height: 96
                visible: root._movItems.length > 0

                // Auto-rotate every 8 s
                Timer {
                    interval: 8000; running: root._movItems.length > 1; repeat: true
                    onTriggered: root._movSpotIdx = (root._movSpotIdx + 1) % root._movItems.length
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    anchors.topMargin: 8
                    color: "#111111"; radius: 12
                    border.color: "#222222"; border.width: 1
                    clip: true

                    // Label + position dots
                    Row {
                        anchors.top: parent.top; anchors.left: parent.left
                        anchors.topMargin: 14; anchors.leftMargin: 16
                        spacing: 10
                        Text {
                            text: "TRENDING NOW"
                            color: "#444444"; font.family: "Space Mono"
                            font.pixelSize: 10; font.letterSpacing: 0.8
                        }
                        Row {
                            spacing: 4; anchors.verticalCenter: parent.verticalCenter
                            Repeater {
                                model: root._movItems.length
                                Rectangle {
                                    width: index === root._movSpotIdx ? 12 : 4
                                    height: 4; radius: 2
                                    color: index === root._movSpotIdx ? "#8B5CF6" : "#222222"
                                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 300 } }
                                }
                            }
                        }
                    }

                    // Primary: film title
                    Text {
                        anchors.bottom: parent.bottom; anchors.left: parent.left
                        anchors.right: spotMeta.left
                        anchors.bottomMargin: 12; anchors.leftMargin: 16; anchors.rightMargin: 8
                        text: root._movItems.length > root._movSpotIdx
                              ? root._movItems[root._movSpotIdx].title : ""
                        color: "#FFFFFF"; font.family: "Space Grotesk"
                        font.pixelSize: 18; font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    // Secondary: year + rating (right-aligned)
                    Column {
                        id: spotMeta
                        anchors.bottom: parent.bottom; anchors.right: parent.right
                        anchors.bottomMargin: 12; anchors.rightMargin: 16
                        spacing: 3
                        Text {
                            anchors.right: parent.right
                            text: root._movItems.length > root._movSpotIdx
                                  ? root._movItems[root._movSpotIdx].year : ""
                            color: "#444444"; font.family: "Space Mono"; font.pixelSize: 9
                        }
                        Text {
                            anchors.right: parent.right
                            visible: root._movItems.length > root._movSpotIdx &&
                                     root._movItems[root._movSpotIdx].vote !== ""
                            text: root._movItems.length > root._movSpotIdx
                                  ? "★ " + root._movItems[root._movSpotIdx].vote : ""
                            color: "#555555"; font.family: "Space Mono"; font.pixelSize: 9
                        }
                    }

                    scale: maSpot.pressed ? 0.97 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: "#FFFFFF"
                        opacity: maSpot.pressed ? 0.03 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 80 } }
                    }
                    MouseArea { id: maSpot; anchors.fill: parent; onClicked: root.navRequested(1) }
                }
            }

            Item {
                width: col.width; height: 112

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    anchors.topMargin: 8
                    color: "#111111"; radius: 12
                    border.color: "#222222"; border.width: 1

                    // Label + live dot + airing count
                    Row {
                        anchors.top: parent.top; anchors.left: parent.left
                        anchors.topMargin: 14; anchors.leftMargin: 16
                        spacing: 8

                        Text {
                            text: "ANIME"
                            color: "#444444"; font.family: "Space Mono"
                            font.pixelSize: 10; font.letterSpacing: 0.8
                        }

                        // Pulsing live dot
                        Rectangle {
                            width: 5; height: 5; radius: 3; color: "#8B5CF6"
                            anchors.verticalCenter: parent.verticalCenter
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.2; duration: 900; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            visible: root._aniToday > 0
                            Text {
                                text: root._aniToday + " AIRING TODAY"
                                color: "#555555"; font.family: "Space Mono"
                                font.pixelSize: 9; font.letterSpacing: 0.5
                            }
                            Text {
                                visible: root._aniCountdownStr !== ""
                                text: "NEXT · " + root._aniNextInfo + " · " + root._aniCountdownStr
                                color: "#6B46C1"; font.family: "Space Mono"
                                font.pixelSize: 8; font.letterSpacing: 0.3
                            }
                        }
                    }

                    // SUB / DUB toggle — a real control, styled Nothing way
                    Row {
                        anchors.top: parent.top; anchors.right: parent.right
                        anchors.topMargin: 12; anchors.rightMargin: 14
                        spacing: 0

                        Rectangle {
                            width: 64; height: 22; radius: 4; color: "#1A1A1A"
                            border.color: "#2A2A2A"; border.width: 1

                            Row {
                                anchors.centerIn: parent; spacing: 0
                                Rectangle {
                                    width: 30; height: 16; radius: 3; color: "#2E2E2E"
                                    Text { anchors.centerIn: parent; text: "SUB"
                                        color: "#CCCCCC"; font.family: "Space Mono"
                                        font.pixelSize: 8; font.letterSpacing: 0.5 }
                                }
                                Item { width: 4; height: 1 }
                                Rectangle {
                                    width: 30; height: 16; radius: 3; color: "transparent"
                                    Text { anchors.centerIn: parent; text: "DUB"
                                        color: "#333333"; font.family: "Space Mono"
                                        font.pixelSize: 8; font.letterSpacing: 0.5 }
                                }
                            }
                        }
                    }

                    // Icon + primary text, left-anchored bottom
                    Row {
                        anchors.bottom: parent.bottom; anchors.left: parent.left
                        anchors.bottomMargin: 16; anchors.leftMargin: 16
                        spacing: 14

                        Image {
                            source: Qt.resolvedUrl("../../assets/icons/anime_vector.svg")
                            sourceSize: Qt.size(28, 28); width: 28; height: 28
                            opacity: 0.20; anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter; spacing: 3
                            Text {
                                text: "Japanese Animation"
                                color: "#FFFFFF"; font.family: "Space Grotesk"
                                font.pixelSize: 18; font.weight: Font.Medium
                            }
                            Text {
                                text: "Stream subbed & dubbed series"
                                color: "#444444"; font.family: "Space Grotesk"
                                font.pixelSize: 11
                            }
                        }
                    }

                    scale: ma3.pressed ? 0.97 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: "#FFFFFF"
                        opacity: ma3.pressed ? 0.03 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 80 } }
                    }
                    MouseArea { id: ma3; anchors.fill: parent; onClicked: root.navRequested(3) }
                }
            }

            Item {
                width: col.width; height: 128

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    anchors.topMargin: 8
                    spacing: 8

                    Rectangle {
                        width: (parent.width - 8) / 2; height: parent.height
                        color: "#111111"; radius: 12
                        border.color: "#222222"; border.width: 1

                        Text {
                            anchors.top: parent.top; anchors.left: parent.left
                            anchors.topMargin: 14; anchors.leftMargin: 14
                            text: "MANGA"
                            color: "#444444"; font.family: "Space Mono"
                            font.pixelSize: 10; font.letterSpacing: 0.8
                        }
                        Image {
                            anchors.top: parent.top; anchors.right: parent.right
                            anchors.topMargin: 12; anchors.rightMargin: 12
                            source: Qt.resolvedUrl("../../assets/icons/manga_vector.svg")
                            sourceSize: Qt.size(18, 18); width: 18; height: 18
                            opacity: 0.25
                        }
                        Text {
                            anchors.bottom: parent.bottom; anchors.left: parent.left
                            anchors.bottomMargin: 26; anchors.leftMargin: 14
                            text: "MangaDex"
                            color: "#FFFFFF"; font.family: "Space Grotesk"
                            font.pixelSize: 17; font.weight: Font.Medium
                        }
                        Text {
                            anchors.bottom: parent.bottom; anchors.left: parent.left
                            anchors.bottomMargin: 13; anchors.leftMargin: 14
                            text: "Chapters & volumes"
                            color: "#444444"; font.family: "Space Grotesk"; font.pixelSize: 10
                        }

                        scale: ma4.pressed ? 0.95 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius; color: "#FFFFFF"
                            opacity: ma4.pressed ? 0.04 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 80 } }
                        }
                        MouseArea { id: ma4; anchors.fill: parent; onClicked: root.navRequested(4) }
                    }

                    Rectangle {
                        width: (parent.width - 8) / 2; height: parent.height
                        color: "#111111"; radius: 12
                        border.color: "#222222"; border.width: 1

                        Text {
                            anchors.top: parent.top; anchors.left: parent.left
                            anchors.topMargin: 14; anchors.leftMargin: 14
                            text: "COMICS"
                            color: "#444444"; font.family: "Space Mono"
                            font.pixelSize: 10; font.letterSpacing: 0.8
                        }
                        Image {
                            anchors.top: parent.top; anchors.right: parent.right
                            anchors.topMargin: 12; anchors.rightMargin: 12
                            source: Qt.resolvedUrl("../../assets/icons/comics_vector.svg")
                            sourceSize: Qt.size(18, 18); width: 18; height: 18
                            opacity: 0.25
                        }
                        Text {
                            anchors.bottom: parent.bottom; anchors.left: parent.left
                            anchors.bottomMargin: 26; anchors.leftMargin: 14
                            text: "Comick"
                            color: "#FFFFFF"; font.family: "Space Grotesk"
                            font.pixelSize: 17; font.weight: Font.Medium
                        }
                        Text {
                            anchors.bottom: parent.bottom; anchors.left: parent.left
                            anchors.bottomMargin: 13; anchors.leftMargin: 14
                            text: "Western comics"
                            color: "#444444"; font.family: "Space Grotesk"; font.pixelSize: 10
                        }

                        scale: ma5.pressed ? 0.95 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius; color: "#FFFFFF"
                            opacity: ma5.pressed ? 0.04 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 80 } }
                        }
                        MouseArea { id: ma5; anchors.fill: parent; onClicked: root.navRequested(5) }
                    }
                }
            }

            Item {
                width: col.width
                height: root._histLoaded && historyModel.count > 0 ? (52 + historyModel.count * 58) : 0
                visible: height > 0

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    anchors.topMargin: 8
                    color: "#111111"; radius: 12
                    border.color: "#222222"; border.width: 1

                    // Section label
                    Text {
                        id: cwLabel
                        anchors.top: parent.top; anchors.left: parent.left
                        anchors.topMargin: 14; anchors.leftMargin: 16
                        text: "CONTINUE WATCHING"
                        color: "#444444"; font.family: "Space Mono"
                        font.pixelSize: 10; font.letterSpacing: 0.8
                    }

                    // Chevron to history
                    Text {
                        anchors.top: parent.top; anchors.right: parent.right
                        anchors.topMargin: 12; anchors.rightMargin: 16
                        text: "›"; color: "#333333"; font.pixelSize: 18
                        MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: root.navRequested(9) }
                    }

                    // List
                    ListView {
                        id: cwList
                        anchors.top: cwLabel.bottom; anchors.topMargin: 8
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                        clip: true; model: historyModel; spacing: 0; interactive: false

                        delegate: Item {
                            width: parent ? parent.width : 0; height: 58

                            // In-progress left accent bar
                            Rectangle {
                                anchors.left: parent.left; anchors.leftMargin: 0
                                anchors.top: parent.top; anchors.topMargin: 8
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                                width: 3; radius: 2
                                color: model.completed ? "#2A2A2A" : "#8B5CF6"
                                opacity: model.completed ? 0.5 : 1.0
                            }

                            // Content: left of chevron
                            Column {
                                anchors.left: parent.left; anchors.leftMargin: 14
                                anchors.right: chevron.left; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5

                                // Top row: type tag + title
                                Row {
                                    width: parent.width; spacing: 8
                                    Text {
                                        text: {
                                            var t = model.media_type
                                            if (t === "movie")  return "FILM"
                                            if (t === "series") return "TV"
                                            if (t === "anime")  return "ANIME"
                                            if (t === "manga")  return "MANGA"
                                            if (t === "comic")  return "COMIC"
                                            if (t === "book")   return "BOOK"
                                            return "–"
                                        }
                                        color: model.completed ? "#333333" : "#8B5CF6"
                                        font.family: "Space Mono"; font.pixelSize: 9
                                        font.letterSpacing: 0.5
                                    }
                                    Text {
                                        width: parent.width - 50
                                        text: model.title
                                        color: "#CCCCCC"; font.family: "Space Grotesk"
                                        font.pixelSize: 13; elide: Text.ElideRight
                                    }
                                }

                                // Bottom row: progress time + episode + time-ago
                                Row {
                                    width: parent.width; spacing: 10
                                    Text {
                                        visible: model.progress_seconds > 0
                                        text: {
                                            var s = model.progress_seconds
                                            var m = Math.floor(s / 60)
                                            var h = Math.floor(m / 60)
                                            if (h > 0) return h + "H " + (m % 60) + "M IN"
                                            return m + " MIN IN"
                                        }
                                        color: "#555555"; font.family: "Space Mono"
                                        font.pixelSize: 9; font.letterSpacing: 0.3
                                    }
                                    Text {
                                        visible: (model.season_num > 0 || model.episode_num > 0)
                                        text: {
                                            if (model.season_num > 0 && model.episode_num > 0)
                                                return "S" + model.season_num + "E" + model.episode_num
                                            if (model.episode_num > 0)
                                                return "EP " + model.episode_num
                                            return ""
                                        }
                                        color: "#444444"; font.family: "Space Mono"
                                        font.pixelSize: 9; font.letterSpacing: 0.3
                                    }
                                    Text {
                                        text: root.timeAgo(model.watched_at)
                                        color: "#333333"; font.family: "Space Mono"
                                        font.pixelSize: 9; font.letterSpacing: 0.3
                                    }
                                }
                            }

                            // Chevron
                            Text {
                                id: chevron
                                anchors.right: parent.right; anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                text: "›"; color: "#2A2A2A"; font.pixelSize: 18
                            }

                            // Row divider
                            Rectangle {
                                visible: index < historyModel.count - 1
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left; anchors.leftMargin: 14
                                anchors.right: parent.right; anchors.rightMargin: 14
                                height: 1; color: "#1A1A1A"
                            }
                        }
                    }
                }
            }

            Item {
                width: col.width
                height: root._readLoaded && readingModel.count > 0 ? (52 + readingModel.count * 58) : 0
                visible: height > 0

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    anchors.topMargin: 8
                    color: "#111111"; radius: 12
                    border.color: "#222222"; border.width: 1

                    Text {
                        id: crLabel
                        anchors.top: parent.top; anchors.left: parent.left
                        anchors.topMargin: 14; anchors.leftMargin: 16
                        text: "CONTINUE READING"
                        color: "#444444"; font.family: "Space Mono"
                        font.pixelSize: 10; font.letterSpacing: 0.8
                    }
                    Text {
                        anchors.top: parent.top; anchors.right: parent.right
                        anchors.topMargin: 12; anchors.rightMargin: 16
                        text: "›"; color: "#333333"; font.pixelSize: 18
                        MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: root.navRequested(9) }
                    }

                    ListView {
                        anchors.top: crLabel.bottom; anchors.topMargin: 8
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                        clip: true; model: readingModel; spacing: 0; interactive: false

                        delegate: Item {
                            width: parent ? parent.width : 0; height: 58

                            Rectangle {
                                anchors.left: parent.left; anchors.leftMargin: 0
                                anchors.top: parent.top; anchors.topMargin: 8
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                                width: 3; radius: 2
                                color: model.completed ? "#2A2A2A" : "#8B5CF6"
                                opacity: model.completed ? 0.5 : 1.0
                            }

                            Column {
                                anchors.left: parent.left; anchors.leftMargin: 14
                                anchors.right: crChevron.left; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5

                                Row {
                                    width: parent.width; spacing: 8
                                    Text {
                                        text: model.media_type === "manga" ? "MANGA" : "COMIC"
                                        color: model.completed ? "#333333" : "#8B5CF6"
                                        font.family: "Space Mono"; font.pixelSize: 9
                                        font.letterSpacing: 0.5
                                    }
                                    Text {
                                        width: parent.width - 60
                                        text: model.title
                                        color: "#CCCCCC"; font.family: "Space Grotesk"
                                        font.pixelSize: 13; elide: Text.ElideRight
                                    }
                                }
                                Row {
                                    width: parent.width; spacing: 10
                                    Text {
                                        visible: model.chapter_num > 0
                                        text: "CH " + model.chapter_num
                                        color: "#555555"; font.family: "Space Mono"
                                        font.pixelSize: 9; font.letterSpacing: 0.3
                                    }
                                    Text {
                                        text: root.timeAgo(model.watched_at)
                                        color: "#333333"; font.family: "Space Mono"
                                        font.pixelSize: 9; font.letterSpacing: 0.3
                                    }
                                }
                            }

                            Text {
                                id: crChevron
                                anchors.right: parent.right; anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                text: "›"; color: "#2A2A2A"; font.pixelSize: 18
                            }

                            Rectangle {
                                visible: index < readingModel.count - 1
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left; anchors.leftMargin: 14
                                anchors.right: parent.right; anchors.rightMargin: 14
                                height: 1; color: "#1A1A1A"
                            }
                        }
                    }
                }
            }

            Item {
                width: col.width; height: 140

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    anchors.topMargin: 8
                    color: "#111111"; radius: 12
                    border.color: "#222222"; border.width: 1

                    Text {
                        id: booksLabel
                        anchors.top: parent.top; anchors.left: parent.left
                        anchors.topMargin: 14; anchors.leftMargin: 16
                        text: "BOOKS"
                        color: "#444444"; font.family: "Space Mono"
                        font.pixelSize: 10; font.letterSpacing: 0.8
                    }
                    Image {
                        anchors.top: parent.top; anchors.right: parent.right
                        anchors.topMargin: 12; anchors.rightMargin: 14
                        source: Qt.resolvedUrl("../../assets/icons/books_vector.svg")
                        sourceSize: Qt.size(20, 20); width: 20; height: 20
                        opacity: 0.20
                    }

                    Column {
                        anchors.top: booksLabel.bottom; anchors.topMargin: 8
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.leftMargin: 16; anchors.rightMargin: 16
                        spacing: 4

                        Text {
                            text: "NYT #1 FICTION"
                            color: "#2A2A2A"; font.family: "Space Mono"
                            font.pixelSize: 9; font.letterSpacing: 0.6
                        }
                        Text {
                            width: parent.width
                            text: root._bkTitle || "Loading…"
                            color: root._bkTitle ? "#FFFFFF" : "#333333"
                            font.family: "Space Grotesk"; font.pixelSize: 17
                            font.weight: Font.Medium; elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: 400 } }
                        }
                        Text {
                            text: root._bkAuthor
                            color: "#555555"; font.family: "Space Mono"
                            font.pixelSize: 9; font.letterSpacing: 0.4
                            visible: root._bkAuthor !== ""
                        }
                    }

                    scale: ma6.pressed ? 0.97 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: "#FFFFFF"
                        opacity: ma6.pressed ? 0.03 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 80 } }
                    }
                    MouseArea { id: ma6; anchors.fill: parent; onClicked: root.navRequested(6) }
                }
            }

            Item {
                width: col.width; height: 128

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    anchors.topMargin: 8
                    spacing: 8

                    Rectangle {
                        width: (parent.width - 8) / 2; height: parent.height
                        color: "#111111"; radius: 12
                        border.color: "#222222"; border.width: 1

                        Text {
                            anchors.top: parent.top; anchors.left: parent.left
                            anchors.topMargin: 14; anchors.leftMargin: 14
                            text: "PAPERS"
                            color: "#444444"; font.family: "Space Mono"
                            font.pixelSize: 10; font.letterSpacing: 0.8
                        }
                        Image {
                            anchors.top: parent.top; anchors.right: parent.right
                            anchors.topMargin: 12; anchors.rightMargin: 12
                            source: Qt.resolvedUrl("../../assets/icons/research_paper_vector.svg")
                            sourceSize: Qt.size(18, 18); width: 18; height: 18
                            opacity: 0.25
                        }
                        Text {
                            anchors.bottom: parent.bottom; anchors.left: parent.left
                            anchors.bottomMargin: 26; anchors.leftMargin: 14
                            text: "arXiv"
                            color: "#FFFFFF"; font.family: "Space Grotesk"
                            font.pixelSize: 17; font.weight: Font.Medium
                        }
                        Text {
                            anchors.bottom: parent.bottom; anchors.left: parent.left
                            anchors.bottomMargin: 13; anchors.leftMargin: 14
                            text: "Research papers"
                            color: "#444444"; font.family: "Space Grotesk"; font.pixelSize: 10
                        }

                        scale: ma7.pressed ? 0.95 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius; color: "#FFFFFF"
                            opacity: ma7.pressed ? 0.04 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 80 } }
                        }
                        MouseArea { id: ma7; anchors.fill: parent; onClicked: root.navRequested(7) }
                    }

                    Rectangle {
                        width: (parent.width - 8) / 2; height: parent.height
                        color: "#111111"; radius: 12
                        border.color: "#222222"; border.width: 1

                        Text {
                            anchors.top: parent.top; anchors.left: parent.left
                            anchors.topMargin: 14; anchors.leftMargin: 14
                            text: "HISTORY"
                            color: "#444444"; font.family: "Space Mono"
                            font.pixelSize: 10; font.letterSpacing: 0.8
                        }
                        Image {
                            anchors.top: parent.top; anchors.right: parent.right
                            anchors.topMargin: 12; anchors.rightMargin: 12
                            source: Qt.resolvedUrl("../../assets/icons/history_vector.svg")
                            sourceSize: Qt.size(18, 18); width: 18; height: 18
                            opacity: 0.25
                        }
                        // Total watch time — computed from loaded history
                        Text {
                            anchors.bottom: parent.bottom; anchors.left: parent.left
                            anchors.bottomMargin: 30; anchors.leftMargin: 14
                            text: {
                                var secs = 0
                                for (var i = 0; i < historyModel.count; i++)
                                    secs += historyModel.get(i).progress_seconds || 0
                                var h = Math.floor(secs / 3600)
                                var m = Math.floor((secs % 3600) / 60)
                                if (h > 0) return h + "H " + m + "M"
                                return m + " MIN"
                            }
                            color: "#FFFFFF"; font.family: "Space Mono"
                            font.pixelSize: 22; font.weight: Font.Bold
                            visible: root._histLoaded && historyModel.count > 0
                        }
                        Text {
                            anchors.bottom: parent.bottom; anchors.left: parent.left
                            anchors.bottomMargin: 14; anchors.leftMargin: 14
                            text: "WATCHED"
                            color: "#444444"; font.family: "Space Mono"
                            font.pixelSize: 9; font.letterSpacing: 0.6
                        }

                        scale: ma8.pressed ? 0.95 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius; color: "#FFFFFF"
                            opacity: ma8.pressed ? 0.04 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 80 } }
                        }
                        MouseArea { id: ma8; anchors.fill: parent; onClicked: root.navRequested(9) }
                    }
                }
            }

            Item {
                width: col.width; height: 60

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    anchors.topMargin: 8
                    color: "#111111"; radius: 8
                    border.color: "#1A1A1A"; border.width: 1

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.leftMargin: 16
                        spacing: 12

                        Image {
                            source: Qt.resolvedUrl("../../assets/icons/browser.svg")
                            sourceSize: Qt.size(18, 18); width: 18; height: 18
                            opacity: 0.20; anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter; spacing: 2
                            Text {
                                text: "BROWSER"
                                color: "#444444"; font.family: "Space Mono"
                                font.pixelSize: 10; font.letterSpacing: 0.8
                            }
                            Text {
                                text: "Open any URL"
                                color: "#666666"; font.family: "Space Grotesk"; font.pixelSize: 12
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right; anchors.rightMargin: 16
                        text: "›"; color: "#2A2A2A"; font.pixelSize: 20
                    }

                    scale: ma9.pressed ? 0.97 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: "#FFFFFF"
                        opacity: ma9.pressed ? 0.03 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 80 } }
                    }
                    MouseArea { id: ma9; anchors.fill: parent; onClicked: root.navRequested(9) }
                }
            }
        }
    }
}
