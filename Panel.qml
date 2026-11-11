import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Omareel in the bar. Idle: a record glyph; a click opens a menu laid out like
// Omareel's launcher: Record (full screen) or Record a window, then the sources
// (system audio, microphone, webcam), each with an on/off switch and, for the
// microphone and webcam, a device picker. Choices are saved in Omareel's own
// settings, so the launcher and `omareel record` use them too.
// Recording: the glyph turns red with the elapsed time, a click stops the
// recording (Omareel then opens the editor), and the menu offers Stop or
// Discard. Right-click always opens the menu; middle-click records the full
// screen straight away, or stops.
Panel {
  id: root
  moduleName: "omareel.recorder"
  ipcTarget: "omareel"
  manageIpc: false

  // A little air on the clock side while the timer shows, so the red dot doesn't touch it.
  readonly property real trailingGap: recording && !(bar && bar.vertical) ? Style.space(6) : 0
  implicitWidth: button.implicitWidth + trailingGap
  implicitHeight: button.implicitHeight

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // Switches that are on take the theme's popup border colour (the blue edge of this menu),
  // like Omareel's own launcher, so on and off read at a glance.
  readonly property color onColor: Commons.Color.popups.border
  readonly property color panelBackground: Commons.Color.popups.background
  // Which of the two record buttons the keyboard is on: 0 Record, 1 Window.
  property int recordChoice: 0
  // One Record button; clicking it swaps in the two ways to record.
  property bool choosingMode: false
  readonly property string tool: String(Qt.resolvedUrl("tools.sh")).replace(/^file:\/\//, "")

  // Recorder state, read from Omareel's own state file once a second.
  property bool recording: false
  property string startedUs: ""
  // Wall-clock milliseconds at which the recording started, worked out once per
  // recording from the daemon's monotonic start time.
  property real startedWallMs: 0
  property real nowMs: Date.now()

  // Omareel's saved sources and the devices found, read each time the menu opens.
  property bool systemAudio: true
  property bool microphone: true
  property string microphoneDevice: "default_input"
  property bool webcam: false
  property string webcamDevice: ""
  property var microphones: []
  property var cameras: []
  // "microphone" or "webcam" while that source's device list is unfolded.
  property string expanded: ""

  property int rowIndex: 0
  property bool cursorActive: false

  readonly property int elapsedSeconds: recording && startedWallMs > 0
    ? Math.max(0, Math.floor((nowMs - startedWallMs) / 1000)) : 0
  readonly property string elapsedText: {
    var s = elapsedSeconds
    var h = Math.floor(s / 3600)
    var m = Math.floor((s % 3600) / 60)
    var sec = s % 60
    var mm = (h > 0 && m < 10 ? "0" : "") + m
    return (h > 0 ? h + ":" : "") + mm + ":" + (sec < 10 ? "0" : "") + sec
  }

  function deviceName(list, value, fallback) {
    for (var i = 0; i < list.length; i++) if (list[i].value === value) return list[i].text
    return fallback
  }

  readonly property string microphoneName: deviceName(microphones, microphoneDevice, "Default input")
  readonly property string webcamName: cameras.length === 0 ? "No camera found" : deviceName(cameras, webcamDevice, "Camera")

  // Every line of the menu, in order. Separators are rows too, but the cursor skips them.
  readonly property var rows: {
    if (recording) return [
      { kind: "action", id: "stop", icon: "󰓛", label: "Stop and edit", hint: "Save the recording and open the editor" },
      { kind: "action", id: "cancel", icon: "󰆴", label: "Discard", hint: "Stop and throw this recording away" }
    ]
    var list = [
      { kind: "records", id: "records" },
      { kind: "separator" },
      { kind: "source", id: "systemAudio", icon: "󰕾", iconOff: "󰖁", label: "System audio", hint: "", on: systemAudio, menu: false },
      { kind: "source", id: "microphone", icon: "󰍬", iconOff: "󰍭", label: "Microphone", hint: microphoneName, on: microphone, menu: microphones.length > 0 }
    ]
    if (expanded === "microphone")
      for (var i = 0; i < microphones.length; i++)
        list.push({ kind: "device", source: "microphone", value: microphones[i].value, label: microphones[i].text, selected: microphones[i].value === microphoneDevice })
    list.push({ kind: "source", id: "webcam", icon: "󰄀", iconOff: "󰗟", label: "Webcam", hint: webcamName, on: webcam, menu: cameras.length > 0 })
    if (expanded === "webcam")
      for (var j = 0; j < cameras.length; j++)
        list.push({ kind: "device", source: "webcam", value: cameras[j].value, label: cameras[j].text, selected: cameras[j].value === webcamDevice })
    list.push({ kind: "separator" })
    list.push({ kind: "action", id: "launcher", icon: "󰒓", label: "Open Omareel", hint: "Launcher with every capture setting" })
    list.push({ kind: "action", id: "last", icon: "󰕧", label: "Edit last recording", hint: "Open the newest recording in the editor" })
    return list
  }

  function run(command) {
    if (bar) bar.run(command)
    else Quickshell.execDetached(["bash", "-lc", command])
  }

  // Saves one source setting in Omareel's settings; the menu shows it at once.
  function save(key, value) {
    Quickshell.execDetached(["bash", tool, "set", key, String(value)])
  }

  function toggleSource(id) {
    if (id === "systemAudio") { systemAudio = !systemAudio; save("systemAudio", systemAudio) }
    else if (id === "microphone") { microphone = !microphone; save("microphone", microphone) }
    else if (id === "webcam") {
      if (!webcam && cameras.length === 0) return
      webcam = !webcam
      save("webcam", webcam)
    }
  }

  function toggleExpanded(id) {
    expanded = expanded === id ? "" : id
  }

  function chooseDevice(source, value) {
    if (source === "microphone") {
      microphoneDevice = value
      save("microphoneDevice", value)
      if (!microphone) { microphone = true; save("microphone", true) }
    } else if (source === "webcam") {
      webcamDevice = value
      save("webcamDevice", value)
      if (!webcam) { webcam = true; save("webcam", true) }
    }
    expanded = ""
    rowIndex = Math.max(0, rowIndexOf(source))
  }

  // -1 is the Record button itself: it shows the choices. 0 full screen, 1 a window.
  function pickRecord(choice) {
    if (choice < 0) {
      choosingMode = true
      recordChoice = 0
      return
    }
    act(choice === 0 ? "fullscreen" : "window")
  }

  function act(id) {
    close()
    if (id === "fullscreen") run("omareel record --fullscreen")
    else if (id === "window") run("omareel record --window")
    else if (id === "launcher") run("omareel")
    else if (id === "last") run("b=$(ls -dt \"$(xdg-user-dir VIDEOS)/omareel\"/*.omareel 2>/dev/null | head -1); "
      + "if [ -n \"$b\" ]; then omareel edit \"$b\"; else omarchy-notification-send 'Omareel' 'No recordings yet'; fi")
    else if (id === "stop") run("omareel record --stop")
    else if (id === "cancel") run("omareel record --cancel")
    Qt.callLater(refresh)
  }

  function activateRow(row) {
    if (!row) return
    if (row.kind === "records") pickRecord(choosingMode ? recordChoice : -1)
    else if (row.kind === "action") act(row.id)
    else if (row.kind === "source") toggleSource(row.id)
    else if (row.kind === "device") chooseDevice(row.source, row.value)
  }

  function rowIndexOf(id) {
    for (var i = 0; i < rows.length; i++) if (rows[i].id === id) return i
    return -1
  }

  function moveCursor(dx, dy) {
    var row = rows[rowIndex]
    if (dx !== 0 && row && row.kind === "records" && choosingMode) {
      recordChoice = dx > 0 ? 1 : 0
      return
    }
    if (dx !== 0 && row && row.kind === "source" && row.menu) {
      expanded = dx > 0 ? row.id : ""
      return
    }
    if (dx < 0 && row && row.kind === "device") {
      var parentIndex = rowIndexOf(row.source)
      expanded = ""
      rowIndex = Math.max(0, parentIndex)
      return
    }
    if (dy === 0) return
    var next = rowIndex
    do { next += dy } while (next >= 0 && next < rows.length && rows[next].kind === "separator")
    if (next >= 0 && next < rows.length) rowIndex = next
  }

  function onButton(code) {
    if (code === Qt.MiddleButton) { act(recording ? "stop" : "fullscreen"); return }
    if (code === Qt.RightButton) { toggle(); return }
    if (recording) act("stop")
    else toggle()
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function readSources() {
    if (!sourcesProc.running) sourcesProc.running = true
  }

  onOpenedChanged: if (opened) {
    rowIndex = 0
    recordChoice = 0
    choosingMode = false
    cursorActive = false
    expanded = ""
    readSources()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onRecordingChanged: {
    rowIndex = 0
    expanded = ""
    if (!recording) startedWallMs = 0
  }
  onRowsChanged: if (rowIndex >= rows.length) rowIndex = Math.max(0, rows.length - 1)
  onStartedUsChanged: if (startedUs !== "" && !anchorProc.running) anchorProc.running = true

  Component.onCompleted: readSources()

  // `omarchy-shell omareel record|window|stop|cancel|toggle|status` — handy for keybindings.
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function record(): void { if (!root.recording) root.act("fullscreen") }
    function window(): void { if (!root.recording) root.act("window") }
    function stop(): void { if (root.recording) root.act("stop") }
    function cancel(): void { if (root.recording) root.act("cancel") }
    function status(): string { return root.recording ? "recording " + root.elapsedText : "idle" }
    function devices(source: string): void { root.open(); Qt.callLater(function() { root.expanded = source }) }
    function choose(): void { root.open(); Qt.callLater(function() { root.choosingMode = true }) }
  }

  // Prints "<started_us>" while Omareel's recorder daemon is alive, nothing otherwise.
  // Countdowns count from their end, so the timer starts when filming does.
  Process {
    id: statusProc
    command: ["bash", "-c",
      "f=\"${XDG_RUNTIME_DIR:-/tmp}/omareel/recording.json\"; [ -f \"$f\" ] || exit 0; "
      + "read -r pid start cd < <(jq -r '[.pid // 0, .started_us // 0, .countdown_end_us // 0] | @tsv' \"$f\" 2>/dev/null) || exit 0; "
      + "grep -qa __record-daemon \"/proc/$pid/cmdline\" 2>/dev/null || exit 0; "
      + "[ \"${cd:-0}\" -gt \"${start:-0}\" ] 2>/dev/null && start=$cd; echo \"$start\""]
    stdout: StdioCollector {
      onStreamFinished: {
        var value = String(text || "").trim()
        root.recording = /^[0-9]+$/.test(value) && value !== "0"
        root.startedUs = root.recording ? value : ""
      }
    }
  }

  // The daemon's start time is CLOCK_MONOTONIC; read that clock once to turn it into wall time.
  Process {
    id: anchorProc
    command: ["python3", "-c", "import time; print(time.monotonic_ns() // 1000)"]
    stdout: StdioCollector {
      onStreamFinished: {
        var nowUs = Number(String(text || "").trim())
        var startUs = Number(root.startedUs)
        if (isFinite(nowUs) && isFinite(startUs) && startUs > 0)
          root.startedWallMs = Date.now() - (nowUs - startUs) / 1000
      }
    }
  }

  Process {
    id: sourcesProc
    command: ["bash", root.tool, "state"]
    stdout: StdioCollector {
      onStreamFinished: {
        var state
        try { state = JSON.parse(String(text || "")) } catch (e) { return }
        if (!state || typeof state !== "object") return
        var clean = function(list) {
          if (!Array.isArray(list)) return []
          return list.slice(0, 16).filter(function(d) { return d && typeof d.value === "string" && typeof d.text === "string" })
            .map(function(d) { return { value: d.value.slice(0, 256), text: d.text.slice(0, 80) } })
        }
        root.systemAudio = state.systemAudio !== false
        root.microphone = state.microphone !== false
        root.microphoneDevice = typeof state.microphoneDevice === "string" ? state.microphoneDevice : "default_input"
        root.webcam = state.webcam === true
        root.webcamDevice = typeof state.webcamDevice === "string" ? state.webcamDevice : ""
        root.microphones = clean(state.microphones)
        root.cameras = clean(state.cameras)
      }
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.nowMs = Date.now()
      if (!root.opened) root.choosingMode = false
      root.refresh()
    }
  }

  BarIconButton {
    id: button
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: implicitWidth
    bar: root.bar
    text: root.recording ? "󰻂" : "󰻃"
    labelText: root.recording && !(root.bar && root.bar.vertical) ? root.elapsedText : ""
    active: root.recording
    tooltipText: root.recording
      ? "Recording " + root.elapsedText + " — click to stop and edit, right-click for more"
      : "Omareel — click to record"
    onPressed: function(code) { root.onButton(code) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))
    heightLive: true

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: root.activateRow(root.rows[root.cursorActive ? root.rowIndex : 0])
      onCloseRequested: {
        if (root.choosingMode) root.choosingMode = false
        else if (root.expanded !== "") root.expanded = ""
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = String(t).toLowerCase()
        if (root.recording) {
          if (key === "s") root.act("stop")
          else if (key === "d") root.act("cancel")
        } else {
          if (key === "r") root.act("fullscreen")
          else if (key === "w") root.act("window")
          else if (key === "a") root.toggleSource("systemAudio")
          else if (key === "m") root.toggleSource("microphone")
          else if (key === "c") root.toggleSource("webcam")
          else if (key === "e") root.act("last")
        }
      }

      Column {
        id: column
        x: Style.space(2)
        width: parent.width - Style.space(4)
        spacing: Style.space(10)

        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            text: root.recording ? "󰻂" : "󰕧"
            color: root.recording ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }
          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.recording ? "Recording " + root.elapsedText : "Omareel"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.rows
            Loader {
              required property var modelData
              required property int index
              width: parent.width
              sourceComponent: modelData.kind === "separator" ? separatorRow
                : modelData.kind === "records" ? recordsRow
                : (modelData.kind === "device" ? deviceRow : mainRow)
              onLoaded: {
                item.row = modelData
                item.rowIndex = index
              }
              onModelDataChanged: if (item) item.row = modelData
              onIndexChanged: if (item) item.rowIndex = index
            }
          }
        }
      }
    }
  }

  Component {
    id: separatorRow
    Item {
      property var row
      property int rowIndex
      implicitHeight: Style.space(9)
      PanelSeparator {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        foreground: root.foreground
      }
    }
  }

  // An action (Record, Open Omareel, …) or a source (System audio, Microphone, Webcam).
  Component {
    id: mainRow
    CursorSurface {
      id: mainItem
      property var row: ({})
      property int rowIndex: 0
      readonly property bool isSource: row.kind === "source"
      readonly property bool isOn: isSource ? row.on === true : true
      readonly property bool isExpanded: isSource && root.expanded === row.id

      hasCursor: root.cursorActive && root.rowIndex === rowIndex
      foreground: root.foreground
      implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: {
          root.cursorActive = true
          root.rowIndex = mainItem.rowIndex
        }
        onClicked: root.activateRow(mainItem.row)
      }

      RowLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: mainItem.isSource && !mainItem.isOn ? (mainItem.row.iconOff || "") : (mainItem.row.icon || "")
          color: mainItem.row.id === "cancel" ? root.urgent : (mainItem.isOn ? root.foreground : root.dim)
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          horizontalAlignment: Text.AlignHCenter
          Layout.preferredWidth: Style.font.heading * 1.4
          Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(1)

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: mainItem.row.label || ""
            color: mainItem.isOn ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          // The hint; for a source with devices, the chosen device, which unfolds the list.
          Item {
            visible: (mainItem.row.hint || "") !== ""
            Layout.fillWidth: true
            implicitHeight: hintRow.implicitHeight

            Row {
              id: hintRow
              spacing: Style.space(4)
              Text {
                textFormat: Text.PlainText
                width: Math.min(implicitWidth, hintRow.parent.width - (chevron.visible ? chevron.implicitWidth + hintRow.spacing : 0))
                text: mainItem.row.hint || ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
              Text {
                id: chevron
                visible: mainItem.isSource && mainItem.row.menu === true
                textFormat: Text.PlainText
                text: mainItem.isExpanded ? "󰅃" : "󰅀"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              visible: mainItem.isSource && mainItem.row.menu === true
              anchors.fill: hintRow
              anchors.margins: -Style.space(3)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: {
                root.cursorActive = true
                root.rowIndex = mainItem.rowIndex
              }
              onClicked: root.toggleExpanded(mainItem.row.id)
            }
          }
        }

        SourceSwitch {
          visible: mainItem.isSource
          checked: mainItem.isOn
          Layout.alignment: Qt.AlignVCenter
          onToggled: root.toggleSource(mainItem.row.id)
        }
      }
    }
  }

  // One camera or microphone in an unfolded list; the chosen one has a check.
  Component {
    id: deviceRow
    CursorSurface {
      id: deviceItem
      property var row: ({})
      property int rowIndex: 0

      hasCursor: root.cursorActive && root.rowIndex === rowIndex
      foreground: root.foreground
      implicitHeight: deviceContent.implicitHeight + Style.spacing.rowPaddingX * 0.6

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: {
          root.cursorActive = true
          root.rowIndex = deviceItem.rowIndex
        }
        onClicked: root.chooseDevice(deviceItem.row.source, deviceItem.row.value)
      }

      RowLayout {
        id: deviceContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10) + Style.font.heading * 1.4 + Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: deviceItem.row.label || ""
          color: deviceItem.row.selected ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          text: deviceItem.row.selected ? "󰄬" : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }

  // The two record buttons, side by side, each with Omareel's red record mark.
  Component {
    id: recordsRow
    Item {
      id: recordsItem
      property var row: ({})
      property int rowIndex: 0
      implicitHeight: Style.space(118)

      RecordTile {
        visible: !root.choosingMode
        anchors.fill: parent
        choice: -1
        label: "Record"
        hint: "Full screen or a window"
        rowIndex: recordsItem.rowIndex
      }

      RowLayout {
        visible: root.choosingMode
        anchors.fill: parent
        spacing: Style.space(8)
        RecordTile {
          Layout.fillWidth: true
          Layout.fillHeight: true
          choice: 0
          label: "Full screen"
          hint: "The whole monitor"
          glyph: "󰍹"
          rowIndex: recordsItem.rowIndex
        }
        RecordTile {
          Layout.fillWidth: true
          Layout.fillHeight: true
          choice: 1
          label: "Window"
          hint: "Click a window"
          glyph: "󰖯"
          rowIndex: recordsItem.rowIndex
        }
      }
    }
  }

  component RecordTile: CursorSurface {
    id: tile
    property int choice: 0
    property int rowIndex: 0
    property string label: ""
    property string hint: ""
    // Empty draws the launcher's white dot; otherwise this glyph sits in the red circle.
    property string glyph: ""
    readonly property bool keyed: root.cursorActive && root.rowIndex === rowIndex && (choice < 0 || root.recordChoice === choice)
    readonly property bool hot: tileMouse.containsMouse || keyed

    hasCursor: keyed
    foreground: root.foreground

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.rowIndex = tile.rowIndex
        if (tile.choice >= 0) root.recordChoice = tile.choice
      }
      onClicked: root.pickRecord(tile.choice)
    }

    Column {
      anchors.centerIn: parent
      spacing: Style.space(6)

      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Style.space(50)
        height: width

        // Halo, then the red disc, as on the launcher's record button.
        Rectangle {
          anchors.centerIn: parent
          width: parent.width
          height: width
          radius: width / 2
          color: "transparent"
          border.width: Math.max(1, Style.space(2))
          border.color: Qt.alpha(root.urgent, tile.hot ? 0.75 : 0.4)
          Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
        }
        Rectangle {
          id: disc
          anchors.centerIn: parent
          width: parent.width - Style.space(10)
          height: width
          radius: width / 2
          color: tile.hot ? Qt.lighter(root.urgent, 1.12) : root.urgent
          Behavior on color { ColorAnimation { duration: Style.duration(120) } }

          Rectangle {
            visible: tile.glyph === ""
            anchors.centerIn: parent
            width: parent.width * 0.36
            height: width
            radius: width / 2
            color: "white"
          }
          Text {
            visible: tile.glyph !== ""
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: tile.glyph
            color: "white"
            font.family: root.fontFamily
            font.pixelSize: Math.round(disc.width * 0.44)
          }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: tile.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: tile.hint
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // On: filled with the theme's popup border colour and a dark knob, like Omareel's launcher.
  // Off: an outline with a dim knob.
  component SourceSwitch: Item {
    id: sw
    property bool checked: false
    signal toggled()

    implicitWidth: Style.space(38)
    implicitHeight: Style.space(22)

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: sw.checked ? root.onColor : "transparent"
      border.width: Math.max(1, Style.space(1.5))
      border.color: sw.checked ? root.onColor : root.dim
      Behavior on color { ColorAnimation { duration: Style.duration(120) } }

      Rectangle {
        width: parent.height - Style.space(8)
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? parent.width - width - Style.space(4) : Style.space(4)
        color: sw.checked ? root.panelBackground : root.dim
        Behavior on x { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Style.duration(120) } }
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: sw.toggled()
    }
  }
}
