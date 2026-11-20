// Live wire: a log of every message between this page and the server,
// for X-ray mode. We wrap the Phoenix socket's push/onMessage, so this is
// the real traffic, not a simulation.
const log = []
const listeners = new Set()
const pending = new Map()
const MAX = 80

const bytes = (payload) => JSON.stringify(payload ?? {}).length

function add(entry) {
  log.unshift(entry)
  if (log.length > MAX) log.pop()
  listeners.forEach((fn) => fn(entry))
}

function describeUp({event, payload}) {
  if (event === "phx_join") return "join · mount the LiveView"
  if (event === "event") {
    const value = payload?.value || {}
    const detail = value.letter || value.key || value.channel || value.difficulty || value.tab || value.section || ""
    return `${payload.type} → "${payload.event}"${detail ? ` (${detail})` : ""}`
  }
  return event
}

function describeDown(msg, request) {
  const diff = msg.payload?.response?.diff || msg.payload?.diff || msg.payload?.response?.rendered
  const events = (diff?.e || []).map(([name]) => name)
  const what = events.length ? ` + push_event: ${events.join(", ")}` : ""
  if (msg.event === "phx_reply" && request) {
    return request.label.startsWith("join") ? "rendered page" : `diff${what}`
  }
  if (msg.event === "diff") return `server push · diff${what}`
  return msg.event
}

export const wire = {
  log,
  subscribe(fn) {
    listeners.add(fn)
    return () => listeners.delete(fn)
  },

  attach(liveSocket) {
    const socket = liveSocket.socket
    const push = socket.push.bind(socket)

    socket.push = (data) => {
      if (data.topic !== "phoenix") {
        const entry = {dir: "up", label: describeUp(data), size: bytes(data.payload), at: performance.now()}
        if (data.ref) pending.set(data.ref, entry)
        add(entry)
      }
      return push(data)
    }

    socket.onMessage((msg) => {
      if (msg.topic === "phoenix") return
      const request = msg.ref && pending.get(msg.ref)
      if (request) pending.delete(msg.ref)
      add({
        dir: "down",
        label: describeDown(msg, request),
        size: bytes(msg.payload),
        latency: request ? Math.round(performance.now() - request.at) : null,
        at: performance.now(),
      })
    })
  },

  transport(liveSocket) {
    const t = liveSocket.socket.transport
    return t === window.WebSocket ? "WebSocket" : "Long-polling"
  },
}
