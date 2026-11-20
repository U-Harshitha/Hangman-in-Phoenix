// Mounts the Three.js ember background. Three.js is ~150 KB gzipped, so it
// is code-split and loaded after the game is already interactive.
export const Scene = {
  mounted() {
    this.handleEvent("fx", (fx) => this.field?.react(fx))

    import("../ember_field")
      .then(({EmberField}) => {
        if (this.gone) return
        this.field = new EmberField(this.el)
        this.el.animate([{opacity: 0}, {opacity: 1}], {duration: 1200, easing: "ease-out"})
      })
      .catch((err) => {
        // No WebGL (old device, disabled GPU): the CSS gradient still looks fine.
        console.warn("Ember background disabled:", err)
      })
  },

  destroyed() {
    this.gone = true
    this.field?.destroy()
  },
}
