# Hangman · in Phoenix

A real-time word game built with **Elixir**, **Phoenix LiveView**, **GSAP** and **Three.js**.
Guess the word one letter at a time; every miss puts out one of six flames.

**Play:** https://harshitha-upadhyayula.vercel.app/hangman

- Six categories (Classic, Animals, Food, Countries, Tech, Space) and three difficulties
- Physical keyboard support (`a`–`z` to guess, `Enter` next word, `?` hint, `Esc` menu)
- Score, streaks and win rate, kept in `localStorage` and re-validated on the server
- Animated chalk-drawn gallows, flipping letter tiles and a WebGL ember field that reacts to every guess
- Respects `prefers-reduced-motion`, works on phones, and degrades gracefully without WebGL

## How it's built

| Layer | What |
| --- | --- |
| Game rules | `Hangman.Game`: a pure, immutable struct with fully unit-tested rules |
| Words | `Hangman.Words`: word lists in `priv/words/*.txt`, compiled into the module |
| UI | `HangmanWeb.GameLive`: one LiveView; pushes `fx` events describing each move |
| Motion | `assets/js/hooks/board.js` (GSAP) and `assets/js/ember_field.js` (Three.js, lazy-loaded) |
| Styling | Tailwind CSS v4 with a small set of design tokens in `assets/css/app.css` |

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
