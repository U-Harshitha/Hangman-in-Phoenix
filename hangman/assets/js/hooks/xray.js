// X-ray mode: the scan-line sweep, the live wire log, the key-press trace,
// the measured numbers in "Why Phoenix", and the crash demo.
import {gsap} from "../motion"
import {wire, trace, totals} from "../wire"

const kb = (n) => (n >= 1024 ? `${(n / 1024).toFixed(1)} KB` : `${n} B`)

export function showTransport() {
  const name = window.liveSocket ? wire.transport(window.liveSocket) : "…"
  for (const el of document.querySelectorAll("#transport-badge, #xp-transport, #proof-transport")) {
    // Children only: these elements are phx-update="ignore", which keeps
    // their content but not attributes the client added.
    el.innerHTML = `<i class="t-dot"></i>${name === "WebSocket" ? "WebSocket" : "HTTP long-polling"}`
  }
}

// The transport line in the X-ray panel fills itself in when it appears.
export const Transport = {
  mounted() {
    showTransport()
  },
}

export const XrayScan = {
  mounted() {
    this.on = this.el.dataset.on
  },

  updated() {
    if (this.el.dataset.on === this.on) return
    this.on = this.el.dataset.on
    const down = this.on === "true"
    gsap.fromTo(
      this.el,
      {autoAlpha: 1, yPercent: down ? -100 : 100},
      {yPercent: down ? 100 : -100, duration: 0.9, ease: "power2.inOut", onComplete: () => gsap.set(this.el, {autoAlpha: 0})},
    )
    if (down) {
      showTransport()
      gsap.from("#xray-panel", {x: 40, opacity: 0, duration: 0.5, delay: 0.2, ease: "power3.out", clearProps: "all"})
      gsap.from(".pin", {scale: 0, duration: 0.4, stagger: 0.05, delay: 0.35, ease: "back.out(3)", clearProps: "all"})
    }
  },
}

export const Wire = {
  mounted() {
    this.render()
    this.off = wire.subscribe((entry) => entry && this.prepend(entry))
  },

  destroyed() {
    this.off?.()
  },

  row(entry) {
    const li = document.createElement("div")
    li.className = `wire-row wire-${entry.dir}`
    const arrow = entry.dir === "up" ? "↑" : "↓"
    const meta = [`${entry.size} B`, entry.latency != null ? `${entry.latency} ms` : null].filter(Boolean).join(" · ")
    li.innerHTML = `<span class="wire-arrow">${arrow}</span><span class="wire-label"></span><span class="wire-meta">${meta}</span>`
    li.querySelector(".wire-label").textContent = entry.label
    return li
  },

  render() {
    this.el.replaceChildren(...wire.log.slice(0, 40).map((e) => this.row(e)))
    if (!wire.log.length) this.el.innerHTML = `<p class="wire-empty">Waiting for traffic… press a letter.</p>`
  },

  prepend(entry) {
    this.el.querySelector(".wire-empty")?.remove()
    const row = this.row(entry)
    this.el.prepend(row)
    gsap.from(row, {backgroundColor: "rgba(29, 106, 133, 0.16)", duration: 1.2, ease: "power2.out"})
    while (this.el.children.length > 40) this.el.lastChild.remove()
  },
}

// One key press, end to end. Steps light up in order as the numbers come in.
export const Trace = {
  mounted() {
    this.steps = [...this.el.querySelectorAll(".trace-step")]
    this.raw = this.el.parentElement.querySelector("#trace-raw")
    this.shown = null
    this.render(false)
    this.off = wire.subscribe(() => this.render(true))
  },

  destroyed() {
    this.off?.()
  },

  render(animate) {
    const t = trace
    if (!t.key) return
    const values = {
      key: `you pressed ${t.key}`,
      up: t.up != null ? `${t.up} bytes up` : "…",
      event_us: t.event_us != null ? `handle_event + Game.guess: ${t.event_us} µs` : "…",
      render_us: t.render_us != null ? `render + diff: ${t.render_us} µs` : "…",
      down: t.down != null ? `${t.down} bytes down` : "…",
      rtt: t.rtt != null ? `round trip, network included: ${t.rtt} ms` : "…",
    }
    for (const [slot, text] of Object.entries(values)) {
      const el = this.el.querySelector(`[data-slot="${slot}"]`)
      if (el) el.textContent = text
    }
    if (this.raw) {
      this.raw.querySelector('[data-raw="up"]').textContent = `↑ ${t.upRaw || ""}`
      this.raw.querySelector('[data-raw="down"]').textContent = t.downRaw ? `↓ ${t.downRaw}` : "↓ …"
    }

    // A new press: run the light along the steps, like a packet travelling.
    const id = `${t.key}:${t.upRaw}`
    if (animate && this.shown !== id) {
      this.shown = id
      this.steps.forEach((s) => s.classList.remove("is-lit"))
      gsap.timeline().add(
        this.steps.map((s, i) => gsap.delayedCall(i * 0.12, () => s.classList.add("is-lit"))),
      )
    } else if (!animate) {
      this.steps.forEach((s) => s.classList.add("is-lit"))
    }
  },
}

// "HTML diffs instead of a JSON API": sizes measured from this tab.
export const DiffStats = {
  mounted() {
    this.render()
    this.off = wire.subscribe(() => this.render())
  },

  destroyed() {
    this.off?.()
  },

  render() {
    const set = (slot, text) => {
      const el = this.el.querySelector(`[data-slot="${slot}"]`)
      if (el) el.textContent = text
    }
    const {first, statics, diffs, messages} = totals
    if (first) set("first", kb(first))
    if (first && statics) set("statics", `${kb(statics)}, sent once`)
    if (diffs.length) set("avg", `${kb(Math.round(diffs.reduce((a, b) => a + b, 0) / diffs.length))} (${diffs.length} guesses)`)
    set("count", `${messages}`)
  },
}

// How much JavaScript this page actually downloaded, from the browser's
// own resource timing.
export const JsStats = {
  mounted() {
    const js = performance
      .getEntriesByType("resource")
      .filter((r) => r.name.includes("/assets/js/") && r.name.split("?")[0].endsWith(".js"))
    const size = (r) => r.encodedBodySize || r.transferSize || 0
    const lazy = js.filter((r) => r.name.includes("ember_field"))
    const main = js.filter((r) => !r.name.includes("ember_field"))
    const sum = (list) => list.reduce((n, r) => n + size(r), 0)
    const set = (slot, text) => (this.el.querySelector(`[data-slot="${slot}"]`).textContent = text)
    set("main", main.length ? `${kb(sum(main))} compressed` : "—")
    set("lazy", lazy.length ? `${kb(sum(lazy))}, after play` : "not loaded")
  },
}

// "Let it crash": remember who we were, then ask the server to die. The
// next join sends this along (see app.js) so the new process can tell you.
export const Crash = {
  mounted() {
    this.el.addEventListener("click", () => {
      try {
        sessionStorage.setItem("hangman:crash", JSON.stringify({pid: this.el.dataset.pid, at: Date.now()}))
      } catch (_e) {
        // No sessionStorage: the crash still happens, just unexplained.
      }
      this.el.disabled = true
      this.el.textContent = "Crashing…"
      this.pushEvent("crash", {})
    })
  },
}

export function takeCrash() {
  try {
    const saved = JSON.parse(sessionStorage.getItem("hangman:crash"))
    sessionStorage.removeItem("hangman:crash")
    if (saved?.pid) return {pid: saved.pid, ms: Math.max(0, Date.now() - saved.at)}
  } catch (_e) {
    // Ignore: nothing to report.
  }
  return undefined
}
