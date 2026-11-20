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
    lib/hangman_web/xray/telemetry.ex
    assets/js/hooks/board.js
  )
  for file <- @files, do: @external_resource(Source.path(file))

  # Line counts for the "Why Phoenix" tab, taken at compile time.
  @elixir_files ~w(
    lib/hangman/game.ex lib/hangman/shows.ex lib/hangman/stats.ex
    lib/hangman_web/live/game_live.ex lib/hangman_web/components/mascots.ex
  )
  @js_files Path.wildcard(Source.path("assets/js/**/*.js"))
  for file <- @js_files, do: @external_resource(file)

  count_lines = fn files ->
    files
    |> Enum.flat_map(&(&1 |> File.read!() |> String.split("\n")))
    |> Enum.count(&(String.trim(&1) != ""))
  end

  @loc %{
    elixir: count_lines.(Enum.map(@elixir_files, &Source.path/1)),
    js: count_lines.(@js_files)
  }

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
    },
    %{
      id: "timers",
      n: 9,
      title: "Timers are just messages",
      body: """
      The episode title card hides itself without any JavaScript timer. When
      a round starts, the process sends itself a message for 2.1 s later with
      `Process.send_after/3`. It arrives in the mailbox like any click would,
      and pattern matching on the round number ignores stale ones.
      """,
      file: "lib/hangman_web/live/game_live.ex",
      code: Source.marked("lib/hangman_web/live/game_live.ex", "timers")
    },
    %{
      id: "channel",
      n: 10,
      title: "Clicks and keys, one code path",
      body: """
      Clicking a row sends `pick_channel`; arrow keys arrive as `key` events
      from `phx-window-keydown`. Both end up in the same `step_channel`, and a
      single `cond` maps every key in the game to what it should do.
      """,
      file: "lib/hangman_web/live/game_live.ex",
      code: Source.marked("lib/hangman_web/live/game_live.ex", "keys")
    }
  ]

  # One key press, end to end (the Trace tab). `slot` names the live number
  # the Trace hook fills in from real traffic and telemetry.
  @trace_steps [
    %{
      where: "browser",
      label: "Browser",
      title: "You press a key",
      body: """
      `phx-window-keydown` on the page catches it. The keycap goes down right
      away; that bit is plain CSS, so it never waits for the server.
      """,
      slot: "key"
    },
    %{
      where: "wire",
      label: "Network, going up",
      title: "A tiny event goes up",
      body: """
      LiveView's client sends the event name and the key over the socket
      that's already open. No HTTP request, no API route you had to design.
      """,
      slot: "up"
    },
    %{
      where: "server",
      label: "Server, your process",
      title: "It lands in your process's mailbox",
      body: """
      Only the process holding *your* game receives it, and
      `handle_event("key", …)` pattern-matches what to do. `Game.guess/2`
      returns `{:hit, game}` or `{:miss, game}`, a brand-new struct.
      """,
      slot: "event_us"
    },
    %{
      where: "server",
      label: "Server, HEEx",
      title: "Only what changed is re-rendered",
      body: """
      HEEx worked out at compile time which parts of the template depend on
      which assigns. LiveView re-renders just those and diffs them against
      what your browser already has.
      """,
      slot: "render_us"
    },
    %{
      where: "wire",
      label: "Network, coming down",
      title: "A small diff comes back",
      body: """
      The changed tiles, the key's new class and the message, plus a
      `push_event` telling the animations what happened. Never the answer.
      """,
      slot: "down"
    },
    %{
      where: "browser",
      label: "Browser",
      title: "Patched in place, then animated",
      body: """
      LiveView patches the DOM without re-rendering the page, so focus and
      scroll stay put. Then the `Board` and `Mascot` hooks hear the event and
      animate with GSAP.
      """,
      slot: "rtt"
    }
  ]

  @specialities [
    %{
      id: :process,
      title: "One process per player",
      body: """
      Every visitor gets their own lightweight BEAM process that holds their
      game in memory. Each costs a few kilobytes, so one small server can hold
      hundreds of thousands. They share no memory: no locks, and no player can
      touch another's state. The scheduler is preemptive, so one busy player
      can't stall the rest.
      """
    },
    %{
      id: :supervision,
      title: "Let it crash, on purpose",
      body: """
      Processes live in supervision trees. If one fails, it fails alone, its
      supervisor carries on, and the LiveView client rejoins a fresh process by
      itself. This is the real chain above your game, read live from the BEAM.
      Go on, crash it.
      """
    },
    %{
      id: :diffs,
      title: "HTML diffs instead of a JSON API",
      body: """
      The first render sends the page's static HTML once. After that, updates
      carry only the dynamic values that changed, worked out on the server.
      Measured from this tab's own traffic:
      """
    },
    %{
      id: :transport,
      title: "Same code, any transport",
      body: """
      LiveView speaks WebSocket and falls back to HTTP long-polling with
      identical server code. That's what keeps this game alive behind the
      portfolio's Vercel rewrite, which can't proxy WebSockets.
      """
    },
    %{
      id: :telemetry,
      title: "Instrumented out of the box",
      body: """
      LiveView emits `:telemetry` events for every mount, event and render. The
      Trace tab's server timings come from one small handler attached to them
      (`HangmanWeb.Xray.Telemetry`), not from timing code spread through the
      game.
      """
    },
    %{
      id: :js,
      title: "JavaScript where it earns its place",
      body: """
      All state and rules are Elixir. JavaScript only animates, through hooks
      the server cues with `push_event`. The answer never exists in
      JavaScript, and Three.js loads only after the game is playable.
      """
    },
    %{
      id: :compile,
      title: "The compiler does the boring work",
      body: """
      The word banks are compiled into the release, `~p` routes are checked at
      compile time, and the code in this panel was cut out of the real source
      files during compilation, so it can't go stale.
      """
    }
  ]

  @comparison [
    {"Where the answer lives", "In the browser, or behind extra API checks",
     "Only in your server process"},
    {"Endpoints to write", "New game, guess, hint, stats", "None: events hit handle_event/3"},
    {"Client state", "A store kept in sync with the server", "None: the server renders"},
    {"Live updates", "Add a socket library", "Built in"},
    {"Wire format", "JSON you design and version", "HTML diffs LiveView computes"},
    {"A server bug crashes", "A 500; the client must recover", "One process; it's restarted"}
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
  def trace_steps, do: @trace_steps
  def specialities, do: @specialities
  def comparison, do: @comparison
  def loc, do: @loc

  @telemetry_html Source.highlight(
                    Source.marked("lib/hangman_web/xray/telemetry.ex", "telemetry")
                  )
  def telemetry_html, do: @telemetry_html

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
    [memory: memory, reductions: reductions] = Process.info(pid, [:memory, :reductions])
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    %{
      pid: inspect(pid),
      memory_kb: Float.round(memory / 1024, 1),
      reductions: reductions,
      chain: chain(pid),
      processes: :erlang.system_info(:process_count),
      schedulers: System.schedulers_online(),
      uptime: format_uptime(div(uptime_ms, 1000)),
      versions: "Elixir #{System.version()} · OTP #{:erlang.system_info(:otp_release)}"
    }
  end

  @doc """
  The supervisors above `pid`, root first, read from the `$ancestors` that
  OTP's proc_lib records in every process it starts.
  """
  def chain(pid) do
    {:dictionary, dict} = Process.info(pid, :dictionary)

    ancestors =
      dict
      |> Keyword.get(:"$ancestors", [])
      |> Enum.reverse()
      |> Enum.map(&describe/1)
      |> Enum.with_index()
      |> Enum.map(&label/1)

    [%{name: "the BEAM", kind: "the virtual machine"} | ancestors] ++
      [%{name: "you, " <> inspect(pid), kind: "LiveView process"}]
  end

  defp describe(name) when is_atom(name),
    do: %{name: inspect(name), kind: kind(Process.whereis(name))}

  defp describe(pid) when is_pid(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, name} when is_atom(name) and name != [] ->
        %{name: inspect(name), kind: kind(pid)}

      _ ->
        %{name: inspect(pid), kind: kind(pid)}
    end
  end

  defp describe(other), do: %{name: inspect(other), kind: "process"}

  # Unnamed processes in the chain: the application master at the root, and
  # the socket's partition supervisors (one per scheduler) further down.
  defp label({%{name: "#PID" <> _, kind: "process"}, 0}),
    do: %{name: ":hangman", kind: "OTP application"}

  defp label({%{name: "#PID" <> _ = name, kind: "supervisor" <> _ = kind}, _}),
    do: %{name: name, kind: "partition " <> kind}

  defp label({node, _}), do: node

  defp kind(pid) when is_pid(pid) do
    case Process.info(pid, [:dictionary, :links]) do
      [dictionary: dict, links: links] -> kind(Keyword.get(dict, :"$initial_call"), links)
      _ -> "process"
    end
  end

  defp kind(_), do: "process"

  defp kind({:supervisor, Supervisor.Default, _}, links), do: supervises(links)
  defp kind({:supervisor, mod, _}, links), do: "#{short(mod)}, #{supervises(links)}"
  defp kind({:application_master, _, _}, _), do: "starts the :hangman app"
  defp kind({mod, _, _}, _), do: short(mod)
  defp kind(_, _), do: "process"

  # Links minus the parent: roughly how many children it supervises.
  defp supervises(links), do: "supervisor of #{max(length(links) - 1, 1)}"

  defp short(mod), do: mod |> inspect() |> String.replace_prefix(":", "")

  defp format_uptime(s) when s < 3600, do: "#{div(s, 60)}m #{rem(s, 60)}s"
  defp format_uptime(s) when s < 86_400, do: "#{div(s, 3600)}h #{div(rem(s, 3600), 60)}m"
  defp format_uptime(s), do: "#{div(s, 86_400)}d #{div(rem(s, 86_400), 3600)}h"
end
