// Live wire: every message between this page and the server, for X-ray
// mode. We wrap the Phoenix socket's push/onMessage, so this is the real
// traffic, not a simulation. It also keeps:
//   * `trace`: the last key press, end to end (the Trace tab)
//   * `totals`: first-render and diff sizes (the Why Phoenix tab)
const log = []
const listeners = new Set()
const pending = new Map()
const MAX = 80
const RAW = 700

const bytes = (payload) => JSON.stringify(payload ?? {}).length
const raw = (payload) => {
  const json = JSON.stringify(payload ?? {})
  return json.length > RAW ? `${json.slice(0, RAW)}…` : json
}

export const trace = {}
export const totals = {first: null, statics: null, diffs: [], messages: 0}

function emit(entry) {
  if (entry) {
    log.unshift(entry)
    if (log.length > MAX) log.pop()
  }
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
  if (events.includes("xray_trace")) return "server push · telemetry timings (X-ray only)"
  if (msg.event === "diff") return `server push · diff${what}`
  return msg.event
}

// Sum the static HTML fragments ("s" and shared "p" templates) in a
// LiveView rendered tree: the part that is sent once and never again.
function staticBytes(node) {
  if (Array.isArray(node)) return node.reduce((n, child) => n + staticBytes(child), 0)
  if (!node || typeof node !== "object") return 0
  let n = 0
  for (const [key, value] of Object.entries(node)) {
    if (key === "s" && Array.isArray(value)) n += value.join("").length
    else if (key === "p") n += Object.values(value).reduce((m, s) => m + s.join("").length, 0)
    else n += staticBytes(value)
  }
  return n
}

const isGuess = (payload) => payload?.event === "guess" || (payload?.event === "key" && payload?.value?.key?.length === 1)

export const wire = {
  log,
  subscribe(fn) {
    listeners.add(fn)
    return () => listeners.delete(fn)
  },

  // Server timings arrive as a push_event right after the reply.
  serverTiming({event, event_us, render_us}) {
    if (event !== "guess" && event !== "key") return
    Object.assign(trace, {event_us, render_us})
    emit(null)
  },

  attach(liveSocket) {
    const socket = liveSocket.socket
    const push = socket.push.bind(socket)

    socket.push = (data) => {
      if (data.topic !== "phoenix") {
        const entry = {dir: "up", label: describeUp(data), size: bytes(data.payload), at: performance.now()}
        if (data.event === "event" && isGuess(data.payload)) {
          entry.guess = true
          const value = data.payload.value || {}
          for (const k of Object.keys(trace)) delete trace[k]
          Object.assign(trace, {key: (value.letter || value.key).toUpperCase(), up: entry.size, upRaw: raw(data.payload)})
        }
        if (data.ref) pending.set(data.ref, entry)
        totals.messages++
        emit(entry)
      }
      return push(data)
    }

    socket.onMessage((msg) => {
      if (msg.topic === "phoenix") return
      const request = msg.ref && pending.get(msg.ref)
      if (request) pending.delete(msg.ref)
      const size = bytes(msg.payload)
      const latency = request ? Math.round(performance.now() - request.at) : null

      const rendered = msg.payload?.response?.rendered
      if (rendered && request?.label.startsWith("join")) {
        totals.first = size
        totals.statics = staticBytes(rendered)
      }
      if (request?.guess) {
        totals.diffs.push(size)
        Object.assign(trace, {down: size, downRaw: raw(msg.payload?.response?.diff ?? msg.payload), rtt: latency})
      }
      totals.messages++
      emit({dir: "down", label: describeDown(msg, request), size, latency, at: performance.now()})
    })
  },

  transport(liveSocket) {
    const t = liveSocket.socket.transport
    return t === window.WebSocket ? "WebSocket" : "Long-polling"
  },
}
