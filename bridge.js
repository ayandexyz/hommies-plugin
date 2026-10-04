.pragma library

// port.json can outlive the bridge (a crash leaves it behind), and the freed
// port is then free for any local user. So the client only talks to the port
// the running child process announced (Service.qml), and drops the
// connection the moment that process exits.
var connection = null
var fileConnection = null
var livePort = 0

function apply() {
  connection = fileConnection && livePort > 0 && fileConnection.port === livePort ? fileConnection : null
  return connection !== null
}

/** The contents of port.json. Used only while its port matches the live bridge. */
function configure(next) {
  if (next && Number.isInteger(next.port) && typeof next.token === "string") fileConnection = next
  return apply()
}

/** The port the running hommies-bridge printed, or 0 once it has exited. */
function setLivePort(port) {
  livePort = Number.isInteger(port) && port > 0 && port < 65536 ? port : 0
  return apply()
}

function snapshot() {
  if (!connection) return Promise.resolve({ totalCount: 0, threads: [] })
  return request("GET", "/v1/pending")
}

function respond(input) {
  if (!connection) return Promise.reject(new Error("Hommies bridge is unavailable"))
  return request("POST", "/v1/respond", input)
}

function focus(threadId) {
  if (!connection) return Promise.reject(new Error("Hommies bridge is unavailable"))
  return request("POST", "/v1/focus", { threadId: threadId })
}

function setPreferences(input) {
  if (!connection) return Promise.resolve({ ok: false })
  return request("POST", "/v1/preferences", input)
}

function subscribe(_onUpdate) { return function() {} }

function request(method, path, body) {
  return new Promise(function(resolve, reject) {
    var xhr = new XMLHttpRequest()
    xhr.open(method, "http://127.0.0.1:" + connection.port + path)
    xhr.setRequestHeader("x-hommies-token", connection.token)
    xhr.setRequestHeader("content-type", "application/json")
    xhr.onload = function() {
      if (xhr.status >= 200 && xhr.status < 300) resolve(JSON.parse(xhr.responseText))
      else reject(new Error("bridge request failed"))
    }
    xhr.onerror = function() { reject(new Error("bridge request failed")) }
    xhr.send(body === undefined ? null : JSON.stringify(body))
  })
}
