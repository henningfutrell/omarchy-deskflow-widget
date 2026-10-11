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
  property string appMode: ""
  property bool clipboard: false
  property string fingerprint: ""
  property string pendingFingerprint: ""
  property string unknownClient: ""
  property string coreError: ""
  property var layout: []
  property var clients: []
  property string connectionState: "stopped"
  property string lastError: ""

  readonly property string configuredMode: String(setting("mode", "auto"))
  readonly property string mode: Model.resolveMode(configuredMode, appMode)
  readonly property bool isServer: mode === "server"

  // Optimistic run state so the switch throws the instant it is clicked:
  // -1 follows the real unit state, 0/1 while a stop/start is catching up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  readonly property bool connected: active && connectionState === "connected"
  readonly property bool failing: connectionState === "failed" || connectionState === "input-error"
  readonly property bool busy: controlProcess.running
  readonly property string statusText: _desired === 1 && !running ? "Starting…" : Model.stateText(connectionState, host, clients)

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 5, 2, 300)

  // All file and systemd work lives in deskflowctl next to this file, so the
  // plugin folder is self-contained and arguments never pass through a shell.
  readonly property string ctl: decodeURIComponent(String(Qt.resolvedUrl("deskflowctl")).replace(/^file:\/\//, ""))

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
    statusProcess.command = ["bash", ctl, "status", mode]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw, mode)
    var modeBefore = mode
    appMode = parsed.appMode
    clipboard = parsed.clipboard
    installed = parsed.installed
    running = parsed.running
    autostart = parsed.autostart
    host = parsed.host
    screenName = parsed.screenName
    fingerprint = parsed.fingerprint
    pendingFingerprint = parsed.pendingFingerprint
    unknownClient = parsed.unknownClient
    coreError = parsed.error
    layout = parsed.layout
    clients = parsed.clients
    connectionState = parsed.state
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    // The app's mode was only known after this probe; read the right unit.
    if (mode !== modeBefore) Qt.callLater(refresh)
  }

  function run(args, desired) {
    if (!installed || controlProcess.running) return
    if (desired !== undefined) _desired = desired
    lastError = ""
    controlProcess.command = ["bash", ctl].concat(args)
    controlProcess.running = true
  }

  // `address` is the panel's unsaved server field, so starting never ignores
  // what is on screen.
  function start(address) {
    var args = ["start", mode]
    var pending = String(address || "").trim()
    if (!isServer && pending !== "" && pending !== host) args.push(pending)
    run(args, 1)
  }
  function stop() { run(["stop", mode], 0) }
  function toggleRunning() { active ? stop() : start() }
  function toggleAutostart() { run([autostart ? "disable" : "enable", mode]) }
  function toggleClipboard() { run(["set-clipboard", clipboard ? "false" : "true"]) }
  function setMode(newMode) { if (newMode !== mode) run(["set-mode", newMode], -1) }
  function toggleMode() { setMode(isServer ? "client" : "server") }
  function setServer(address) { run(["set-server", String(address || "").trim()]) }
  function trustPending() { if (pendingFingerprint !== "") run(["trust", mode, pendingFingerprint]) }
  function addScreen(name, direction) { run(["add-screen", name, direction]) }
  function removeScreen(name) { run(["remove-screen", name]) }

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
    // The connection settles a moment after a change, so re-poll a few times
    // instead of waiting for the next periodic refresh.
    id: settleTimer
    property int ticks: 0
    interval: 1000
    repeat: true
    onTriggered: {
      ticks += 1
      root.refresh()
      if (ticks >= 6) {
        ticks = 0
        running = false
        root._desired = -1
      }
    }
  }

  Process {
    id: statusProcess
    command: []
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
        root.lastError = String(controlStderr.text || "Deskflow command failed").trim().split("\n").pop()
      }
      settleTimer.ticks = 0
      settleTimer.restart()
      root.refresh()
    }
  }
}
