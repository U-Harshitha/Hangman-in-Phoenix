# Sitcom Hangman · built in Phoenix

A sitcom trivia word game built with **Elixir**, **Phoenix LiveView**, **GSAP** and **Three.js**,
plus an **X-ray mode** that opens up the page and shows how Phoenix makes it work.

**Play:** https://harshitha-upadhyayula.vercel.app/hangman

## The channels

| CH | Show | Instead of a hangman… | You lose when… |
| --- | --- | --- | --- |
| 01 | Friends | Marcel hangs from a rope above the orange couch | he lets go and heads for the San Diego Zoo |
| 02 | The Big Bang Theory | an atom builds up on Sheldon's whiteboard | it reaches critical mass: **BANG!** |
| 03 | Modern Family | Fizbo the clown assembles himself on the lawn | Fizbo arrives (HONK) |
| 04 | Brooklyn Nine-Nine | Cheddar wanders into a police lineup | Cheddar gets booked |
| 00 | Channel surf | a different show every episode | |

- 160+ trivia answers, each with a clue that doubles as a fun fact (`priv/words/<show>.txt`, one `answer | clue` per line)
- Styled to sit next to the portfolio: the same light studio, type (Bricolage Grotesque,
  Instrument Sans, JetBrains Mono, Kalam), haldi accent and part colours (one per show)
- A TV guide with a gliding remote cursor and programme progress, and a retro TV with rabbit ears,
  a channel dial that turns to the current channel, static between channels and an on-screen display
- Laptop keycaps for the keyboard (hits turn haldi, misses stay pressed down) and keycap slots for
  the answer: a found letter rises out of its slot and clicks into place
- Per-episode title cards ("The One With the Missing Letters") and closed-caption audience reactions
- Each channel recolours the guide, the lower third and the Three.js light motes (Brooklyn gets sirens)
- Keyboard play: `a`–`z` guess, `Enter` next episode, `?` hint, `Esc` back, `←`/`→` change channel
- Score and streaks in `localStorage`, re-validated on the server

All artwork is original. The shows are referenced through trivia, with no official logos, fonts or music.

## X-ray mode

Press **X-ray** in the header and the page turns into a blueprint (same teal, dashed outlines and
labels as the portfolio's own X-ray):

- **Inside**: ten numbered pins on the game explain what each part does in Phoenix. Each pin shows
  the real code behind it, which is extracted from the source files at compile time
  (`HangmanWeb.Xray.Source`), so it can't drift from what's running.
- **Trace**: one key press followed end to end (keydown, event up, your process's mailbox,
  `Game.guess/2`, HEEx re-render, diff down, DOM patch, animation) with live numbers: bytes each way,
  round trip, and the server's own `handle_event` and render times. Those come from the `:telemetry`
  events LiveView already emits (`HangmanWeb.Xray.Telemetry`), plus the raw JSON that crossed the wire.
- **Why Phoenix**: what the BEAM and LiveView bring, each with proof from the page: your process's
  memory and reductions, the **live supervision chain** above your game, a **"Crash my process"**
  button (your process dies, the browser rejoins a fresh one and tells you how long it took), the
  first-render vs per-guess diff sizes, the JavaScript actually downloaded, and a comparison with
  the usual SPA + JSON API approach.
- **Live process facts**: the Erlang PID serving *your* game, its memory, the number of processes on
  the node, and whether you're on a WebSocket or long-polling (through Vercel it's long-polling).
- **Live wire**: every message between the browser and the server, with byte sizes and round-trip
  times. You can watch a key press go up as a tiny event and come back as a small diff.
- **Lessons**: what I learned from picking up Phoenix and Elixir for this project. Edit them in
  `lib/hangman_web/xray.ex` (`@lessons`).

## How it's built

| Layer | What |
| --- | --- |
| Game rules | `Hangman.Game`: a pure, immutable struct with fully unit-tested rules |
| Content | `Hangman.Shows`: channels, catchphrases and trivia compiled in from `priv/words/` |
| UI | `HangmanWeb.GameLive`: one LiveView that pushes `fx` events describing each move |
| Mascots | `HangmanWeb.Mascots`: SVG sets drawn part by part by a GSAP hook |
| Motion | `assets/js/hooks/*.js` (GSAP) and `assets/js/ember_field.js` (Three.js, lazy-loaded) |
| X-ray | `HangmanWeb.Xray` (content, live BEAM stats, supervision chain), `HangmanWeb.Xray.Telemetry` (server timings) and `assets/js/wire.js` (socket traffic) |

Everything is served under the `/hangman` path, so the app can sit behind the portfolio's domain.

## Run it locally (optional)

Requires Elixir 1.15+ and Node 18+.

```bash
cd hangman
mix setup          # deps, npm packages (GSAP, Three.js), asset build
mix phx.server     # http://localhost:4000/hangman
mix test           # unit + LiveView tests
```

## Deployment

Vercel can't run Elixir/BEAM servers, so the game runs on **Render** (free plan, Docker) and the
portfolio on Vercel **proxies** `/hangman` to it. Visitors only ever see the portfolio's URL.

```
browser ──► harshitha-upadhyayula.vercel.app/hangman ──(Vercel rewrite)──► <render-app>.onrender.com/hangman
```

### 1. Render (one-time, in the browser)

1. Sign in at https://dashboard.render.com with GitHub.
2. **New → Blueprint**, pick this repository and branch, then click **Apply**. `render.yaml` configures
   everything: the Docker build, the health check, and a generated `SECRET_KEY_BASE`.
3. Note the service URL, e.g. `https://hangman-in-phoenix.onrender.com`.

### 2. Vercel (in the portfolio repository)

Add these rewrites to the portfolio's `vercel.json`, before any catch-all SPA rewrite, then redeploy.
Replace the host with your Render URL:

```json
{
  "rewrites": [
    { "source": "/hangman", "destination": "https://hangman-in-phoenix.onrender.com/hangman" },
    { "source": "/hangman/:path*", "destination": "https://hangman-in-phoenix.onrender.com/hangman/:path*" }
  ]
}
```

Then link to it from the portfolio, e.g. `<a href="/hangman">Play Hangman</a>`. Use a normal link,
not client-side routing, so the browser actually requests `/hangman`.

> Vercel rewrites don't proxy WebSockets, so through the portfolio domain LiveView automatically
> falls back to HTTP long-polling. CI tests that path.

### 3. Optional: keep it warm

Free Render services sleep after 15 idle minutes, and the first visit then takes about 30–60 s. To
avoid that, set the repository variable `HANGMAN_URL` to your Render URL (GitHub → Settings → Secrets
and variables → Actions → Variables). The `Keep warm` workflow then pings the server every 10 minutes.

### Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `SECRET_KEY_BASE` | *(required)* | Signs cookies/sessions. Render generates it. |
| `CHECK_ORIGINS` | `//harshitha-upadhyayula.vercel.app` | Extra origins allowed to connect (comma separated) |
| `PORTFOLIO_URL` | `https://harshitha-upadhyayula.vercel.app` | Target of the "← Portfolio" link |
| `PHX_HOST` | Render's hostname | Public host of the server itself |
| `BIND_IPV6` | `false` | Bind `::` instead of `0.0.0.0` (e.g. on Fly.io) |
