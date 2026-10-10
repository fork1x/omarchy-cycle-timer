import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui

Ui.BarWidget {
    id: root
    moduleName: "local.cycle-timer"
    property string script: decodeURIComponent(Qt.resolvedUrl("timer.py").toString().replace(/^file:\/\//, ""))
    property var timerState: ({phase: "stopped", paused: false, text: "◷ Timer", completed: 0})
    property string errorText: ""
    readonly property bool opened: panel.opened
    readonly property bool popoutSwitchClosing: panel.popoutSwitchClosing
    function open() { panel.open() }
    function close() { panel.close() }
    function closeForPopoutSwitch() { panel.closeForPopoutSwitch() }
    function refresh() { if (!poll.running && !action.running) poll.running = true }
    function execute(args) {
        if (action.running) return
        errorText = ""
        action.command = ["python3", script].concat(args)
        action.running = true
    }
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    Process {
        id: poll
        command: ["python3", root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.timerState = JSON.parse(text); panel.initialize(root.timerState.config) }
                catch (e) { root.errorText = "Could not read timer status" }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.errorText = text.trim() }
    }
    Process {
        id: action
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.timerState = JSON.parse(text) } catch (e) { }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.errorText = text.trim() }
        onExited: root.refresh()
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
    Ui.WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.timerState.phase === "stopped" ? "" : String(Math.floor((root.timerState.seconds || 0) / 60)).padStart(2, "0") + ":" + String((root.timerState.seconds || 0) % 60).padStart(2, "0")
        labelVisible: false
        hasVisualContent: true
        fixedWidth: barContents.implicitWidth + Style.space(16)
        Row {
            id: barContents
            anchors.centerIn: parent
            spacing: Style.space(6)
            Text {
                text: "\uDB81\uDD1B"
                font.family: button.fontFamily
                font.pixelSize: Style.bar.iconFont
                color: button.foreground
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: button.text.length > 0
                text: (root.timerState.paused ? "Ⅱ " : "") + button.text
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
                color: button.foreground
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        horizontalMargin: 8
        onPressed: b => {
            if (b === Qt.RightButton) root.execute(["toggle"])
            else if (b === Qt.MiddleButton) root.execute(["stop"])
            else panel.toggle()
        }
    }
    TimerPanel {
        id: panel
        bar: root.bar
        anchorItem: button
        hostWidget: root
        timerState: root.timerState
        errorText: root.errorText
        busy: action.running
        onCommandRequested: args => root.execute(args)
    }
}
