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
    {:easy, "Easy", "Short answers · 2 hints"},
    {:normal, "Normal", "Any length · 1 hint"},
    {:hard, "Hard", "Long answers · no hints"}
  ]
  @channels [:surf | Shows.ids()]
  @recent_limit 40
  @titlecard_ms 2100
  @xray_tick_ms 4000

  @impl true
  def mount(_params, _session, socket) do
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
       xray: false,
       xray_tab: "inside",
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

  # ── Menu ──────────────────────────────────────────────────────────────

  @impl true
  def handle_event("pick_channel", %{"channel" => value}, socket) do
    case Shows.parse(value) do
      nil -> {:noreply, socket}
      channel -> {:noreply, switch_channel(socket, channel)}
    end
  end

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

  # ── X-ray ─────────────────────────────────────────────────────────────

  def handle_event("xray", _params, %{assigns: %{xray: true}} = socket),
    do: {:noreply, assign(socket, xray: false)}

  def handle_event("xray", _params, socket) do
    send(self(), :xray_tick)
    {:noreply, socket |> assign(xray: true) |> push_event("xray", %{on: true})}
  end

  def handle_event("xray_tab", %{"tab" => tab}, socket) when tab in ~w(inside wire lessons),
    do: {:noreply, assign(socket, xray_tab: tab)}

  def handle_event("xray_focus", %{"section" => id}, socket) do
    section = if Xray.section(id), do: id
    {:noreply, assign(socket, xray: true, xray_tab: "inside", xray_section: section)}
  end

  def handle_event("xray_back", _params, socket),
    do: {:noreply, assign(socket, xray_section: nil)}

  @impl true
  def handle_info(:xray_tick, %{assigns: %{xray: true}} = socket) do
    Process.send_after(self(), :xray_tick, @xray_tick_ms)
    {:noreply, assign(socket, runtime: Xray.runtime())}
  end

  def handle_info(:xray_tick, socket), do: {:noreply, socket}

  def handle_info({:hide_titlecard, round}, %{assigns: %{round: round}} = socket),
    do: {:noreply, assign(socket, titlecard: nil)}

  def handle_info({:hide_titlecard, _}, socket), do: {:noreply, socket}

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
          <.topbar stats={@stats} portfolio_url={@portfolio_url} screen={@screen} xray={@xray} />
          <main class="mx-auto flex w-full max-w-6xl flex-1 flex-col px-4 pb-8 sm:px-6">
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
            <span>Built with Elixir · Phoenix LiveView · GSAP · Three.js</span>
            <span class="relative inline-flex items-center gap-2">
              <span id="transport-badge" phx-update="ignore" class="transport-badge">connecting…</span>
              <.pin :if={@xray} section="transport" n={8} />
            </span>
            <a href="https://github.com/U-Harshitha/Hangman-in-Phoenix" target="_blank" rel="noopener">
              Source
            </a>
          </footer>
        </div>
        <.xray_panel
          :if={@xray}
          tab={@xray_tab}
          section={@xray_section && Xray.section(@xray_section)}
          runtime={@runtime}
        />
      </div>
    </Layouts.app>
    """
  end

  attr :stats, Stats, required: true
  attr :portfolio_url, :string, required: true
  attr :screen, :atom, required: true
  attr :xray, :boolean, required: true

  defp topbar(assigns) do
    ~H"""
    <header class="topbar">
      <a href={@portfolio_url} class="chip-link group" aria-label="Back to portfolio">
        <svg
          viewBox="0 0 20 20"
          class="size-4 transition-transform group-hover:-translate-x-0.5"
          aria-hidden="true"
        >
          <path
            d="M12.5 4.5 7 10l5.5 5.5"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
        <span class="hidden sm:inline">Portfolio</span>
      </a>
      <button
        type="button"
        phx-click="menu"
        class="brand"
        aria-label="Sitcom Hangman, back to the TV guide"
      >
        <span class="brand-dot" aria-hidden="true"></span> Sitcom Hangman
      </button>
      <div class="flex items-center gap-3 sm:gap-5">
        <dl class="stats" id="stats-bar">
          <div>
            <dt>Score</dt><dd data-stat="score">{@stats.score}</dd>
          </div>
          <div class="hidden sm:block">
            <dt>Streak</dt><dd data-stat="streak">{@stats.streak}</dd>
          </div>
          <.pin :if={@xray} section="stats" n={6} />
        </dl>
        <button
          type="button"
          id="xray-toggle"
          phx-click="xray"
          class={["xray-toggle", @xray && "is-on"]}
          aria-pressed={to_string(@xray)}
          title="See how this page works under the hood"
        >
          <svg viewBox="0 0 24 24" class="size-4" aria-hidden="true">
            <path
              d="M3 7V4h3M21 7V4h-3M3 17v3h3M21 17v3h-3M8 12h8M12 8v8"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
            />
          </svg>
          X-ray
        </button>
      </div>
    </header>
    """
  end

  # ── Menu: a TV guide ──────────────────────────────────────────────────

  attr :shows, :list, required: true
  attr :channel, :atom, required: true
  attr :difficulties, :list, required: true
  attr :difficulty, :atom, required: true
  attr :stats, Stats, required: true
  attr :total_words, :integer, required: true
  attr :xray, :boolean, required: true

  defp menu(assigns) do
    assigns = assign(assigns, :current, Enum.find(assigns.shows, &(&1.id == assigns.channel)))

    ~H"""
    <section id="menu" phx-hook="Intro" class="menu">
      <div class="menu-copy">
        <p class="kicker" data-intro>Now airing · built in Elixir</p>
        <h1 class="hero-title" aria-label="Sitcom Hangman">
          <span class="hero-line">
            <span :for={ch <- String.graphemes("Sitcom")} class="hero-letter" aria-hidden="true">{ch}</span>
          </span>
          <span class="hero-line hero-line--accent">
            <span :for={ch <- String.graphemes("Hangman")} class="hero-letter" aria-hidden="true">{ch}</span>
          </span>
        </h1>
        <p class="lede" data-intro>
          Four channels, {@total_words} pieces of sitcom trivia. Guess the answer
          one letter at a time before your six takes run out.
        </p>

        <div class="guide" role="radiogroup" aria-label="Channel" data-intro>
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
            <span class="guide-ch">CH {String.pad_leading(to_string(n), 2, "0")}</span>
            <span class="guide-name">{if id == :surf, do: "Channel surf", else: show_name(@shows, id)}</span>
            <span class="guide-meta">
              {if id == :surf,
                do: "All four shows, mixed",
                else: "starring #{show_field(@shows, id, :mascot)}"}
            </span>
            <span :if={id == @channel} class="on-air">On air</span>
          </button>
        </div>
      </div>

      <div class="tv-wrap" data-intro>
        <div class="tv" id="tv" phx-hook="Tv" data-channel={@channel}>
          <.pin :if={@xray} section="process" n={7} />
          <div class="tv-screen">
            <div :if={@channel != :surf} class="tv-picture">
              <Mascots.set show={@channel} preview />
            </div>
            <div :if={@channel == :surf} class="tv-picture tv-surf">
              <span>CHANNEL SURFING</span>
            </div>
            <canvas class="tv-static" aria-hidden="true"></canvas>
            <span class="tv-osd" aria-hidden="true">
              CH {String.pad_leading(
                to_string(Enum.find_index([:surf | Shows.ids()], &(&1 == @channel))),
                2,
                "0"
              )}
            </span>
            <div class="tv-lower-third">
              <strong>{if @current, do: @current.name, else: "Channel surf"}</strong>
              <span>{if @current, do: @current.tagline, else: "A different show every episode."}</span>
            </div>
          </div>
          <div class="tv-base" aria-hidden="true">
            <span class="tv-brand">PHOENIX</span>
            <span class="tv-knob"></span>
            <span class="tv-knob"></span>
          </div>
        </div>
        <div class="remote" data-intro>
          <p class="panel-label">Difficulty</p>
          <div class="segmented mt-2" role="radiogroup" aria-label="Difficulty">
            <button
              :for={{id, label, blurb} <- @difficulties}
              type="button"
              role="radio"
              aria-checked={to_string(id == @difficulty)}
              phx-click="pick_difficulty"
              phx-value-difficulty={id}
              class={[id == @difficulty && "is-selected"]}
            >
              <span class="font-semibold">{label}</span>
              <span class="text-xs opacity-70">{blurb}</span>
            </button>
          </div>
        </div>

        <div class="remote-play" data-intro>
          <button type="button" phx-click="start" class="btn-primary" id="play">
            Roll the episode
            <svg viewBox="0 0 20 20" class="size-4" aria-hidden="true">
              <path d="M6 4.5v11l9-5.5-9-5.5Z" fill="currentColor" />
            </svg>
          </button>
          <span class="hint-text hidden sm:inline"><kbd>Enter</kbd>
          to play · <kbd>←</kbd> <kbd>→</kbd>
          change channel</span>
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
        <span class="ep-title">
          <span class="ep-number">S{season(@game.difficulty)} · E{@round}</span>
          {Shows.episode_title(@show.id, @round)}
        </span>
        <.pin :if={@xray} section="process" n={7} />
      </div>

      <div class="board-grid">
        <div class="set-panel">
          <.pin :if={@xray} section="mascot" n={4} />
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
          <div
            :if={@caption}
            id={"cc-#{@caption_n}"}
            class="caption"
            aria-hidden="true"
          >
            {@caption}
          </div>
          <div class="takes" id="takes">
            <span class="takes-label">Takes left</span>
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
          </div>
        </div>

        <div class="play-col">
          <div class="clue-card">
            <p class="clue-label">Clue</p>
            <p class="clue-text">{@game.clue}</p>
          </div>

          <div class="word-card">
            <.pin :if={@xray} section="word" n={1} />
            <div
              id="word"
              class={["word", length(Game.tiles(@game)) > 11 && "word--long"]}
              role="img"
              aria-label={"Answer: " <> Game.masked(@game)}
            >
              <span
                :for={{tile, i} <- Enum.with_index(Game.tiles(@game))}
                class={[
                  "tile",
                  tile.char == " " && "tile--gap",
                  !tile.letter? && tile.char != " " && "tile--punct",
                  tile.revealed && "is-revealed",
                  tile.missed && "is-missed"
                ]}
                data-index={i}
                data-revealed={to_string(tile.revealed)}
              >
                <span :if={tile.revealed or !tile.letter?}>{if tile.char == " ",
                  do: "",
                  else: tile.char}</span>
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
                class="btn-ghost"
                id="hint"
                disabled={Game.lives(@game) <= 1}
              >
                Hint ({@game.hints_left})
              </button>
            </div>
          </div>

          <div id="keyboard" class="keyboard" aria-label="Letters">
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
            <p class="hint-text mt-3 hidden text-center sm:block">
              Type to guess · <kbd>?</kbd> hint · <kbd>Esc</kbd> TV guide
            </p>
          </div>
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
        <p class="result-word">{@game.word}</p>
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
          <button type="button" phx-click="next" class="btn-primary flex-1 justify-center" id="next">
            Next episode <kbd class="kbd-dark">Enter</kbd>
          </button>
          <button type="button" phx-click="menu" class="btn-ghost flex-1 justify-center">
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

  attr :tab, :string, required: true
  attr :section, :map, default: nil
  attr :runtime, :map, default: nil

  defp xray_panel(assigns) do
    ~H"""
    <aside id="xray-panel" class="xray-panel" aria-label="X-ray: how this page works">
      <div class="xp-head">
        <div>
          <p class="xp-kicker">X-ray mode</p>
          <h2 class="xp-title">How this page works</h2>
        </div>
        <button type="button" phx-click="xray" class="xp-close" aria-label="Close X-ray">✕</button>
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
            <dt>Schedulers</dt><dd>{@runtime.schedulers}</dd>
          </div>
          <div>
            <dt>Server uptime</dt><dd>{@runtime.uptime}</dd>
          </div>
          <div>
            <dt>Transport</dt><dd id="xp-transport" phx-hook="Transport" phx-update="ignore">…</dd>
          </div>
          <div>
            <dt>Runtime</dt><dd>{@runtime.versions}</dd>
          </div>
        </dl>
      </div>

      <nav class="xp-tabs" role="tablist">
        <button
          :for={
            {id, label} <- [
              {"inside", "Inside"},
              {"wire", "Live wire"},
              {"lessons", "What I learned"}
            ]
          }
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

  defp message_text(nil), do: ""
  defp message_text({_kind, text}), do: text

  defp message_class({:hit, _}), do: "message--hit"
  defp message_class({:miss, _}), do: "message--miss"
  defp message_class(_), do: nil
end
