.pragma library

var connection = null

function configure(next) {
  if (next && Number.isInteger(next.port) && typeof next.token === "string") connection = next
}

function snapshot() {
  if (!connection) return Promise.resolve({ totalCount: 0, threads: [] })
  return request("GET", "/v1/pending")
}

function respond(input) {
  if (!connection) return Promise.reject(new Error("agent-fold bridge is unavailable"))
  return request("POST", "/v1/respond", input)
}

function focus(threadId) {
  if (!connection) return Promise.reject(new Error("agent-fold bridge is unavailable"))
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
    xhr.setRequestHeader("x-agent-fold-token", connection.token)
    xhr.setRequestHeader("content-type", "application/json")
    xhr.onload = function() {
      if (xhr.status >= 200 && xhr.status < 300) resolve(JSON.parse(xhr.responseText))
      else reject(new Error("bridge request failed"))
    }
    xhr.onerror = function() { reject(new Error("bridge request failed")) }
    xhr.send(body === undefined ? null : JSON.stringify(body))
  })
}
