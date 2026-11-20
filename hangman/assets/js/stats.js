// Player totals live in localStorage so they survive reloads; the server
// re-validates whatever we send on connect (Hangman.Stats.from_params/1).
const KEY = "hangman:stats:v1"

export function loadStats() {
  try {
    return JSON.parse(localStorage.getItem(KEY)) || {}
  } catch (_e) {
    return {}
  }
}

export function saveStats(stats) {
  try {
    localStorage.setItem(KEY, JSON.stringify(stats))
  } catch (_e) {
    // Private mode / storage disabled: stats just won't persist.
  }
}
