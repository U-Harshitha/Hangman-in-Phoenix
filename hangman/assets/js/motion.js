import {gsap} from "gsap"

export const reducedMotion = () =>
  window.matchMedia("(prefers-reduced-motion: reduce)").matches

// One place to tone everything down for people who asked for less motion.
if (reducedMotion()) gsap.globalTimeline.timeScale(4)

export {gsap}
