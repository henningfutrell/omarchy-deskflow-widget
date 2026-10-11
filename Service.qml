import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool running: false
  property bool autostart: false
  property string host: ""
  property string screenName: ""
  property var clients: []
  property string connectionState: "stopped"
  property string lastError: ""

  readonly property string mode: setting("mode", "client") === "server" ? "server" : "client"
  readonly property bool isServer: mode === "server"
  readonly property string unit: Model.unitName(mode)

  // Optimistic run state so the switch throws the instant it is clicked:
  // -1 follows the real unit state, 0/1 while a stop/start is catching up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  readonly property bool connected: active && connectionState === "connected"
  readonly property bool busy: controlProcess.running
  readonly property string statusText: _desired === 1 && !running ? "Starting…" : Model.stateText(connectionState, host, clients)

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 5, 2, 300)

  // The plugin carries its own systemd template, so copying the plugin folder
  // to another machine is all it takes; it is installed on first start.
  readonly property string unitSource: decodeURIComponent(String(Qt.resolvedUrl("deskflow@.service")).replace(/^file:\/\//, ""))
  readonly property string installUnit: "dest=\"${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/deskflow@.service\"; "
    + "cmp -s \"$1\" \"$dest\" || { install -Dm644 \"$1\" \"$dest\" && systemctl --user daemon-reload; }"

  // One probe for everything the widget shows. Deskflow keeps its settings in
  // a QSettings INI file; the journal of the unit's current run tells us who
  // is connected.
  readonly property string probeScript: [
    "unit=" + unit,
    "conf=\"${XDG_CONFIG_HOME:-$HOME/.config}/Deskflow/Deskflow.conf\"",
    "ini() { [ -f \"$conf\" ] && awk -F= -v s=\"[$1]\" -v k=\"$2\" '$0==s{f=1;next} /^\\[/{f=0} f&&$1==k{sub(/^[^=]*=/,\"\");print;exit}' \"$conf\"; }",
    "command -v deskflow-core >/dev/null && echo installed=1 || echo installed=0",
    "state=$(systemctl --user is-active $unit 2>/dev/null); echo active=$state",
    "echo enabled=$(systemctl --user is-enabled $unit 2>/dev/null)",
    "echo host=$(ini client remoteHost)",
    "echo screen=$(ini core screenName)",
    "since=$(systemctl --user show -p ExecMainStartTimestamp --value --timestamp=unix $unit 2>/dev/null)",
    "[ \"$state\" = active ] && [ -n \"$since\" ] && journalctl --user -u $unit --since \"$since\" -o cat --no-pager 2>/dev/null"
      + " | grep -iE 'connected|failed to' | tail -n 500 | sed 's/^/log=/'",
    "true"
  ].join("\n")

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw, mode)
    installed = parsed.installed
    running = parsed.running
    autostart = parsed.autostart
    host = parsed.host
    screenName = parsed.screenName
    clients = parsed.clients
    connectionState = parsed.state
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
  }

  function start() { runSystemctl("start " + unit, 1) }
  function stop() { runSystemctl("stop " + unit, 0) }

  function toggleRunning() {
    if (active) stop()
    else start()
  }

  function toggleAutostart() {
    runSystemctl((autostart ? "disable " : "enable ") + unit, -1)
  }

  function runSystemctl(args, desired) {
    if (!installed || controlProcess.running) return
    _desired = desired
    lastError = ""
    controlProcess.command = ["sh", "-c", installUnit + " && systemctl --user " + args, "deskflow", unitSource]
    controlProcess.running = true
  }

  // The GUI owns setup: mode, server address or screen layout, and TLS
  // fingerprints. Stop the background unit so the two don't fight over it.
  function openSettings() {
    if (running) stop()
    Quickshell.execDetached(["uwsm-app", "--", "deskflow"])
  }

  onModeChanged: {
    _desired = -1
    clients = []
    refresh()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    // The connection settles a moment after the unit starts, so re-poll a few
    // times instead of waiting for the next periodic refresh.
    id: settleTimer
    property int ticks: 0
    interval: 1000
    repeat: true
    onTriggered: {
      ticks += 1
      root.refresh()
      if (ticks >= 5) {
        ticks = 0
        running = false
        root._desired = -1
      }
    }
  }

  Process {
    id: statusProcess
    command: ["sh", "-c", root.probeScript]
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    onExited: root.applyStatus(statusStdout.text)
  }

  Process {
    id: controlProcess
    command: []
    stderr: StdioCollector { id: controlStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = String(controlStderr.text || "Deskflow command failed").trim()
      }
      settleTimer.ticks = 0
      settleTimer.restart()
      root.refresh()
    }
  }
}
