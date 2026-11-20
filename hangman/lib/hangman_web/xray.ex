defmodule HangmanWeb.Xray do
  @moduledoc """
  Content for X-ray mode: what each part of the page is doing under the
  hood, the real code behind it, and what building this taught me.

  Code excerpts are extracted from the source files at compile time (see
  `HangmanWeb.Xray.Source`), so they can never drift from the real code.
  To change the wording, edit the `@sections` and `@lessons` below.
  """

  alias HangmanWeb.Xray.Source

  @files ~w(
    lib/hangman/game.ex
    lib/hangman/stats.ex
    lib/hangman/application.ex
    lib/hangman_web/endpoint.ex
    lib/hangman_web/live/game_live.ex
    assets/js/hooks/board.js
  )
  for file <- @files, do: @external_resource(Source.path(file))

  @sections [
    %{
      id: "word",
      n: 1,
      title: "The answer never leaves the server",
      body: """
      Your browser only ever receives the masked tiles. The answer lives in an
      Elixir struct inside a server process, so "view source" can't cheat.
      `Game.tiles/1` decides what each tile is allowed to show.
      """,
      file: "lib/hangman/game.ex",
      code: Source.function("lib/hangman/game.ex", :tiles)
    },
    %{
      id: "keyboard",
      n: 2,
      title: "A key press is a message, not a page load",
      body: """
      Each key has `phx-click="guess"` and the page listens with
      `phx-window-keydown`. LiveView sends a tiny event over the socket, the
      server handles it, and only the parts of the HTML that changed come back
      as a diff. Open the Live wire tab and press a letter to watch it happen.
      """,
      file: "lib/hangman_web/live/game_live.ex",
      code: Source.function("lib/hangman_web/live/game_live.ex", :guess)
    },
    %{
      id: "rules",
      n: 3,
      title: "Game rules as a pure function",
      body: """
      `Game.guess/2` takes a game and a letter and returns a tagged tuple such
      as `{:hit, game}` or `{:miss, game}`. No mutation, no database, no side
      effects. Pattern matching turns each rule into one clause, and each
      clause into one unit test.
      """,
      file: "lib/hangman/game.ex",
      code: Source.function("lib/hangman/game.ex", :guess)
    },
    %{
      id: "mascot",
      n: 4,
      title: "Server state, client motion",
      body: """
      The server only says how many mistakes there are (`data-mistakes`). A
      small JavaScript hook watches that attribute and draws the next part with
      GSAP. `phx-update="ignore"` tells LiveView to leave the drawing alone, so
      the animation and the DOM diffs never fight.
      """,
      file: "assets/js/hooks/board.js",
      code: Source.marked("assets/js/hooks/board.js", "mascot")
    },
    %{
      id: "scene",
      n: 5,
      title: "The server cues the special effects",
      body: """
      When a round ends, the LiveView calls `push_event/3` to say what
      happened. The Three.js background (loaded lazily, after the game is
      already playable) listens and changes its mood, and your stats are saved
      to localStorage.
      """,
      file: "lib/hangman_web/live/game_live.ex",
      code: Source.function("lib/hangman_web/live/game_live.ex", :maybe_finish)
    },
    %{
      id: "stats",
      n: 6,
      title: "Trust, but verify",
      body: """
      Your score lives in your browser's localStorage and is sent along when the
      socket connects. The server never trusts it blindly: `Stats.from_params/1`
      throws away anything malformed or impossible (like more wins than games).
      """,
      file: "lib/hangman/stats.ex",
      code: Source.function("lib/hangman/stats.ex", :from_params)
    },
    %{
      id: "process",
      n: 7,
      title: "One player, one process",
      body: """
      Your game runs in its own lightweight Erlang process (its ID is shown at
      the top of this panel). Processes share no memory, so a crash in one game
      can't touch another, and supervisors restart anything that dies. The BEAM
      can run millions of them on one machine.
      """,
      file: "lib/hangman/application.ex",
      code: Source.function("lib/hangman/application.ex", :start)
    },
    %{
      id: "transport",
      n: 8,
      title: "WebSockets, or not",
      body: """
      LiveView prefers a WebSocket. Through the portfolio's Vercel rewrite there
      are no WebSockets, so after 1.5 s the client falls back to HTTP
      long-polling. Same server code, different transport. The badge at the top
      of this panel shows which one you're on right now.
      """,
      file: "lib/hangman_web/endpoint.ex",
      code: Source.marked("lib/hangman_web/endpoint.ex", "socket")
    }
  ]

  # Written in the first person: edit these to say it in your own words.
  @lessons [
    %{
      title: "State can just live on the server",
      body: """
      With LiveView there was no REST API, no client-side store, and nothing to
      keep in sync between them. The game is an Elixir struct in a process and
      the browser renders what it's sent. A whole category of bugs (stale
      client state) simply disappeared.
      """
    },
    %{
      title: "Immutability makes logic boring, in a good way",
      body: """
      Every move returns a brand-new `%Game{}`. Nothing changes behind my back,
      so testing a rule is three steps: build a game, call a function, check
      the result.
      """
    },
    %{
      title: "Say what happened, not just what is",
      body: """
      Returning `{:hit, game}` or `{:miss, game}` instead of only the new state
      meant the UI always knew *why* something changed, which is exactly what
      the animations needed.
      """
    },
    %{
      title: "Processes are a design tool",
      body: """
      Treating each player as an isolated process with its own state and
      mailbox changed how I think about concurrency: no shared memory, no
      locks, and failures stay contained.
      """
    },
    %{
      title: "The network is part of the architecture",
      body: """
      Deploying behind a Vercel rewrite quietly broke WebSockets. LiveView's
      long-polling fallback kept the game working with zero code changes, but
      it taught me to design for the transport I actually get.
      """
    },
    %{
      title: "Let JavaScript do what it's good at",
      body: """
      LiveView owns the state; small hooks own the motion. Keeping GSAP and
      Three.js in hooks, cued by `push_event`, stopped the two worlds from
      fighting over the DOM.
      """
    },
    %{
      title: "Compile time is a feature",
      body: """
      Loading the word lists at compile time fixed a production bug (v1 read
      files relative to the working directory), and it's how the code in this
      X-ray panel is pulled straight from the real source.
      """
    }
  ]

  @sections Enum.map(@sections, &Map.put(&1, :html, Source.highlight(&1.code)))

  def sections, do: @sections
  def lessons, do: @lessons

  def section(id), do: Enum.find(@sections, &(&1.id == id))

  @doc "Inline `code` spans in the plain-text explanations."
  def format(text) do
    text
    |> String.trim()
    |> String.replace("\n", " ")
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace(~r/`([^`]+)`/, "<code>\\1</code>")
    |> String.replace(~r/\*([^*]+)\*/, "<em>\\1</em>")
    |> Phoenix.HTML.raw()
  end

  @doc "Live facts about the BEAM process serving this LiveView."
  def runtime(pid \\ self()) do
    {:memory, memory} = Process.info(pid, :memory)
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    %{
      pid: inspect(pid),
      memory_kb: Float.round(memory / 1024, 1),
      processes: :erlang.system_info(:process_count),
      schedulers: System.schedulers_online(),
      uptime: format_uptime(div(uptime_ms, 1000)),
      versions: "Elixir #{System.version()} · OTP #{:erlang.system_info(:otp_release)}"
    }
  end

  defp format_uptime(s) when s < 3600, do: "#{div(s, 60)}m #{rem(s, 60)}s"
  defp format_uptime(s) when s < 86_400, do: "#{div(s, 3600)}h #{div(rem(s, 3600), 60)}m"
  defp format_uptime(s), do: "#{div(s, 86_400)}d #{div(rem(s, 86_400), 3600)}h"
end
