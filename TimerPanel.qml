import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui

Ui.Panel {
    id: root
    moduleName: "local.cycle-timer"
    manageIpc: false
    property var anchorItem: null
    property var hostWidget: null
    property var timerState: ({})
    property string errorText: ""
    property string validationError: ""
    property bool busy: false
    property bool initialized: false
    property bool minutes: false
    property bool forever: true
    property bool soundEnabled: true
    readonly property color themeAccent: bar ? bar.foreground : Color.foreground
    readonly property bool running: timerState.phase === "work" || timerState.phase === "rest"
    readonly property real phaseDuration: timerState.config ? (timerState.phase === "rest" ? timerState.config.rest : timerState.config.interval * 60) : 0
    readonly property real progress: running && phaseDuration > 0 ? Math.max(0, Math.min(1, 1 - timerState.seconds / phaseDuration)) : 0
    function displayTime() {
        var seconds = running ? (timerState.seconds || 0) : Math.max(0, Math.round(number(interval.text) * 60) || 0)
        return String(Math.floor(seconds / 60)).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0")
    }
    signal commandRequested(var args)
    function initialize(c) {
        if (initialized || !c) return
        // The form starts empty; saved daemon settings must not overwrite user input.
        soundEnabled = c.sound !== false
        initialized = true
    }
    function number(text) { return Number(text.trim().replace(",", ".")) }
    function startTimer() {
        var i = number(interval.text), r = number(rest.text), n = forever ? 0 : number(repeats.text)
        if (!message.text.trim() || !interval.text.trim() || !rest.text.trim() ||
            !isFinite(i) || i <= 0 || i > 10080 || !isFinite(r) || r < 0 || r * (minutes ? 60 : 1) > 604800 ||
            (!forever && (!repeats.text.trim() || !isFinite(n) || n < 1 || n > 100000 || Math.floor(n) !== n))) {
            validationError = "Enter a reminder, interval > 0, break ≥ 0, and a whole repeat count ≥ 1."
            return
        }
        validationError = ""
        commandRequested(["start", "--message=" + message.text.trim(), "--interval", String(i),
                          "--rest", String(r * (minutes ? 60 : 1)), "--repeats", String(n)].concat(soundEnabled ? [] : ["--silent"]))
    }
    component Caption: Text {
        color: root.themeAccent
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
    }
    component Action: Ui.Button {
        focusable: true
        bordered: selected
        foreground: root.themeAccent
        accent: root.themeAccent
        opacity: enabled ? 1 : 0.35
        Layout.fillWidth: true
    }
    component Field: Ui.TextField {
        foreground: root.themeAccent
        accent: root.themeAccent
        Layout.fillWidth: true
    }
    Ui.KeyboardPanel {
        id: popup
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: content
        contentWidth: fittedContentWidth(Style.space(400))
        contentHeight: fittedContentHeight(form.implicitHeight)
        FocusScope {
            id: content
            anchors.fill: parent
            Keys.onEscapePressed: root.close()
            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: form.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: form
                    width: parent.width
                    spacing: Style.space(10)
                    RowLayout {
                        Layout.fillWidth: true
                        Caption { text: "TIMER"; font.letterSpacing: 1.5; Layout.fillWidth: true }
                        Ui.Button { foreground: root.themeAccent; accent: root.themeAccent; text: "×"; focusable: true; onClicked: root.close() }
                    }
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Style.space(18)
                        Caption {
                            text: "\uDB81\uDD1B"
                            anchors.baseline: countdown.baseline
                            font.pixelSize: Style.space(44)
                        }
                        Caption {
                            id: countdown
                            text: root.displayTime()
                            font.pixelSize: Style.space(48)
                            font.letterSpacing: 2
                        }
                    }
                    Caption {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        opacity: 0.8
                        horizontalAlignment: Text.AlignHCenter
                        text: (root.timerState.paused ? "Pause · " : "") +
                              (root.timerState.phase === "work" ? "Until break" : root.timerState.phase === "rest" ? "Break" : "Ready to start") +
                              " · " + (root.timerState.completed || 0) + " / " +
                              (root.timerState.config && root.timerState.config.repeats ? root.timerState.config.repeats : "∞")
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: Style.space(3)
                        color: Qt.rgba(root.themeAccent.r, root.themeAccent.g, root.themeAccent.b, 0.15)
                        Rectangle { width: parent.width * root.progress; height: parent.height; color: root.themeAccent }
                    }
                    Caption { text: "Reminder" }
                    Field { id: message; Layout.fillWidth: true; maximumLength: 1000; placeholderText: "Reminder text" }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Style.space(18)
                        rowSpacing: Style.space(8)
                        Layout.topMargin: Style.space(6)
                        Caption { text: "Interval · min" }
                        Caption { text: "Break" }
                        Field {
                            id: interval
                            Layout.preferredWidth: 1
                            Layout.minimumWidth: 0
                            placeholderText: "Minutes"
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                        }
                        Field {
                            id: rest
                            Layout.preferredWidth: 1
                            Layout.minimumWidth: 0
                            placeholderText: "0 for no break"
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                        }
                        Item { Layout.fillWidth: true }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Action { text: "sec"; selected: !root.minutes; onClicked: { if (root.minutes) { if (rest.text.trim()) rest.text = String(root.number(rest.text) * 60); root.minutes = false } } }
                            Action { text: "min"; selected: root.minutes; onClicked: { if (!root.minutes) { if (rest.text.trim()) rest.text = String(root.number(rest.text) / 60); root.minutes = true } } }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Action { text: "∞ Unlimited"; selected: root.forever; onClicked: root.forever = true }
                        Action { text: "Repeat count"; selected: !root.forever; onClicked: root.forever = false }
                    }
                    RowLayout {
                        visible: !root.forever
                        Caption { text: "Repeats:" }
                        Field { id: repeats; Layout.fillWidth: true; placeholderText: "Count"; inputMethodHints: Qt.ImhDigitsOnly }
                    }
                    Action {
                        text: root.soundEnabled ? "Sound: On" : "Sound: Off"
                        selected: root.soundEnabled
                        onClicked: root.soundEnabled = !root.soundEnabled
                    }
                    Caption {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        opacity: 0.6
                        text: "Settings apply when you start"
                        font.pixelSize: Style.space(11)
                    }
                    Caption {
                        visible: text.length > 0
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.validationError || root.errorText
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Action { text: root.timerState.phase === "stopped" ? "Start" : "Restart"; selected: true; enabled: !root.busy && root.initialized; onClicked: root.startTimer() }
                        Action { text: root.timerState.paused ? "Resume" : "Pause"; enabled: !root.busy && root.running; onClicked: root.commandRequested(["toggle"]) }
                        Action { text: "Stop"; enabled: !root.busy && root.running; onClicked: root.commandRequested(["stop"]) }
                    }
                }
            }
        }
    }
}
