// X-ray mode: the scan-line sweep when it toggles, and the live wire log.
import {gsap} from "../motion"
import {wire} from "../wire"

export function showTransport() {
  const name = window.liveSocket ? wire.transport(window.liveSocket) : "…"
  for (const el of document.querySelectorAll("#transport-badge, #xp-transport")) {
    el.textContent = name === "WebSocket" ? "WebSocket" : "HTTP long-polling"
    el.dataset.transport = name
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
    this.off = wire.subscribe((entry) => this.prepend(entry))
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
    gsap.from(row, {backgroundColor: "rgba(94, 242, 255, 0.35)", duration: 1.2, ease: "power2.out"})
    while (this.el.children.length > 40) this.el.lastChild.remove()
  },
}
