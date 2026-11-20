defmodule HangmanWeb.GameLive do
  @moduledoc """
  Sitcom Hangman in one LiveView: a TV-guide menu (pick a channel and a
  difficulty), the board, and X-ray mode, which explains how it all works.

  All rules live in `Hangman.Game`. This module turns clicks and key presses
  into moves and pushes "fx" events so the client can animate what just
  happened (GSAP for the board, Three.js for the background).
  """
  use HangmanWeb, :live_view

  alias Hangman.{Game, Shows, Stats}
  alias HangmanWeb.{Mascots, Xray}

  @keyboard ~w(qwertyuiop asdfghjkl zxcvbnm) |> Enum.map(&String.graphemes/1)
  @difficulties [
    {:easy, "Easy", "short · 2 hints"},
    {:normal, "Normal", "any · 1 hint"},
    {:hard, "Hard", "long · no hints"}
  ]
  @channels [:surf | Shows.ids()]
  @recent_limit 40
  @titlecard_ms 2100
  @xray_tick_ms 4000

  @impl true
  def mount(_params, _session, socket) do
    recovered = restore_crash(socket)
    if recovered, do: send(self(), :xray_tick)

    {:ok,
     assign(socket,
       page_title: "Sitcom Hangman",
       screen: :menu,
       channel: :friends,
       difficulty: :normal,
       game: nil,
       show: nil,
       round: 0,
       titlecard: nil,
       recent: [],
       message: nil,
       caption: nil,
       caption_n: 0,
       last_points: 0,
       stats: restore_stats(socket),
       shows: Shows.all(),
       total_words: Shows.total_words(),
       difficulties: @difficulties,
       keyboard: @keyboard,
       xray: recovered != nil,
       xray_tab: if(recovered, do: "phoenix", else: "inside"),
       recovered: recovered,
       xray_section: nil,
       runtime: nil,
       portfolio_url:
         Application.get_env(:hangman, :portfolio_url, "https://harshitha-upadhyayula.vercel.app")
     )}
  end

  defp restore_stats(socket) do
    if connected?(socket) do
      socket |> get_connect_params() |> Kernel.||(%{}) |> Map.get("stats") |> Stats.from_params()
    else
      Stats.new()
    end
  end

  # After the X-ray "crash my process" demo, the browser reconnects and
  # tells the new process which one died and when (see assets/js/app.js).
  defp restore_crash(socket) do
    with true <- connected?(socket),
         %{"crash" => %{"pid" => "#PID<" <> _ = pid, "ms" => ms}} <- get_connect_params(socket),
         true <- is_integer(ms) and ms in 0..120_000 and byte_size(pid) < 40 do
      %{pid: pid, ms: ms}
    else
      _ -> nil
    end
  end

  # ── Menu ──────────────────────────────────────────────────────────────

  @impl true
  def handle_event("pick_channel", %{"channel" => value}, socket) do
    case Shows.parse(value) do
      nil -> {:noreply, socket}
      channel -> {:noreply, switch_channel(socket, channel)}
    end
  end

  def handle_event("channel_step", %{"dir" => dir}, %{assigns: %{screen: :menu}} = socket),
    do: {:noreply, step_channel(socket, if(dir == "-1", do: -1, else: 1))}

  def handle_event("channel_step", _params, socket), do: {:noreply, socket}

  def handle_event("pick_difficulty", %{"difficulty" => value}, socket) do
    case Enum.find(@difficulties, fn {id, _, _} -> Atom.to_string(id) == value end) do
      nil -> {:noreply, socket}
      {difficulty, _, _} -> {:noreply, assign(socket, difficulty: difficulty)}
    end
  end

  # Guards make these idempotent: Enter on a focused button fires both the
  # click and the window keydown, which must not skip a word.
  def handle_event("start", _params, %{assigns: %{screen: :menu}} = socket),
    do: {:noreply, start_round(socket)}

  def handle_event("next", _params, %{assigns: %{game: %Game{status: status}}} = socket)
      when status != :playing,
      do: {:noreply, start_round(socket)}

  def handle_event(event, _params, socket) when event in ["start", "next"],
    do: {:noreply, socket}

  def handle_event("menu", _params, socket), do: {:noreply, to_menu(socket)}

  # ── Playing ───────────────────────────────────────────────────────────

  def handle_event("guess", %{"letter" => letter}, socket), do: {:noreply, guess(socket, letter)}
  def handle_event("hint", _params, socket), do: {:noreply, hint(socket)}

  # xray:keys
  # Physical keyboard: letters guess, Enter plays / continues, Escape backs
  # out, arrows flip channels on the menu, ? asks for a hint.
  def handle_event("key", %{"key" => key}, socket) do
    %{screen: screen, game: game, xray: xray} = socket.assigns

    socket =
      cond do
        key == "Escape" and xray -> assign(socket, xray: false)
        key == "Escape" and screen == :game -> to_menu(socket)
        key == "Enter" and (screen == :menu or Game.over?(game)) -> start_round(socket)
        key in ["ArrowRight", "ArrowDown"] and screen == :menu -> step_channel(socket, 1)
        key in ["ArrowLeft", "ArrowUp"] and screen == :menu -> step_channel(socket, -1)
        key == "?" and screen == :game -> hint(socket)
        screen == :game and String.length(key) == 1 -> guess(socket, key)
        true -> socket
      end

    {:noreply, socket}
  end

  def handle_event("key", _params, socket), do: {:noreply, socket}
  # xray:end

  # ── X-ray ─────────────────────────────────────────────────────────────

  def handle_event("xray", _params, %{assigns: %{xray: true}} = socket),
    do: {:noreply, assign(socket, xray: false)}

  def handle_event("xray", _params, socket) do
    send(self(), :xray_tick)
    {:noreply, socket |> assign(xray: true) |> push_event("xray", %{on: true})}
  end

  def handle_event("xray_tab", %{"tab" => tab}, socket)
      when tab in ~w(inside trace phoenix wire lessons),
      do: {:noreply, assign(socket, xray_tab: tab)}

  def handle_event("xray_focus", %{"section" => id}, socket) do
    section = if Xray.section(id), do: id
    {:noreply, assign(socket, xray: true, xray_tab: "inside", xray_section: section)}
  end

  def handle_event("xray_back", _params, socket),
    do: {:noreply, assign(socket, xray_section: nil)}

  # "Let it crash", on purpose: this LiveView process dies, its supervisor
  # shrugs, and the browser rejoins a brand-new process. Only you notice.
  def handle_event("crash", _params, socket) do
    raise "X-ray demo: #{inspect(self())} crashed on purpose (#{socket.assigns.screen} screen)"
  end

  @impl true
  def handle_info(:xray_tick, %{assigns: %{xray: true}} = socket) do
    Process.send_after(self(), :xray_tick, @xray_tick_ms)
    {:noreply, assign(socket, runtime: Xray.runtime())}
  end

  def handle_info(:xray_tick, socket), do: {:noreply, socket}

  # Timings from LiveView's own :telemetry events (HangmanWeb.Xray.Telemetry).
  # Only a push_event, never an assign, so it can't trigger another render.
  def handle_info({:xray_trace, trace}, socket),
    do: {:noreply, push_event(socket, "xray_trace", trace)}

  # xray:timers
  # The title card hides itself 2.1 s after an episode starts. The timer
  # message carries the round number, so a stale timer from an episode you
  # skipped can never hide the next episode's card.
  def handle_info({:hide_titlecard, round}, %{assigns: %{round: round}} = socket),
    do: {:noreply, assign(socket, titlecard: nil)}

  def handle_info({:hide_titlecard, _}, socket), do: {:noreply, socket}
  # xray:end

  # ── Moves ─────────────────────────────────────────────────────────────

  defp switch_channel(socket, channel) do
    socket
    |> assign(channel: channel)
    |> push_event("fx", %{kind: "channel", show: theme(channel)})
  end

  defp step_channel(socket, step) do
    index = Enum.find_index(@channels, &(&1 == socket.assigns.channel))

    switch_channel(
      socket,
      Enum.at(@channels, rem(index + step + length(@channels), length(@channels)))
    )
  end

  defp to_menu(socket) do
    socket
    |> assign(screen: :menu, titlecard: nil)
    |> push_event("fx", %{kind: "menu", show: theme(socket.assigns.channel)})
  end

  defp start_round(socket) do
    %{channel: channel, difficulty: difficulty, recent: recent, round: round} = socket.assigns
    {show, %{word: word, clue: clue}} = Shows.random(channel, difficulty, recent)
    game = Game.new(word, show: show, clue: clue, difficulty: difficulty)
    round = round + 1
    Process.send_after(self(), {:hide_titlecard, round}, @titlecard_ms)

    socket
    |> assign(
      screen: :game,
      game: game,
      show: show,
      round: round,
      titlecard: round,
      recent: Enum.take([word | recent], @recent_limit),
      last_points: 0,
      message: {:info, "#{length(Game.letters(word))} different letters. Read the clue."}
    )
    |> caption("[THEME MUSIC PLAYS]")
    |> push_event("fx", %{kind: "start", show: show})
  end

  defp guess(%{assigns: %{game: %Game{status: :playing} = game}} = socket, letter) do
    letter = String.downcase(letter)
    show = Shows.get(game.show)

    case Game.guess(game, letter) do
      {:hit, game} ->
        count = length(Game.positions(game, letter))
        times = if count == 1, do: "once", else: "#{count}×"

        socket
        |> assign(
          game: game,
          message: {:hit, "#{Enum.random(show.hit)} #{up(letter)} appears #{times}."}
        )
        |> caption(Enum.random(["[LAUGHTER]", "[AUDIENCE CHEERS]", "[WHOOPS FROM THE CROWD]"]))
        |> push_event("fx", %{
          kind: "hit",
          show: game.show,
          letter: letter,
          positions: Game.positions(game, letter)
        })
        |> maybe_finish()

      {:miss, game} ->
        socket
        |> assign(game: game, message: {:miss, "#{Enum.random(show.miss)} No #{up(letter)}."})
        |> caption(Enum.random(["[AUDIENCE: OOOOH]", "[GASPS]", "[NERVOUS LAUGHTER]"]))
        |> push_event("fx", %{
          kind: "miss",
          show: game.show,
          letter: letter,
          lives: Game.lives(game)
        })
        |> maybe_finish()

      {:already_guessed, _game} ->
        socket
        |> assign(message: {:info, "You already tried #{up(letter)}."})
        |> caption("[AWKWARD SILENCE]")
        |> push_event("fx", %{kind: "repeat", show: game.show, letter: letter})

      {_other, _game} ->
        socket
    end
  end

  defp guess(socket, _letter), do: socket

  defp hint(%{assigns: %{game: %Game{status: :playing} = game}} = socket) do
    case Game.hint(game) do
      {:ok, letter, game} ->
        socket
        |> assign(game: game, message: {:hit, "Hint: #{up(letter)}. That cost you a take."})
        |> caption("[KNOWING MURMURS]")
        |> push_event("fx", %{
          kind: "hint",
          show: game.show,
          letter: letter,
          positions: Game.positions(game, letter),
          lives: Game.lives(game)
        })
        |> maybe_finish()

      {:error, :no_hints, _} ->
        assign(socket, message: {:info, "No hints left this episode."})

      {:error, :last_life, _} ->
        assign(socket, message: {:info, "Hints cost a take, and this is your last one."})

      {:error, _, _} ->
        socket
    end
  end

  defp hint(socket), do: socket

  defp maybe_finish(%{assigns: %{game: %Game{status: :playing}}} = socket), do: socket

  defp maybe_finish(%{assigns: %{game: game, stats: stats}} = socket) do
    stats = Stats.record(stats, game)
    won? = Game.won?(game)

    socket
    |> assign(stats: stats, last_points: Game.score(game))
    |> caption(if(won?, do: "[THUNDEROUS APPLAUSE]", else: "[AUDIENCE: AWWW]"))
    |> push_event("stats", Stats.to_map(stats))
    |> push_event("fx", %{kind: if(won?, do: "win", else: "lose"), show: game.show})
  end

  defp caption(socket, text),
    do: assign(socket, caption: text, caption_n: socket.assigns.caption_n + 1)

  defp up(letter), do: String.upcase(letter)

  defp theme(:surf), do: "surf"
  defp theme(show), do: show

  # ── Rendering ─────────────────────────────────────────────────────────

  @slots %{
    surf: "All night",
    friends: "8:00",
    big_bang: "8:30",
    modern_family: "9:00",
    brooklyn_99: "9:30"
  }

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        id="app"
        phx-window-keydown="key"
        data-show={if @screen == :game, do: @show, else: theme(@channel)}
        class={["app", @xray && "is-xray"]}
      >
        <div
          id="xray-scan"
          phx-hook="XrayScan"
          data-on={to_string(@xray)}
          class="xray-scan"
          aria-hidden="true"
        >
        </div>
        <div class="app-body">
          <.topbar stats={@stats} portfolio_url={@portfolio_url} xray={@xray} />
          <main class="main">
            <.menu
              :if={@screen == :menu}
              shows={@shows}
              channel={@channel}
              difficulties={@difficulties}
              difficulty={@difficulty}
              stats={@stats}
              total_words={@total_words}
              xray={@xray}
            />
            <.board
              :if={@screen == :game}
              game={@game}
              show={Shows.get(@show)}
              round={@round}
              titlecard={@titlecard}
              message={@message}
              caption={@caption}
              caption_n={@caption_n}
              keyboard={@keyboard}
              stats={@stats}
              last_points={@last_points}
              xray={@xray}
            />
          </main>
          <footer class="footer">
            <span>Elixir · Phoenix LiveView · GSAP · Three.js</span>
            <span class="relative inline-flex items-center gap-2">
              <span id="transport-badge" phx-update="ignore" class="transport-badge">connecting…</span>
              <.pin :if={@xray} section="transport" n={8} />
            </span>
            <a href="https://github.com/U-Harshitha/Hangman-in-Phoenix" target="_blank" rel="noopener">
              Source on GitHub
            </a>
          </footer>
        </div>
        <.xray_panel
          :if={@xray}
          tab={@xray_tab}
          section={@xray_section && Xray.section(@xray_section)}
          runtime={@runtime}
          recovered={@recovered}
        />
      </div>
    </Layouts.app>
    """
  end

  attr :stats, Stats, required: true
  attr :portfolio_url, :string, required: true
  attr :xray, :boolean, required: true

  defp topbar(assigns) do
    ~H"""
    <header class="topbar">
      <a href={@portfolio_url} class="mark" aria-label="Back to the portfolio">
        <span class="mark-glyph" aria-hidden="true">H.U.</span>
        <span class="mark-sub">
          <svg viewBox="0 0 20 20" class="size-3.5" aria-hidden="true">
            <path
              d="M12.5 4.5 7 10l5.5 5.5"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
          <span class="hidden sm:inline">portfolio</span>
        </span>
      </a>
      <nav class="tools" aria-label="Game">
        <button
          type="button"
          phx-click="menu"
          class="tool tool-brand"
          aria-label="Sitcom Hangman: back to the TV guide"
        >
          <span class="hidden sm:inline">Sitcom Hangman</span>
          <span class="sm:hidden">Guide</span>
        </button>
        <span class="tool tool-stat" id="stats-bar">
          score <b data-stat="score">{@stats.score}</b>
          <.pin :if={@xray} section="stats" n={6} />
        </span>
        <span class="tool tool-stat hidden sm:inline-flex">
          streak <b data-stat="streak">{@stats.streak}</b>
        </span>
        <button
          type="button"
          id="xray-toggle"
          phx-click="xray"
          class="tool"
          aria-pressed={to_string(@xray)}
          title="See how this page works under the hood"
        >
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <path
              d="M3 8V4h4M21 8V4h-4M3 16v4h4M21 16v4h-4M8 12h8M12 8v8"
              fill="none"
              stroke="currentColor"
              stroke-width="1.6"
              stroke-linecap="round"
            />
          </svg>
          X-ray
        </button>
      </nav>
    </header>
    """
  end

  # ── Menu: the TV guide and the set ────────────────────────────────────

  attr :shows, :list, required: true
  attr :channel, :atom, required: true
  attr :difficulties, :list, required: true
  attr :difficulty, :atom, required: true
  attr :stats, Stats, required: true
  attr :total_words, :integer, required: true
  attr :xray, :boolean, required: true

  defp menu(assigns) do
    assigns =
      assigns
      |> assign(:current, Enum.find(assigns.shows, &(&1.id == assigns.channel)))
      |> assign(:index, Enum.find_index(@channels, &(&1 == assigns.channel)))
      |> assign(:slots, @slots)

    ~H"""
    <section id="menu" phx-hook="Intro" class="menu">
      <div class="menu-copy">
        <p class="eyebrow" data-intro>
          <span class="tally" aria-hidden="true"></span> Tonight on Phoenix TV
        </p>
        <h1 class="title" aria-label="Hangman, the sitcom edition">
          <span class="title-note" aria-hidden="true">the sitcom edition</span>
          <svg class="title-arrow" viewBox="0 0 64 40" aria-hidden="true">
            <path d="M60 3C42 5 22 12 9 31" />
            <path d="M9 31l1.5-10.5M9 31l9.5-4.5" />
          </svg>
          <span class="title-word" aria-hidden="true">
            <span :for={ch <- String.graphemes("Hangman")} class="title-letter">{ch}</span>
          </span>
          <span class="title-mark" aria-hidden="true"></span>
        </h1>
        <p class="lede" data-intro>
          {@total_words} questions from four sitcoms. Guess the answer a letter at a
          time before your six takes run out.
        </p>

        <div
          id="guide"
          class="guide"
          role="radiogroup"
          aria-label="Channel"
          phx-hook="Guide"
          data-x="phx-click → pick_channel"
          data-intro
        >
          <.pin :if={@xray} section="channel" n={10} />
          <div class="guide-head" aria-hidden="true">
            <span>CH</span>
            <span>Tonight</span>
            <span class="text-right">Time</span>
          </div>
          <div class="guide-rows">
            <span id="guide-cursor" class="guide-cursor" phx-update="ignore" aria-hidden="true"></span>
            <button
              :for={{id, n} <- Enum.with_index([:surf | Enum.map(@shows, & &1.id)])}
              type="button"
              role="radio"
              aria-checked={to_string(id == @channel)}
              phx-click="pick_channel"
              phx-value-channel={id}
              class={["guide-row", id == @channel && "is-selected"]}
              data-show={id}
              data-card
            >
              <span class="guide-ch">{String.pad_leading(to_string(n), 2, "0")}</span>
              <span class="guide-main">
                <span class="guide-name">
                  <i class="guide-swatch" aria-hidden="true"></i>{if id == :surf,
                    do: "Channel surf",
                    else: show_name(@shows, id)}
                </span>
                <span class="guide-meta">
                  {if id == :surf,
                    do: "All four shows, shuffled",
                    else:
                      "starring #{show_field(@shows, id, :mascot)} · #{length(Shows.entries(id))} questions"}
                </span>
              </span>
              <span class="guide-slot">
                <span :if={id == @channel} class="on-air">On air</span>
                <span :if={id != @channel}>{@slots[id]}</span>
              </span>
              <span :if={id == @channel} class="guide-progress" aria-hidden="true"><i></i></span>
            </button>
          </div>
        </div>
      </div>

      <div class="stage" data-intro>
        <div
          class="tv"
          id="tv"
          phx-hook="Tv"
          data-channel={@channel}
          style={"--dial: #{@index * 64 - 128}deg"}
          data-x="Tv hook · canvas static"
        >
          <.pin :if={@xray} section="process" n={7} />
          <div class="tv-antenna" aria-hidden="true"><i></i><i></i><b></b></div>
          <div class="tv-body">
            <div class="tv-screen">
              <div :if={@channel != :surf} class="tv-picture">
                <Mascots.set show={@channel} preview />
              </div>
              <div :if={@channel == :surf} class="tv-picture tv-surf">
                <span>CHANNEL SURFING</span>
              </div>
              <canvas class="tv-static" aria-hidden="true"></canvas>
              <span class="tv-osd" aria-hidden="true">
                CH {String.pad_leading(to_string(@index), 2, "0")}
              </span>
              <div class="tv-lower-third">
                <strong>{if @current, do: @current.name, else: "Channel surf"}</strong>
                <span>{if @current, do: @current.tagline, else: "A different show every episode."}</span>
              </div>
            </div>
            <div class="tv-panel">
              <span class="tv-grille" aria-hidden="true"></span>
              <button
                type="button"
                class="tv-dial"
                phx-click="channel_step"
                phx-value-dir="1"
                aria-label="Next channel"
                title="Next channel"
              >
                <i aria-hidden="true"></i>
              </button>
              <span class="tv-dial-label" aria-hidden="true">channel</span>
              <button
                type="button"
                class="tv-dial tv-dial--small"
                phx-click="channel_step"
                phx-value-dir="-1"
                aria-label="Previous channel"
                title="Previous channel"
              >
                <i aria-hidden="true"></i>
              </button>
              <span class="tv-led" aria-hidden="true"></span>
            </div>
          </div>
          <div class="tv-feet" aria-hidden="true"><i></i><i></i></div>
        </div>

        <div class="controls" data-intro>
          <div class="segmented" role="radiogroup" aria-label="Difficulty">
            <button
              :for={{id, label, blurb} <- @difficulties}
              type="button"
              role="radio"
              aria-checked={to_string(id == @difficulty)}
              phx-click="pick_difficulty"
              phx-value-difficulty={id}
              class={[id == @difficulty && "is-selected"]}
            >
              <span class="seg-label">{label}</span>
              <span class="seg-blurb">{blurb}</span>
            </button>
          </div>
          <div class="play-row">
            <button type="button" phx-click="start" class="btn btn-primary" id="play">
              Roll the episode
            </button>
            <span class="hint-text hidden sm:inline">
              <kbd>Enter</kbd> to play · <kbd>←</kbd><kbd>→</kbd> channels
            </span>
          </div>
          <dl :if={@stats.played > 0} class="menu-stats">
            <div>
              <dt>Episodes</dt><dd>{@stats.played}</dd>
            </div>
            <div>
              <dt>Win rate</dt><dd>{Stats.win_rate(@stats)}%</dd>
            </div>
            <div>
              <dt>Best streak</dt><dd>{@stats.best_streak}</dd>
            </div>
          </dl>
        </div>
      </div>
    </section>
    """
  end

  defp show_name(shows, id), do: show_field(shows, id, :name)
  defp show_field(shows, id, field), do: shows |> Enum.find(&(&1.id == id)) |> Map.fetch!(field)

  # ── Board ─────────────────────────────────────────────────────────────

  attr :game, Game, required: true
  attr :show, :map, required: true
  attr :round, :integer, required: true
  attr :titlecard, :any, required: true
  attr :message, :any, required: true
  attr :caption, :string, default: nil
  attr :caption_n, :integer, required: true
  attr :keyboard, :list, required: true
  attr :stats, Stats, required: true
  attr :last_points, :integer, required: true
  attr :xray, :boolean, required: true

  defp board(assigns) do
    ~H"""
    <section id="board" phx-hook="Board" data-show={@show.id} class="board">
      <div class="episode-bar">
        <span class="ep-channel">CH {String.pad_leading(to_string(@show.channel), 2, "0")}</span>
        <span class="ep-show">{@show.short}</span>
        <span class="ep-number">S{season(@game.difficulty)} · E{@round}</span>
        <span class="ep-title">{Shows.episode_title(@show.id, @round)}</span>
        <.pin :if={@xray} section="timers" n={9} />
      </div>

      <div class="board-grid">
        <div class="set-tv" data-x="Mascot hook · phx-update=ignore">
          <.pin :if={@xray} section="mascot" n={4} />
          <div class="set-screen">
            <div
              id="mascot"
              phx-hook="Mascot"
              data-show={@show.id}
              data-mistakes={Game.mistakes(@game)}
              data-status={@game.status}
              data-round={@round}
              class="mascot"
            >
              <div id={"mascot-svg-#{@show.id}"} phx-update="ignore" class="mascot-frame">
                <Mascots.set show={@show.id} />
              </div>
            </div>
            <div :if={@caption} id={"cc-#{@caption_n}"} class="caption" aria-hidden="true">
              {@caption}
            </div>
          </div>
          <div class="takes" id="takes">
            <span class="takes-label">takes</span>
            <span
              class="takes-lamps"
              aria-label={"#{Game.lives(@game)} of #{Game.max_lives()} takes left"}
            >
              <span
                :for={i <- 1..Game.max_lives()}
                class={["lamp", i > Game.lives(@game) && "is-out"]}
                data-lamp={i}
                aria-hidden="true"
              ></span>
            </span>
            <.pin :if={@xray} section="scene" n={5} />
            <.pin :if={@xray} section="process" n={7} />
          </div>
        </div>

        <div class="play-col">
          <div class="clue-card">
            <p class="clue-label">Clue</p>
            <p class="clue-text">{@game.clue}</p>
          </div>

          <div class="word-card" data-x="server-rendered · HEEx diff">
            <.pin :if={@xray} section="word" n={1} />
            <div
              id="word"
              class={["word", word_size(@game)]}
              role="img"
              aria-label={"Answer: " <> Game.masked(@game)}
            >
              <span :for={group <- word_groups(@game)} class="word-group">
                <span
                  :for={{tile, i} <- group}
                  class={[
                    "tile",
                    !tile.letter? && "tile--punct",
                    tile.revealed && "is-revealed",
                    tile.missed && "is-missed"
                  ]}
                  data-index={i}
                  data-revealed={to_string(tile.revealed)}
                >
                  <b :if={tile.revealed or !tile.letter?}>{tile.char}</b>
                </span>
              </span>
            </div>
            <div class="word-foot">
              <p id="message" class={["message", message_class(@message)]} aria-live="polite">
                {message_text(@message)}
              </p>
              <.pin :if={@xray} section="rules" n={3} />
              <button
                :if={@game.hints_left > 0 and @game.status == :playing}
                type="button"
                phx-click="hint"
                class="btn btn-small"
                id="hint"
                disabled={Game.lives(@game) <= 1}
              >
                Hint · {@game.hints_left}
              </button>
            </div>
          </div>

          <div
            id="keyboard"
            class="keyboard"
            aria-label="Letters"
            data-x="phx-click → handle_event"
          >
            <.pin :if={@xray} section="keyboard" n={2} />
            <div :for={row <- @keyboard} class="keyboard-row">
              <button
                :for={letter <- row}
                type="button"
                phx-click="guess"
                phx-value-letter={letter}
                class={["key", "key--#{Game.letter_state(@game, letter)}"]}
                data-key={letter}
                disabled={Game.letter_state(@game, letter) != :unused or @game.status != :playing}
                aria-label={"Guess " <> String.upcase(letter)}
              >
                {letter}
              </button>
            </div>
          </div>
          <p class="hint-text hidden text-center sm:block">
            Type to guess · <kbd>?</kbd> hint · <kbd>Esc</kbd> TV guide
          </p>
        </div>
      </div>

      <div
        :if={@titlecard}
        id={"titlecard-#{@titlecard}"}
        phx-hook="TitleCard"
        phx-remove={JS.transition({"ease-in duration-500", "opacity-100", "opacity-0"}, time: 500)}
        class="titlecard"
        aria-hidden="true"
      >
        <canvas class="tv-static"></canvas>
        <div class="titlecard-inner">
          <span class="tc-osd">CH {String.pad_leading(to_string(@show.channel), 2, "0")}</span>
          <span class="tc-show">{@show.name}</span>
          <span class="tc-title">{Shows.episode_title(@show.id, @round)}</span>
          <span class="tc-ep">Season {season(@game.difficulty)} · Episode {@round}</span>
        </div>
      </div>

      <.result :if={Game.over?(@game)} game={@game} show={@show} stats={@stats} points={@last_points} />
    </section>
    """
  end

  # Tiles grouped per word (spaces dropped), so answers wrap between
  # words rather than in the middle of one.
  defp word_groups(game) do
    game
    |> Game.tiles()
    |> Enum.with_index()
    |> Enum.chunk_by(fn {tile, _} -> tile.char == " " end)
    |> Enum.reject(fn [{tile, _} | _] -> tile.char == " " end)
  end

  defp word_size(game) do
    longest = game |> word_groups() |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)

    cond do
      longest > 9 or length(Game.tiles(game)) > 14 -> "word--long"
      longest > 7 -> "word--mid"
      true -> nil
    end
  end

  defp season(:easy), do: 1
  defp season(:normal), do: 2
  defp season(:hard), do: 3

  attr :game, Game, required: true
  attr :show, :map, required: true
  attr :stats, Stats, required: true
  attr :points, :integer, required: true

  defp result(assigns) do
    ~H"""
    <div
      id="result"
      phx-hook="Result"
      data-status={@game.status}
      class="result-backdrop"
      role="dialog"
      aria-modal="true"
      aria-labelledby="result-title"
    >
      <div class="result-card">
        <p class="kicker">{if Game.won?(@game), do: "That's a wrap", else: "Cut!"}</p>
        <h2 id="result-title" class="result-title">
          {if Game.won?(@game), do: @show.win, else: @show.lose}
        </h2>
        <p :if={Game.lost?(@game)} class="result-line">{@show.lose_line}</p>
        <p class="result-label">The answer was</p>
        <p class="result-word">
          <span
            :for={ch <- String.graphemes(@game.word)}
            class={["rw-cap", ch == " " && "rw-gap"]}
          >
            {ch}
          </span>
        </p>
        <p class="result-fact"><span>Trivia</span> {@game.clue}</p>
        <dl class="result-stats">
          <div class="result-stat">
            <dt>Points</dt><dd data-count={@points}>+{@points}</dd>
          </div>
          <div class="result-stat">
            <dt>Streak</dt><dd>{@stats.streak}</dd>
          </div>
          <div class="result-stat">
            <dt>Total</dt><dd>{@stats.score}</dd>
          </div>
        </dl>
        <div class="result-actions">
          <button type="button" phx-click="next" class="btn btn-primary flex-1" id="next">
            Next episode
          </button>
          <button type="button" phx-click="menu" class="btn flex-1">
            Change channel
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ── X-ray ─────────────────────────────────────────────────────────────

  attr :section, :string, required: true
  attr :n, :integer, required: true

  defp pin(assigns) do
    ~H"""
    <button
      type="button"
      class="pin"
      phx-click="xray_focus"
      phx-value-section={@section}
      aria-label={"X-ray note #{@n}"}
    >
      {@n}
    </button>
    """
  end

  @tabs [
    {"inside", "Inside"},
    {"trace", "Trace"},
    {"phoenix", "Why Phoenix"},
    {"wire", "Wire"},
    {"lessons", "Lessons"}
  ]

  attr :tab, :string, required: true
  attr :section, :map, default: nil
  attr :runtime, :map, default: nil
  attr :recovered, :map, default: nil

  defp xray_panel(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <aside id="xray-panel" class="xray-panel" aria-label="X-ray: how this page works">
      <div class="xp-head">
        <div>
          <p class="xp-kicker">X-ray mode</p>
          <h2 class="xp-title">How this page works</h2>
        </div>
        <button type="button" phx-click="xray" class="xp-close" aria-label="Close X-ray">
          <svg viewBox="0 0 20 20" class="size-4" aria-hidden="true">
            <path
              d="M5 5l10 10M15 5 5 15"
              stroke="currentColor"
              stroke-width="1.8"
              stroke-linecap="round"
            />
          </svg>
        </button>
      </div>

      <div class="xp-runtime">
        <div class="xp-runtime-row">
          <span class="xp-dot" aria-hidden="true"></span>
          Your game is Erlang process <code>{@runtime && @runtime.pid}</code>
        </div>
        <dl :if={@runtime} class="xp-facts">
          <div>
            <dt>Its memory</dt><dd>{@runtime.memory_kb} KB</dd>
          </div>
          <div>
            <dt>Processes on node</dt><dd>{@runtime.processes}</dd>
          </div>
          <div>
            <dt>Transport</dt><dd id="xp-transport" phx-hook="Transport" phx-update="ignore">…</dd>
          </div>
          <div>
            <dt>Server uptime</dt><dd>{@runtime.uptime}</dd>
          </div>
        </dl>
      </div>

      <nav class="xp-tabs" role="tablist">
        <button
          :for={{id, label} <- @tabs}
          type="button"
          role="tab"
          aria-selected={to_string(@tab == id)}
          phx-click="xray_tab"
          phx-value-tab={id}
          class={[@tab == id && "is-active"]}
        >
          {label}
        </button>
      </nav>

      <div class="xp-body">
        <div :if={@tab == "inside" and is_nil(@section)} class="xp-index">
          <p class="xp-p">
            This is a <strong>Phoenix LiveView</strong>: the page is rendered by an Elixir
            process on the server, and every click travels over one persistent connection.
            The numbered pins on the page mark the interesting parts.
          </p>
          <button
            :for={s <- Xray.sections()}
            type="button"
            phx-click="xray_focus"
            phx-value-section={s.id}
            class="xp-item"
          >
            <span class="xp-n">{s.n}</span>
            <span>{s.title}</span>
          </button>
        </div>

        <div :if={@tab == "inside" and @section} class="xp-section">
          <button type="button" phx-click="xray_back" class="xp-back">← All notes</button>
          <h3 class="xp-h"><span class="xp-n">{@section.n}</span>{@section.title}</h3>
          <p class="xp-p">{Xray.format(@section.body)}</p>
          <p class="xp-file">{@section.file}</p>
          <pre class="xp-code"><code>{Phoenix.HTML.raw(@section.html)}</code></pre>
        </div>

        <.xray_trace :if={@tab == "trace"} />
        <.xray_phoenix :if={@tab == "phoenix"} runtime={@runtime} recovered={@recovered} />

        <div :if={@tab == "wire"} class="xp-wire">
          <p class="xp-p">
            Every message between your browser and the server, live. Press a letter and
            watch a tiny event go up and a small diff come back. The answer isn't in any of
            it until the episode ends.
          </p>
          <div id="wire-log" phx-hook="Wire" phx-update="ignore" class="wire-log"></div>
        </div>

        <div :if={@tab == "lessons"} class="xp-lessons">
          <p class="xp-p">
            I picked Phoenix for this project to learn something new. Here's what it taught me
            about building for the web.
          </p>
          <article :for={{lesson, i} <- Enum.with_index(Xray.lessons(), 1)} class="lesson">
            <span class="lesson-n">{String.pad_leading(to_string(i), 2, "0")}</span>
            <div>
              <h3>{lesson.title}</h3>
              <p>{Xray.format(lesson.body)}</p>
            </div>
          </article>
        </div>
      </div>
    </aside>
    """
  end

  # One key press, followed end to end. The numbers are filled in by the
  # Trace hook from real traffic and LiveView's own telemetry.
  defp xray_trace(assigns) do
    assigns = assign(assigns, :steps, Xray.trace_steps())

    ~H"""
    <div class="xp-trace">
      <p class="xp-p">
        Follow one key press all the way to the server and back. Start an episode and
        press a letter: every number below is measured from that press.
      </p>
      <ol id="trace" class="trace" phx-hook="Trace" phx-update="ignore">
        <li :for={{step, i} <- Enum.with_index(@steps, 1)} class="trace-step" data-where={step.where}>
          <span class="trace-dot" aria-hidden="true">{i}</span>
          <div class="trace-body">
            <p class="trace-where">{step.label}</p>
            <h4>{step.title}</h4>
            <p class="trace-text">{Xray.format(step.body)}</p>
            <p :if={step[:slot]} class="trace-value">
              <span data-slot={step.slot}>—</span>
            </p>
          </div>
        </li>
      </ol>
      <div id="trace-raw" class="trace-raw" phx-update="ignore">
        <p class="xp-file">What actually crossed the wire</p>
        <pre class="xp-code"><code data-raw="up">Press a letter…</code></pre>
        <pre class="xp-code"><code data-raw="down"></code></pre>
      </div>
    </div>
    """
  end

  attr :runtime, :map, default: nil
  attr :recovered, :map, default: nil

  defp xray_phoenix(assigns) do
    assigns = assign(assigns, specialities: Xray.specialities(), loc: Xray.loc())

    ~H"""
    <div class="xp-phoenix">
      <div :if={@recovered} class="recovered" id="recovered">
        <p class="recovered-k">You just crashed a process</p>
        <p>
          <code>{@recovered.pid}</code>
          died. Its supervisor didn't care: your browser rejoined and got
          <code>{@runtime && @runtime.pid}</code>
          in <strong>{@recovered.ms} ms</strong>. Your score survived (it lives in your
          browser); the episode you were in did not. Nobody else playing noticed a thing.
        </p>
      </div>

      <p class="xp-p">
        Phoenix is a web framework for Elixir, which runs on the BEAM, the virtual machine
        Ericsson built for telephone switches that weren't allowed to go down. Here's
        what that buys a small game, with proof from this page.
      </p>

      <article :for={{sp, i} <- Enum.with_index(@specialities, 1)} class="spec" id={"spec-#{sp.id}"}>
        <span class="spec-n">{String.pad_leading(to_string(i), 2, "0")}</span>
        <div class="spec-body">
          <h3>{sp.title}</h3>
          <p>{Xray.format(sp.body)}</p>
          <.proof id={sp.id} runtime={@runtime} loc={@loc} />
        </div>
      </article>

      <h3 class="xp-sub">The same game, the usual way</h3>
      <table class="compare">
        <thead>
          <tr>
            <th></th>
            <th>SPA + JSON API</th>
            <th>This LiveView</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{row, spa, lv} <- Xray.comparison()}>
            <th>{row}</th>
            <td>{spa}</td>
            <td>{lv}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :id, :atom, required: true
  attr :runtime, :map, default: nil
  attr :loc, :map, required: true

  defp proof(%{id: :process} = assigns) do
    ~H"""
    <dl :if={@runtime} class="proof proof-grid">
      <div>
        <dt>you</dt><dd>{@runtime.pid}</dd>
      </div>
      <div>
        <dt>your memory</dt><dd>{@runtime.memory_kb} KB</dd>
      </div>
      <div>
        <dt>work done</dt><dd>{@runtime.reductions} reductions</dd>
      </div>
      <div>
        <dt>schedulers</dt><dd>{@runtime.schedulers} (one per core)</dd>
      </div>
    </dl>
    """
  end

  defp proof(%{id: :supervision} = assigns) do
    ~H"""
    <div class="proof">
      <ol :if={@runtime} class="tree" aria-label="Your process's supervision chain">
        <li :for={{node, depth} <- Enum.with_index(@runtime.chain)} style={"--d: #{depth}"}>
          <span class="tree-name">{node.name}</span>
          <span class="tree-kind">{node.kind}</span>
        </li>
      </ol>
      <button
        type="button"
        id="crash"
        class="btn btn-small btn-danger"
        phx-hook="Crash"
        data-pid={@runtime && @runtime.pid}
      >
        Crash my process
      </button>
    </div>
    """
  end

  defp proof(%{id: :diffs} = assigns) do
    ~H"""
    <dl id="proof-diffs" class="proof proof-grid" phx-hook="DiffStats" phx-update="ignore">
      <div>
        <dt>first render</dt><dd data-slot="first">—</dd>
      </div>
      <div>
        <dt>static HTML in it</dt><dd data-slot="statics">—</dd>
      </div>
      <div>
        <dt>avg diff per guess</dt><dd data-slot="avg">press a letter</dd>
      </div>
      <div>
        <dt>messages so far</dt><dd data-slot="count">—</dd>
      </div>
    </dl>
    """
  end

  defp proof(%{id: :js} = assigns) do
    ~H"""
    <dl id="proof-js" class="proof proof-grid" phx-hook="JsStats" phx-update="ignore">
      <div>
        <dt>JS to play</dt><dd data-slot="main">—</dd>
      </div>
      <div>
        <dt>Three.js, later</dt><dd data-slot="lazy">—</dd>
      </div>
      <div>
        <dt>Elixir (rules + UI)</dt><dd>{@loc.elixir} lines</dd>
      </div>
      <div>
        <dt>JS (motion + X-ray)</dt><dd>{@loc.js} lines</dd>
      </div>
    </dl>
    """
  end

  defp proof(%{id: :transport} = assigns) do
    ~H"""
    <p class="proof proof-line">
      Right now: <b id="proof-transport" phx-hook="Transport" phx-update="ignore">…</b>
    </p>
    """
  end

  defp proof(%{id: :telemetry} = assigns) do
    ~H"""
    <pre class="xp-code proof"><code>{Phoenix.HTML.raw(Xray.telemetry_html())}</code></pre>
    """
  end

  defp proof(assigns), do: ~H""

  defp message_text(nil), do: ""
  defp message_text({_kind, text}), do: text

  defp message_class({:hit, _}), do: "message--hit"
  defp message_class({:miss, _}), do: "message--miss"
  defp message_class(_), do: nil
end
