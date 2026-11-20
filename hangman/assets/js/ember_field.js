// Soft motes of coloured light drifting up through the studio, rendered
// with Three.js behind the whole app.
//
// It's a single THREE.Points draw call; motion happens in the vertex
// shader, so the CPU only advances one clock. Game events nudge a few
// uniforms (speed, size, colour) with GSAP for the mood changes. On the
// light studio background they're blended normally (not additively), so
// they read as out-of-focus confetti in the channel's colour.
import {
  BufferAttribute,
  NormalBlending,
  BufferGeometry,
  Color,
  PerspectiveCamera,
  Points,
  Scene as ThreeScene,
  ShaderMaterial,
  WebGLRenderer,
} from "three"
import {gsap, reducedMotion} from "./motion"

const HEIGHT = 34
// Each channel has its own palette; "calm" is whichever show is on air.
const THEMES = {
  friends: {a: "#8e5bd8", b: "#f2b705"},
  big_bang: {a: "#3a9ad9", b: "#8fd0f5"},
  modern_family: {a: "#4caf50", b: "#f2b705"},
  brooklyn_99: {a: "#3a86ff", b: "#f2b705", siren: true},
  surf: {a: "#8e5bd8", b: "#3a9ad9"},
}

const MOODS = {
  calm: {a: "#8e5bd8", b: "#f2b705"},
  miss: {a: "#e5432f", b: "#ff8a6b"},
  win: {a: "#f2b705", b: "#ffcd2e"},
  lose: {a: "#8b8a93", b: "#b5b4bb"},
}

const BASE = 0.42

const vertexShader = /* glsl */ `
  uniform float uTime;
  uniform float uSize;
  uniform float uPixelRatio;
  uniform float uHeight;
  attribute float aSeed;
  attribute float aSpeed;
  varying float vSeed;
  varying float vLife;

  void main() {
    vec3 p = position;
    float t = uTime * aSpeed;
    p.y = mod(p.y + t + uHeight * 0.5, uHeight) - uHeight * 0.5;
    p.x += sin(t * 0.35 + aSeed * 6.2831) * 0.9 + sin(t * 1.3 + aSeed * 40.0) * 0.12;
    p.z += cos(t * 0.3 + aSeed * 12.0) * 0.6;

    vLife = 1.0 - smoothstep(0.0, 1.0, (p.y + uHeight * 0.5) / uHeight);
    vSeed = aSeed;

    vec4 mv = modelViewMatrix * vec4(p, 1.0);
    gl_Position = projectionMatrix * mv;
    float flicker = 0.75 + 0.25 * sin(uTime * (3.0 + aSeed * 5.0) + aSeed * 100.0);
    gl_PointSize = uSize * (0.35 + aSeed * 0.9) * flicker * uPixelRatio * (24.0 / -mv.z);
  }
`

const fragmentShader = /* glsl */ `
  uniform vec3 uColorA;
  uniform vec3 uColorB;
  uniform float uIntensity;
  varying float vSeed;
  varying float vLife;

  void main() {
    float d = length(gl_PointCoord - 0.5);
    float core = smoothstep(0.5, 0.0, d);
    float glow = pow(core, 2.2);
    vec3 color = mix(uColorA, uColorB, vSeed * 0.8 + glow * 0.4);
    float alpha = core * (0.2 + 0.8 * vLife) * uIntensity;
    if (alpha < 0.01) discard;
    gl_FragColor = vec4(color, alpha);
  }
`

export class EmberField {
  constructor(container) {
    this.container = container
    this.renderer = new WebGLRenderer({antialias: false, alpha: true, powerPreference: "low-power"})
    this.renderer.setClearColor(0x000000, 0)
    container.appendChild(this.renderer.domElement)

    this.scene = new ThreeScene()
    this.camera = new PerspectiveCamera(55, 1, 0.1, 100)
    this.camera.position.set(0, 0, 18)

    const count = window.innerWidth < 640 ? 120 : 260
    const positions = new Float32Array(count * 3)
    const seeds = new Float32Array(count)
    const speeds = new Float32Array(count)
    for (let i = 0; i < count; i++) {
      positions[i * 3] = (Math.random() - 0.5) * 46
      positions[i * 3 + 1] = (Math.random() - 0.5) * HEIGHT
      positions[i * 3 + 2] = (Math.random() - 0.5) * 18
      seeds[i] = Math.random()
      speeds[i] = 0.6 + Math.random() * 1.4
    }
    const geometry = new BufferGeometry()
    geometry.setAttribute("position", new BufferAttribute(positions, 3))
    geometry.setAttribute("aSeed", new BufferAttribute(seeds, 1))
    geometry.setAttribute("aSpeed", new BufferAttribute(speeds, 1))

    this.uniforms = {
      uTime: {value: 0},
      uSize: {value: 11},
      uPixelRatio: {value: Math.min(window.devicePixelRatio, 2)},
      uHeight: {value: HEIGHT},
      uIntensity: {value: BASE},
      uColorA: {value: new Color(MOODS.calm.a)},
      uColorB: {value: new Color(MOODS.calm.b)},
    }
    this.material = new ShaderMaterial({
      uniforms: this.uniforms,
      vertexShader,
      fragmentShader,
      transparent: true,
      depthWrite: false,
      blending: NormalBlending,
    })
    this.points = new Points(geometry, this.material)
    this.scene.add(this.points)

    this.speed = 1 // multiplier tweened by events; integrated into uTime
    this.pointer = {x: 0, y: 0}
    this.clock = performance.now()

    this.onResize = () => this.resize()
    this.onPointer = (e) => {
      this.pointer.x = e.clientX / window.innerWidth - 0.5
      this.pointer.y = e.clientY / window.innerHeight - 0.5
    }
    this.onVisibility = () => (document.hidden ? this.stop() : this.start())
    window.addEventListener("resize", this.onResize)
    window.addEventListener("pointermove", this.onPointer, {passive: true})
    document.addEventListener("visibilitychange", this.onVisibility)

    this.resize()
    if (reducedMotion()) {
      this.uniforms.uTime.value = 12
      this.render()
    } else {
      this.start()
    }
  }

  resize() {
    const {innerWidth: w, innerHeight: h} = window
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    this.renderer.setSize(w, h, false)
    this.renderer.domElement.style.width = "100%"
    this.renderer.domElement.style.height = "100%"
    this.camera.aspect = w / h
    this.camera.updateProjectionMatrix()
    if (reducedMotion()) this.render()
  }

  start() {
    if (this.raf || reducedMotion()) return
    this.clock = performance.now()
    const tick = (now) => {
      const dt = Math.min((now - this.clock) / 1000, 0.05)
      this.clock = now
      this.uniforms.uTime.value += dt * this.speed
      this.camera.position.x += (this.pointer.x * 2.4 - this.camera.position.x) * 0.03
      this.camera.position.y += (-this.pointer.y * 1.6 - this.camera.position.y) * 0.03
      this.camera.lookAt(0, 0, 0)
      this.render()
      this.raf = requestAnimationFrame(tick)
    }
    this.raf = requestAnimationFrame(tick)
  }

  stop() {
    cancelAnimationFrame(this.raf)
    this.raf = null
  }

  render() {
    this.renderer.render(this.scene, this.camera)
  }

  // Switch channel palette. Brooklyn gets red/blue siren pulses.
  theme(show) {
    const theme = THEMES[show]
    if (!theme) return
    MOODS.calm = theme
    this.siren?.kill()
    this.siren = null
    this.mood("calm", 1)
  }

  startSiren(delay) {
    if (!MOODS.calm.siren) return
    this.siren?.kill()
    const red = new Color("#ff3b3b")
    this.siren = gsap.to(this.uniforms.uColorB.value, {r: red.r, g: red.g, b: red.b, duration: 0.55, yoyo: true, repeat: -1, ease: "steps(1)", delay})
  }

  mood(name, duration = 0.8) {
    const {a, b} = MOODS[name]
    const ca = new Color(a)
    const cb = new Color(b)
    gsap.to(this.uniforms.uColorA.value, {r: ca.r, g: ca.g, b: ca.b, duration, overwrite: "auto"})
    gsap.to(this.uniforms.uColorB.value, {r: cb.r, g: cb.g, b: cb.b, duration, overwrite: "auto"})
    if (name === "calm") this.startSiren(duration)
  }

  surge(speed, size, duration = 1.2) {
    gsap.timeline({defaults: {overwrite: "auto"}})
      .to(this, {speed, duration: 0.25, ease: "power2.out"})
      .to(this.uniforms.uSize, {value: size, duration: 0.25, ease: "power2.out"}, 0)
      .to(this, {speed: 1, duration, ease: "power2.inOut"})
      .to(this.uniforms.uSize, {value: 11, duration, ease: "power2.inOut"}, "<")
  }

  react({kind, show}) {
    if (show && (kind === "start" || kind === "menu" || kind === "channel")) this.theme(show)

    switch (kind) {
      case "channel":
        this.mood("calm", 0.6)
        this.surge(4, 14, 0.8)
        break
      case "start":
      case "menu":
        this.mood("calm", 1.2)
        gsap.to(this.uniforms.uIntensity, {value: BASE, duration: 1})
        this.surge(2.2, 13, 1.4)
        break
      case "hit":
      case "hint":
        this.surge(3.2, 14)
        break
      case "miss":
        this.mood("miss", 0.15)
        gsap.delayedCall(0.45, () => this.mood("calm", 1))
        this.surge(0.4, 10, 1)
        break
      case "win":
        this.mood("win", 0.4)
        gsap.to(this.uniforms.uIntensity, {value: 0.75, duration: 0.4})
        this.surge(7, 18, 3)
        break
      case "lose":
        this.mood("lose", 1.6)
        gsap.to(this.uniforms.uIntensity, {value: 0.22, duration: 1.6})
        this.surge(0.25, 9, 2.5)
        break
    }
  }

  destroy() {
    this.siren?.kill()
    this.stop()
    window.removeEventListener("resize", this.onResize)
    window.removeEventListener("pointermove", this.onPointer)
    document.removeEventListener("visibilitychange", this.onVisibility)
    this.points.geometry.dispose()
    this.material.dispose()
    this.renderer.dispose()
    this.renderer.domElement.remove()
  }
}
