// Phoenix + LiveView client, plus the animation layer.
//
// The server (lib/hangman_web/live/game_live.ex) owns all game state and
// pushes small "fx" events describing what just happened. Everything here
// is presentation: GSAP timelines for the board, Three.js for the embers.
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

import {Scene} from "./hooks/scene"
import {Intro, Board, Gallows, Result} from "./hooks/board"
import {loadStats, saveStats} from "./stats"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/hangman/live", Socket, {
  // Vercel rewrites can't proxy WebSockets, so through the portfolio
  // domain the socket falls back to HTTP long-polling after this delay.
  longPollFallbackMs: 1500,
  params: () => ({_csrf_token: csrfToken, stats: loadStats()}),
  hooks: {Scene, Intro, Board, Gallows, Result},
})

window.addEventListener("phx:stats", (e) => saveStats(e.detail))

liveSocket.connect()
window.liveSocket = liveSocket
