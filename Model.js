// Status is printed by Service.qml's shell probe as key=value lines. Each
// relevant journal line of the unit's current run arrives as its own log= line.
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
    else if (key === "enabled") status.autostart = value === "enabled"
    else if (key === "host") status.host = value
    else if (key === "screen") status.screenName = value
    else if (key === "log" && value !== "") logs.push(value)
  }
  if (mode === "server") {
    status.clients = connectedClients(logs)
    status.state = serverState(status.running, logs, status.clients)
  } else {
    status.state = clientState(status.running, logs.length > 0 ? logs[logs.length - 1] : "")
  }
  return status
}

function defaultStatus() {
  return {
    installed: false,
    running: false,
    autostart: false,
    host: "",
    screenName: "",
    clients: [],
    state: "stopped"
  }
}

function unitName(mode) {
  return "deskflow@" + (mode === "server" ? "server" : "client") + ".service"
}

// Client: the newest relevant deskflow-core log line decides the state.
function clientState(running, line) {
  if (!running) return "stopped"
  var text = String(line || "").toLowerCase()
  if (text.indexOf("failed to connect to eis") >= 0) return "input-error"
  if (text.indexOf("disconnected from server") >= 0) return "connecting"
  if (text.indexOf("connected to server") >= 0) return "connected"
  if (text.indexOf("failed to connect") >= 0) return "unreachable"
  return "connecting"
}

// Server: replay connect/disconnect lines to get the clients attached now.
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

function serverState(running, logs, clients) {
  if (!running) return "stopped"
  for (var i = logs.length - 1; i >= 0; i--) {
    if (String(logs[i]).toLowerCase().indexOf("failed to") >= 0 && clients.length === 0) return "server-error"
  }
  return clients.length > 0 ? "connected" : "waiting"
}

function stateText(state, host, clients) {
  var target = host !== "" ? host : "server"
  if (state === "connected" && clients && clients.length > 0) return "Sharing with " + clients.join(", ")
  if (state === "connected") return "Connected to " + target
  if (state === "connecting") return "Connecting to " + target + "…"
  if (state === "unreachable") return "Can't reach " + target
  if (state === "input-error") return "Input bridge unavailable"
  if (state === "waiting") return "Waiting for clients"
  if (state === "server-error") return "Server failed to start"
  return "Stopped"
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStatus: parseStatus,
    defaultStatus: defaultStatus,
    unitName: unitName,
    clientState: clientState,
    connectedClients: connectedClients,
    serverState: serverState,
    stateText: stateText
  }
}
