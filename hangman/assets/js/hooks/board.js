// GSAP choreography for the menu, board, gallows and result dialog.
//
// LiveView re-renders the DOM; these hooks only add motion on top. Every
// tween ends on the element's natural CSS state (or clears its props), so
// a server patch arriving mid-animation never leaves things stuck.
import {gsap, reducedMotion} from "../motion"

const $ = (root, sel) => root.querySelector(sel)
const $$ = (root, sel) => Array.from(root.querySelectorAll(sel))

// ── Menu ───────────────────────────────────────────────────────────────

export const Intro = {
  mounted() {
    const letters = $$(this.el, ".hero-letter")
    const tl = gsap.timeline({defaults: {ease: "power3.out"}})

    tl.from(letters, {
      yPercent: 110,
      rotate: (i) => (i % 2 ? 8 : -8),
      opacity: 0,
      duration: 0.9,
      stagger: 0.06,
      ease: "back.out(1.7)",
    })
      .from($$(this.el, "[data-intro]"), {y: 24, opacity: 0, duration: 0.7, stagger: 0.08}, "-=0.6")
      .from($$(this.el, "[data-card]"), {y: 18, opacity: 0, scale: 0.96, duration: 0.5, stagger: 0.04}, "-=0.5")
      .add(() => gsap.set([...letters, ...$$(this.el, "[data-intro],[data-card]")], {clearProps: "all"}))

    // Letters lean toward the pointer, like they're listening.
    this.onMove = (e) => {
      if (reducedMotion()) return
      letters.forEach((el) => {
        const r = el.getBoundingClientRect()
        const dx = (e.clientX - (r.left + r.width / 2)) / window.innerWidth
        const dy = (e.clientY - (r.top + r.height / 2)) / window.innerHeight
        gsap.to(el, {x: dx * 18, y: dy * 14, rotate: dx * 6, duration: 0.8, ease: "power2.out", overwrite: "auto"})
      })
    }
    window.addEventListener("pointermove", this.onMove, {passive: true})
  },

  destroyed() {
    window.removeEventListener("pointermove", this.onMove)
  },
}

// ── Board (word tiles, keyboard, flames) ───────────────────────────────

export const Board = {
  mounted() {
    this.entrance(true)
    this.handleEvent("fx", (fx) => this.fx(fx))
  },

  entrance(first) {
    const tiles = $$(this.el, ".tile")
    const keys = $$(this.el, ".key")
    const tl = gsap.timeline()

    if (first) {
      tl.from($$(this.el, ".panel"), {y: 30, opacity: 0, duration: 0.7, stagger: 0.1, ease: "power3.out", clearProps: "all"})
    }

    tl.from(
      tiles,
      {y: -28, rotateX: -90, opacity: 0, duration: 0.55, stagger: 0.045, ease: "back.out(2)", clearProps: "all"},
      first ? "-=0.45" : 0,
    ).from(
      keys,
      {y: 12, opacity: 0, scale: 0.9, duration: 0.4, stagger: {each: 0.012, from: "center"}, ease: "power2.out", clearProps: "all"},
      "<0.1",
    )
  },

  fx({kind, letter, positions = [], lives}) {
    const key = letter && $(this.el, `[data-key="${letter}"]`)
    const word = $(this.el, "#word")

    switch (kind) {
      case "start":
        return this.entrance(false)

      case "hit":
      case "hint":
        this.flipTiles(positions)
        if (key) gsap.fromTo(key, {scale: 1.25}, {scale: 1, duration: 0.6, ease: "elastic.out(1, 0.4)", clearProps: "transform"})
        if (kind === "hint") this.snuffFlame(lives + 1)
        return

      case "miss":
        if (key) gsap.fromTo(key, {x: -4}, {x: 0, duration: 0.5, ease: "elastic.out(1.2, 0.3)", clearProps: "transform"})
        gsap.fromTo(word, {x: -12}, {x: 0, duration: 0.6, ease: "elastic.out(1.4, 0.25)", clearProps: "transform"})
        this.snuffFlame(lives + 1)
        return

      case "repeat":
        if (key) gsap.fromTo(key, {rotate: -8}, {rotate: 0, duration: 0.5, ease: "elastic.out(1.5, 0.3)", clearProps: "transform"})
        gsap.fromTo("#message", {x: -6}, {x: 0, duration: 0.4, ease: "elastic.out(1.5, 0.3)", clearProps: "transform"})
        return

      case "win":
        gsap.to($$(this.el, ".tile:not(.tile--gap)"), {
          y: -16,
          duration: 0.28,
          ease: "power2.out",
          yoyo: true,
          repeat: 1,
          stagger: 0.05,
          clearProps: "transform",
        })
        return

      case "lose":
        this.flipTiles($$(this.el, ".tile.is-missed").map((t) => Number(t.dataset.index)))
        gsap.fromTo(word, {x: -18}, {x: 0, duration: 0.9, ease: "elastic.out(1.6, 0.2)", clearProps: "transform"})
        return
    }
  },

  flipTiles(positions) {
    const tiles = positions.map((i) => $(this.el, `.tile[data-index="${i}"]`)).filter(Boolean)
    gsap.fromTo(
      tiles,
      {rotateX: -100, y: -10, opacity: 0.2},
      {rotateX: 0, y: 0, opacity: 1, duration: 0.6, stagger: 0.07, ease: "back.out(2.2)", clearProps: "all"},
    )
  },

  // The flame that just went out flares, then a wisp of smoke drifts up.
  snuffFlame(n) {
    const flame = $(this.el, `[data-flame="${n}"]`)
    if (!flame) return
    const svg = flame.querySelector("svg")
    gsap.fromTo(svg, {scale: 1.5, filter: "brightness(2)"}, {scale: 1, filter: "brightness(1)", duration: 0.7, ease: "power3.out", clearProps: "all"})

    const puff = document.createElement("span")
    puff.className = "pointer-events-none absolute size-3 rounded-full bg-chalk/40 blur-[3px]"
    flame.style.position = "relative"
    flame.appendChild(puff)
    gsap.fromTo(
      puff,
      {x: 6, y: 0, opacity: 0.8, scale: 0.6},
      {x: 6 + gsap.utils.random(-10, 10), y: -46, opacity: 0, scale: 2.4, duration: 1.2, ease: "power1.out", onComplete: () => puff.remove()},
    )
  },
}

// ── Gallows (SVG stroke drawing) ───────────────────────────────────────

export const Gallows = {
  mounted() {
    this.svg = $(this.el, "svg")
    this.parts = $$(this.svg, "[data-part]")
    this.figure = $(this.svg, ".gallows-figure")
    this.face = $(this.svg, ".gallows-face")

    for (const el of [...$$(this.svg, "[data-frame]"), ...this.parts]) {
      const len = Math.ceil(el.getTotalLength())
      el.style.strokeDasharray = len
      el.dataset.len = len
    }

    this.drawn = 0
    this.status = "playing"
    this.round = this.el.dataset.round

    // Draw the frame like chalk on a board, then catch up on any parts.
    gsap.fromTo(
      $$(this.svg, "[data-frame]"),
      {strokeDashoffset: (_i, el) => el.dataset.len},
      {strokeDashoffset: 0, duration: 0.6, stagger: 0.12, ease: "power2.inOut"},
    )
    this.parts.forEach((p) => (p.style.strokeDashoffset = p.dataset.len))
    this.sync()
  },

  updated() {
    this.sync()
  },

  sync() {
    const mistakes = Number(this.el.dataset.mistakes)
    const status = this.el.dataset.status
    const round = this.el.dataset.round

    if (round !== this.round) {
      // New word: wipe the figure and reset any win/lose pose.
      this.round = round
      this.drawn = 0
      this.status = "playing"
      gsap.killTweensOf([this.figure, this.face, ...this.parts])
      gsap.set(this.figure, {rotation: 0, y: 0, svgOrigin: "168 30"})
      gsap.set(this.parts, {clearProps: "stroke,filter"})
      gsap.set(this.face, {opacity: 0})
      gsap.to(this.parts, {strokeDashoffset: (_i, el) => el.dataset.len, duration: 0.3, ease: "power2.in"})
    }

    for (let i = this.drawn; i < mistakes; i++) {
      const part = this.parts[i]
      gsap.to(part, {strokeDashoffset: 0, duration: 0.55, delay: (i - this.drawn) * 0.15, ease: "power2.out"})
    }
    this.drawn = Math.max(this.drawn, mistakes)

    if (status !== this.status) {
      this.status = status
      if (status === "lost") this.lose()
      if (status === "won") this.win()
    }
  },

  lose() {
    gsap.to(this.face, {opacity: 1, duration: 0.4, delay: 0.5})
    gsap.fromTo(
      this.figure,
      {rotation: 0, svgOrigin: "168 30"},
      {rotation: 7, duration: 1.4, ease: "sine.inOut", yoyo: true, repeat: -1, delay: 0.4, svgOrigin: "168 30"},
    )
  },

  win() {
    gsap.fromTo(
      this.figure,
      {y: 0},
      {y: -10, duration: 0.3, ease: "power2.out", yoyo: true, repeat: 3, svgOrigin: "168 30"},
    )
    gsap.to(this.parts, {stroke: "#ffd479", filter: "drop-shadow(0 0 14px rgba(255, 212, 121, 0.9))", duration: 0.6})
  },
}

// ── Result dialog ──────────────────────────────────────────────────────

export const Result = {
  destroyed() {
    this.tl?.kill()
  },

  mounted() {
    const card = $(this.el, ".result-card")
    const won = this.el.dataset.status === "won"
    const points = $(this.el, "[data-count]")

    const items = $$(card, ".kicker, .result-title, .result-word, .result-stat, .result-actions")
    const all = [this.el, card, ...items]
    // Explicit end states + clearProps: the dialog can never get stuck
    // half-faded, whatever else is animating when it opens.
    this.tl = gsap.timeline({delay: won ? 0.9 : 1.3, onComplete: () => gsap.set(all, {clearProps: "all"})})
      .fromTo(this.el, {opacity: 0}, {opacity: 1, duration: 0.35})
      .fromTo(card, {y: 40, scale: 0.94, opacity: 0}, {y: 0, scale: 1, opacity: 1, duration: 0.6, ease: "back.out(1.6)"}, "<")
      .fromTo(items, {y: 14, opacity: 0}, {y: 0, opacity: 1, duration: 0.45, stagger: 0.05, ease: "power2.out"}, "-=0.35")
      .add(() => $(this.el, "#next")?.focus({preventScroll: true}))

    if (points) {
      const target = Number(points.dataset.count)
      const counter = {v: 0}
      gsap.to(counter, {
        v: target,
        duration: 1,
        delay: won ? 1.3 : 1.6,
        ease: "power2.out",
        onUpdate: () => (points.textContent = `+${Math.round(counter.v)}`),
      })
    }
  },
}
