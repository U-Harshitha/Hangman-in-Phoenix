// The TV bits: analogue static between channels, and the episode title
// card that opens every round.
import {gsap, reducedMotion} from "../motion"

// Paint random grey noise on a small canvas (CSS scales it up, pixelated)
// for `ms` milliseconds, or until stopped. Returns a stop function.
export function playStatic(canvas, ms = 400, {loop = false} = {}) {
  if (!canvas) return () => {}
  const ctx = canvas.getContext("2d")
  canvas.width = 160
  canvas.height = 100
  const img = ctx.createImageData(canvas.width, canvas.height)
  let raf
  const start = performance.now()

  const frame = (now) => {
    const px = img.data
    for (let i = 0; i < px.length; i += 4) {
      const v = (Math.random() * 255) | 0
      px[i] = px[i + 1] = px[i + 2] = v
      px[i + 3] = 255
    }
    ctx.putImageData(img, 0, 0)
    if (loop || now - start < ms) raf = requestAnimationFrame(frame)
  }

  gsap.set(canvas, {autoAlpha: 1})
  raf = requestAnimationFrame(frame)
  const stop = () => {
    cancelAnimationFrame(raf)
    gsap.to(canvas, {autoAlpha: 0, duration: 0.2})
  }
  if (!loop) setTimeout(stop, ms)
  return stop
}

export const Tv = {
  mounted() {
    this.channel = this.el.dataset.channel
    this.tune(true)
  },

  updated() {
    if (this.el.dataset.channel !== this.channel) {
      this.channel = this.el.dataset.channel
      this.tune(false)
    }
  },

  // Switching channels: a burst of static and a CRT "roll".
  tune(first) {
    this.stopSurf?.()
    const canvas = this.el.querySelector(".tv-static")
    const picture = this.el.querySelector(".tv-picture")

    if (this.channel === "surf") {
      this.wiggle(first)
      this.stopSurf = playStatic(canvas, 0, {loop: !reducedMotion()})
      gsap.set(canvas, {autoAlpha: 0.55})
      return
    }

    this.wiggle(first)
    playStatic(canvas, first ? 500 : 320)
    gsap.fromTo(
      picture,
      {scaleY: 0.02, scaleX: 1.1, filter: "brightness(3)"},
      {scaleY: 1, scaleX: 1, filter: "brightness(1)", duration: 0.45, delay: first ? 0.35 : 0.18, ease: "expo.out", clearProps: "all"},
    )
    gsap.fromTo(this.el.querySelector(".tv-lower-third"), {xPercent: -12, opacity: 0}, {xPercent: 0, opacity: 1, duration: 0.5, delay: 0.3, ease: "power3.out", clearProps: "all"})
  },

  // The rabbit ears wobble when the channel changes, and the OSD number
  // pops up then fades, like a real set.
  wiggle(first) {
    const [left, right] = this.el.querySelectorAll(".tv-antenna i")
    if (left && !first) {
      gsap.fromTo(left, {rotation: -38}, {rotation: -28, transformOrigin: "50% 100%", duration: 1.1, ease: "elastic.out(1.3, 0.25)"})
      gsap.fromTo(right, {rotation: 32}, {rotation: 22, transformOrigin: "50% 100%", duration: 1.2, ease: "elastic.out(1.3, 0.22)"})
    }
    gsap.fromTo(
      this.el.querySelector(".tv-osd"),
      {autoAlpha: 1},
      {autoAlpha: 0, duration: 0.5, delay: first ? 2.4 : 1.8, ease: "power1.in", overwrite: true},
    )
  },

  destroyed() {
    this.stopSurf?.()
  },
}

export const TitleCard = {
  mounted() {
    const q = (s) => this.el.querySelector(s)
    playStatic(q(".tv-static"), 380)
    gsap.timeline({delay: 0.25})
      .from(q(".tc-osd"), {x: -24, opacity: 0, duration: 0.35, ease: "power2.out"})
      .from(q(".tc-show"), {y: 18, opacity: 0, duration: 0.45, ease: "power3.out"}, "<0.1")
      .from(q(".tc-title"), {y: 26, opacity: 0, scale: 0.96, duration: 0.6, ease: "back.out(1.8)"}, "<0.12")
      .from(q(".tc-ep"), {opacity: 0, duration: 0.4}, "<0.25")
  },
}
