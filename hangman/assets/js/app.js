// Phoenix + LiveView client, plus the animation layer.
//
// The server (lib/hangman_web/live/game_live.ex) owns all game state and
// pushes small "fx" events describing what just happened. Everything here
// is presentation: GSAP for the board, Three.js for the background, and the
// instrumentation behind X-ray mode.
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

import {Scene} from "./hooks/scene"
import {Intro, Guide, Board, Mascot, Result} from "./hooks/board"
import {Tv, TitleCard} from "./hooks/tv"
import {XrayScan, Wire, Transport, Trace, DiffStats, JsStats, Crash, showTransport, takeCrash} from "./hooks/xray"
import {wire} from "./wire"
import {loadStats, saveStats} from "./stats"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/hangman/live", Socket, {
  // Vercel rewrites can't proxy WebSockets, so through the portfolio
  // domain the socket falls back to HTTP long-polling after this delay.
  longPollFallbackMs: 1500,
  // Called on every join, including the rejoin after the X-ray crash demo.
  params: () => ({_csrf_token: csrfToken, stats: loadStats(), crash: takeCrash()}),
  hooks: {Scene, Intro, Guide, Board, Mascot, Result, Tv, TitleCard, XrayScan, Wire, Transport, Trace, DiffStats, JsStats, Crash},
})

wire.attach(liveSocket)
liveSocket.socket.onOpen(() => setTimeout(showTransport, 50))
window.addEventListener("phx:stats", (e) => saveStats(e.detail))
window.addEventListener("phx:xray_trace", (e) => wire.serverTiming(e.detail))

liveSocket.connect()
window.liveSocket = liveSocket
