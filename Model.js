// Status is printed by `deskflowctl status` as key=value lines. Repeated keys
// (log=, layout=) arrive once per line, oldest first.
function parseStatus(raw, mode) {
  var status = defaultStatus()
  var logs = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var eq = lines[i].indexOf("=")
    if (eq <= 0) continue
    var key = lines[i].substring(0, eq)
    var value = lines[i].substring(eq + 1).trim()
    if (key === "installed") status.installed = value === "1"
    else if (key === "active") status.running = value === "active" || value === "activating" || value === "reloading"
    else if (key === "substate") status.restarting = value === "auto-restart"
    else if (key === "enabled") status.autostart = value === "enabled"
    else if (key === "host") status.host = value
    else if (key === "screen") status.screenName = value
    else if (key === "coremode") status.appMode = appMode(value)
    else if (key === "clipboard") status.clipboard = value === "true"
    else if (key === "fingerprint") status.fingerprint = value
    else if (key === "pending") status.pendingFingerprint = value
    else if (key === "unknown") status.unknownClient = value
    else if (key === "error") status.error = value
    else if (key === "layout") status.layout.push(layoutEntry(value))
    else if (key === "log" && value !== "") logs.push(value)
  }
  if (mode === "server") status.clients = connectedClients(logs)
  status.state = state(mode, status, logs)
  return status
}

function defaultStatus() {
  return {
    installed: false,
    running: false,
    restarting: false,
    autostart: false,
    host: "",
    screenName: "",
    appMode: "",
    clipboard: false,
    fingerprint: "",
    pendingFingerprint: "",
    unknownClient: "",
    error: "",
    layout: [],
    clients: [],
    state: "stopped"
  }
}

// Deskflow stores its CoreMode enum (None, Client, Server) as a name or index.
function appMode(value) {
  var text = String(value || "").toLowerCase()
  if (text === "2" || text === "server") return "server"
  if (text === "1" || text === "client") return "client"
  return ""
}

// The widget's own setting wins; "auto" follows the Deskflow app.
function resolveMode(configured, app) {
  if (configured === "client" || configured === "server") return configured
  return app === "server" ? "server" : "client"
}

function layoutEntry(value) {
  var parts = String(value || "").split(" ")
  return { name: parts[0] || "", direction: parts[1] || "" }
}

// Replay connect/disconnect lines to get the clients attached now.
function connectedClients(logs) {
  var clients = []
  for (var i = 0; i < logs.length; i++) {
    var match = String(logs[i]).match(/client "([^"]+)" has (connected|disconnected)/)
    if (!match) continue
    var index = clients.indexOf(match[1])
    if (match[2] === "connected" && index < 0) clients.push(match[1])
    else if (match[2] === "disconnected" && index >= 0) clients.splice(index, 1)
  }
  return clients
}

function state(mode, status, logs) {
  if (status.restarting) return "failed"
  if (!status.running) return "stopped"
  if (status.pendingFingerprint !== "") return "untrusted"
  if (mode === "server") {
    if (status.unknownClient !== "") return "unknown-client"
    return status.clients.length > 0 ? "connected" : "waiting"
  }
  var line = String(logs.length > 0 ? logs[logs.length - 1] : "").toLowerCase()
  if (line.indexOf("failed to connect to eis") >= 0) return "input-error"
  if (line.indexOf("disconnected from server") >= 0) return "connecting"
  if (line.indexOf("connected to server") >= 0) return "connected"
  if (line.indexOf("failed to connect") >= 0) return "unreachable"
  return "connecting"
}

function stateText(state, host, clients) {
  var target = host !== "" ? host : "server"
  if (state === "connected" && clients && clients.length > 0) return "Sharing with " + clients.join(", ")
  if (state === "connected") return "Connected to " + target
  if (state === "connecting") return "Connecting to " + target + "…"
  if (state === "unreachable") return "Can't reach " + target
  if (state === "input-error") return "Input bridge unavailable"
  if (state === "untrusted") return "Waiting for you to trust it"
  if (state === "unknown-client") return "A new client wants a spot"
  if (state === "waiting") return "Waiting for clients"
  if (state === "failed") return "Deskflow keeps failing"
  return "Stopped"
}

// Fingerprints are 64 hex characters; show them in groups of four so two
// screens are easy to compare by eye.
function formatFingerprint(hex) {
  var text = String(hex || "").toUpperCase()
  var groups = []
  for (var i = 0; i < text.length; i += 4) groups.push(text.substring(i, i + 4))
  return groups.join(" ")
}

function directionLabel(direction) {
  if (direction === "above") return "Above this screen"
  if (direction === "below") return "Below this screen"
  if (direction === "left") return "Left of this screen"
  if (direction === "right") return "Right of this screen"
  return ""
}

function directionGlyph(direction) {
  if (direction === "above") return "󰁝"
  if (direction === "below") return "󰁅"
  if (direction === "left") return "󰁍"
  if (direction === "right") return "󰁔"
  return "󰍹"
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStatus: parseStatus,
    defaultStatus: defaultStatus,
    appMode: appMode,
    resolveMode: resolveMode,
    layoutEntry: layoutEntry,
    connectedClients: connectedClients,
    state: state,
    stateText: stateText,
    formatFingerprint: formatFingerprint,
    directionLabel: directionLabel,
    directionGlyph: directionGlyph
  }
}
