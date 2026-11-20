// GSAP choreography for the TV guide, the board, the mascots and the
// result dialog.
//
// LiveView re-renders the DOM; these hooks only add motion on top. Tweens
// end on the element's natural CSS state (or clear their props), so a
// server patch arriving mid-animation never leaves anything stuck.
import {gsap, reducedMotion} from "../motion"

const $ = (root, sel) => root.querySelector(sel)
const $$ = (root, sel) => Array.from(root.querySelectorAll(sel))

// ── TV guide (menu) ────────────────────────────────────────────────────

export const Intro = {
  mounted() {
    const letters = $$(this.el, ".hero-letter")
    const tl = gsap.timeline({defaults: {ease: "power3.out"}})

    tl.from(letters, {
      yPercent: 110,
      rotate: (i) => (i % 2 ? 9 : -9),
      opacity: 0,
      duration: 0.85,
      stagger: 0.045,
      ease: "back.out(1.7)",
    })
      .from($$(this.el, "[data-intro]"), {y: 24, opacity: 0, duration: 0.65, stagger: 0.07}, "-=0.55")
      .from($$(this.el, "[data-card]"), {x: -16, opacity: 0, duration: 0.45, stagger: 0.05}, "-=0.5")
      .add(() => gsap.set([...letters, ...$$(this.el, "[data-intro],[data-card]")], {clearProps: "all"}))

    // Letters lean toward the pointer, like a studio audience leaning in.
    this.onMove = (e) => {
      if (reducedMotion()) return
      letters.forEach((el) => {
        const r = el.getBoundingClientRect()
        const dx = (e.clientX - (r.left + r.width / 2)) / window.innerWidth
        const dy = (e.clientY - (r.top + r.height / 2)) / window.innerHeight
        gsap.to(el, {x: dx * 16, y: dy * 12, rotate: dx * 6, duration: 0.8, ease: "power2.out", overwrite: "auto"})
      })
    }
    window.addEventListener("pointermove", this.onMove, {passive: true})
  },

  destroyed() {
    window.removeEventListener("pointermove", this.onMove)
  },
}

// ── Board (tiles, keyboard, takes) ─────────────────────────────────────

export const Board = {
  mounted() {
    this.entrance(true)
    this.handleEvent("fx", (fx) => this.fx(fx))
  },

  // Tiles and keys slide in once the episode title card clears.
  entrance(first) {
    const tl = gsap.timeline({delay: 1.15})
    if (first) {
      gsap.from($$(this.el, ".set-panel, .clue-card, .word-card, .episode-bar"), {
        y: 26,
        opacity: 0,
        duration: 0.7,
        stagger: 0.08,
        ease: "power3.out",
        clearProps: "all",
      })
    }
    tl.from($$(this.el, ".tile"), {
      y: -26,
      rotateX: -90,
      opacity: 0,
      duration: 0.55,
      stagger: 0.04,
      ease: "back.out(2)",
      clearProps: "all",
    }).from(
      $$(this.el, ".key"),
      {y: 12, opacity: 0, scale: 0.9, duration: 0.4, stagger: {each: 0.01, from: "center"}, ease: "power2.out", clearProps: "all"},
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
        if (kind === "hint") this.cutLamp(lives + 1)
        return

      case "miss":
        if (key) gsap.fromTo(key, {x: -4}, {x: 0, duration: 0.5, ease: "elastic.out(1.2, 0.3)", clearProps: "transform"})
        gsap.fromTo(word, {x: -12}, {x: 0, duration: 0.6, ease: "elastic.out(1.4, 0.25)", clearProps: "transform"})
        this.cutLamp(lives + 1)
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

  // The "take" lamp that just went out flares, like a blown bulb.
  cutLamp(n) {
    const lamp = $(this.el, `[data-lamp="${n}"]`)
    if (lamp) gsap.fromTo(lamp, {scale: 1.8, filter: "brightness(2.2)"}, {scale: 1, filter: "brightness(1)", duration: 0.7, ease: "power3.out", clearProps: "all"})
  },
}

// ── Mascots (SVG drawn part by part) ───────────────────────────────────

// xray:mascot
export const Mascot = {
  mounted() {
    this.setup()
  },

  updated() {
    // Channel surfing swaps the whole drawing; otherwise just catch up.
    if (this.el.dataset.show !== this.show) this.setup()
    else this.sync()
  },

  setup() {
    this.show = this.el.dataset.show
    this.svg = $(this.el, "svg")
    this.figure = $(this.svg, ".figure")
    this.parts = $$(this.svg, "[data-part]")
    this.lose = $(this.svg, ".fx-lose")
    this.round = this.el.dataset.round
    this.drawn = 0
    this.status = "playing"

    // Measure every outline so it can be "drawn" with stroke-dashoffset.
    for (const ink of $$(this.svg, ".ink, [data-frame] path")) {
      const len = Math.ceil(ink.getTotalLength?.() || 400)
      ink.style.strokeDasharray = len
      ink.dataset.len = len
    }
    gsap.set(this.parts, {autoAlpha: 0})
    gsap.set(this.lose, {autoAlpha: 0})
    this.drawFrame()
    this.sync()
  },

  sync() {
    const mistakes = Number(this.el.dataset.mistakes)
    const status = this.el.dataset.status

    if (this.el.dataset.round !== this.round) this.reset()

    for (let i = this.drawn; i < mistakes; i++) this.reveal(this.parts[i], (i - this.drawn) * 0.15)
    this.drawn = Math.max(this.drawn, mistakes)

    if (status !== this.status) {
      this.status = status
      if (status === "lost") ENDINGS[this.show]?.lose(this)
      if (status === "won") ENDINGS[this.show]?.win(this)
    }
  },
  // xray:end

  drawFrame() {
    const lines = $$(this.svg, "[data-frame] path, path[data-frame], [data-frame].ink")
    gsap.fromTo(
      lines,
      {strokeDashoffset: (_i, el) => el.dataset.len},
      {strokeDashoffset: 0, duration: 0.7, stagger: 0.08, ease: "power2.inOut", delay: 0.9},
    )
  },

  reveal(part, delay = 0) {
    if (!part) return
    part.classList.add("is-drawn")
    const inks = $$(part, ".ink")
    const fills = $$(part, "[fill]").filter((el) => el.getAttribute("fill") !== "none")
    gsap.timeline({delay})
      .set(part, {autoAlpha: 1})
      .fromTo(inks, {strokeDashoffset: (_i, el) => el.dataset.len}, {strokeDashoffset: 0, duration: 0.5, ease: "power2.out"})
      .fromTo(fills, {fillOpacity: 0}, {fillOpacity: 1, duration: 0.35, ease: "power1.out"}, 0.2)
      .fromTo(part, {scale: 0.92, transformOrigin: "50% 50%"}, {scale: 1, duration: 0.5, ease: "back.out(2)"}, 0)
  },

  reset() {
    this.round = this.el.dataset.round
    this.drawn = 0
    this.status = "playing"
    const everything = [this.figure, this.lose, ...$$(this.svg, ".figure *")]
    gsap.killTweensOf(everything)
    gsap.set(everything, {clearProps: "transform,filter"})
    this.parts.forEach((p) => p.classList.remove("is-drawn"))
    gsap.to(this.parts, {autoAlpha: 0, duration: 0.25})
    gsap.set(this.lose, {autoAlpha: 0})
  },
}

// Per-show endings. `m` is the Mascot hook instance.
const pop = (el, delay) =>
  gsap.fromTo(el, {autoAlpha: 0, scale: 0.6, transformOrigin: "50% 50%"}, {autoAlpha: 1, scale: 1, duration: 0.6, delay, ease: "back.out(2.2)"})

const ENDINGS = {
  friends: {
    // Marcel lets go of the rope and heads for the zoo.
    lose(m) {
      gsap.to(m.figure, {y: 320, rotation: 28, svgOrigin: "156 120", duration: 1.1, delay: 0.5, ease: "power2.in"})
      pop(m.lose, 1.5)
    },
    win(m) {
      gsap.fromTo(m.figure, {rotation: -9}, {rotation: 9, svgOrigin: "119 24", duration: 0.45, yoyo: true, repeat: 5, ease: "sine.inOut"})
    },
  },
  big_bang: {
    // Orbits spin up, then: bang.
    lose(m) {
      const orbits = $$(m.svg, ".orbit")
      gsap.to(orbits, {rotation: 720, svgOrigin: "120 122", duration: 1.2, delay: 0.4, ease: "power3.in", stagger: 0.05})
      gsap.to(m.figure, {autoAlpha: 0, scale: 1.6, svgOrigin: "120 122", duration: 0.3, delay: 1.55})
      gsap.fromTo(m.lose, {autoAlpha: 0}, {autoAlpha: 1, duration: 0.1, delay: 1.5})
      gsap.fromTo($(m.lose, ".burst"), {scale: 0, svgOrigin: "120 126"}, {scale: 1, svgOrigin: "120 126", duration: 0.5, delay: 1.5, ease: "expo.out"})
      gsap.fromTo($(m.lose, ".bang-text"), {scale: 0.3, svgOrigin: "120 132"}, {scale: 1, svgOrigin: "120 132", duration: 0.7, delay: 1.6, ease: "back.out(3)"})
    },
    win(m) {
      $$(m.svg, ".orbit").forEach((orbit, i) =>
        gsap.to(orbit, {rotation: 360, svgOrigin: "120 122", duration: 3 + i, repeat: -1, ease: "none"}),
      )
    },
  },
  modern_family: {
    // Fizbo arrives in full: honk, then the smile turns upside down.
    lose(m) {
      pop(m.lose, 0.4)
      gsap.fromTo(m.figure, {x: -6}, {x: 0, duration: 0.8, delay: 0.4, ease: "elastic.out(1.5, 0.2)"})
      gsap.to($(m.svg, ".mouth"), {scaleY: -1, svgOrigin: "120 162", duration: 0.5, delay: 1.1, ease: "back.out(2)"})
    },
    win(m) {
      gsap.fromTo(m.figure, {y: 0}, {y: -14, duration: 0.3, yoyo: true, repeat: 5, ease: "power2.out"})
      gsap.fromTo($(m.svg, ".hat"), {rotation: 0}, {rotation: -22, svgOrigin: "120 92", duration: 0.35, yoyo: true, repeat: 3, ease: "power2.out"})
    },
  },
  brooklyn_99: {
    // Cheddar gets booked: the placard slides up.
    lose(m) {
      gsap.fromTo(m.lose, {autoAlpha: 0, y: 50}, {autoAlpha: 1, y: 0, duration: 0.7, delay: 0.5, ease: "back.out(1.6)"})
      gsap.fromTo(m.figure, {x: -5}, {x: 0, duration: 0.8, delay: 0.5, ease: "elastic.out(1.5, 0.2)"})
    },
    win(m) {
      gsap.fromTo($(m.svg, ".tail"), {rotation: -25}, {rotation: 25, svgOrigin: "72 184", duration: 0.16, yoyo: true, repeat: 11, ease: "sine.inOut"})
      gsap.fromTo(m.figure, {y: 0}, {y: -8, duration: 0.25, yoyo: true, repeat: 3, ease: "power2.out"})
    },
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
    const items = $$(card, ".kicker, .result-title, .result-line, .result-label, .result-word, .result-fact, .result-stat, .result-actions")
    const all = [this.el, card, ...items]

    // Explicit end states + clearProps: the dialog can never get stuck
    // half-faded, whatever else is animating when it opens.
    this.tl = gsap.timeline({delay: won ? 1.2 : 2.2, onComplete: () => gsap.set(all, {clearProps: "all"})})
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
        delay: won ? 1.6 : 2.6,
        ease: "power2.out",
        onUpdate: () => (points.textContent = `+${Math.round(counter.v)}`),
      })
    }
  },
}
