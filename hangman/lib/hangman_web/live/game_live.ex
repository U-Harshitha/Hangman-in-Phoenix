defmodule HangmanWeb.GameLive do
  @moduledoc """
  The whole game in one LiveView: a menu (category + difficulty) and the
  board. All rules live in `Hangman.Game`; this module only translates
  clicks/keys into moves and pushes "fx" events so the client can animate
  what just happened (GSAP for the board, Three.js for the background).
  """
  use HangmanWeb, :live_view

  alias Hangman.{Game, Stats, Words}

  @keyboard ~w(qwertyuiop asdfghjkl zxcvbnm) |> Enum.map(&String.graphemes/1)
  @difficulties [
    {:easy, "Easy", "Short words · 2 hints"},
    {:normal, "Normal", "Any length · 1 hint"},
    {:hard, "Hard", "Long words · no hints"}
  ]
  @recent_limit 30

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Play",
       screen: :menu,
       category: :classic,
       difficulty: :normal,
       game: nil,
       round: 0,
       recent: [],
       message: nil,
       last_points: 0,
       stats: restore_stats(socket),
       categories: Words.categories(),
       difficulties: @difficulties,
       keyboard: @keyboard,
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

  # ── Events ────────────────────────────────────────────────────────────

  @impl true
  def handle_event("pick_category", %{"category" => value}, socket) do
    case Words.parse_category(value) do
      nil -> {:noreply, socket}
      category -> {:noreply, assign(socket, category: category)}
    end
  end

  def handle_event("pick_difficulty", %{"difficulty" => value}, socket) do
    case Enum.find(@difficulties, fn {id, _, _} -> Atom.to_string(id) == value end) do
      nil -> {:noreply, socket}
      {difficulty, _, _} -> {:noreply, assign(socket, difficulty: difficulty)}
    end
  end

  # Guards make these idempotent: pressing Enter on a focused button fires
  # both the click and the window keydown, which must not skip a word.
  def handle_event("start", _params, %{assigns: %{screen: :menu}} = socket),
    do: {:noreply, start_round(socket)}

  def handle_event("next", _params, %{assigns: %{game: %Game{status: status}}} = socket)
      when status != :playing,
      do: {:noreply, start_round(socket)}

  def handle_event(event, _params, socket) when event in ["start", "next"],
    do: {:noreply, socket}

  def handle_event("menu", _params, socket) do
    {:noreply, socket |> assign(screen: :menu) |> push_event("fx", %{kind: "menu"})}
  end

  def handle_event("guess", %{"letter" => letter}, socket), do: {:noreply, guess(socket, letter)}
  def handle_event("hint", _params, socket), do: {:noreply, hint(socket)}

  # Physical keyboard: letters guess, Enter plays / continues, Escape = menu.
  def handle_event("key", %{"key" => key}, socket) do
    %{screen: screen, game: game} = socket.assigns

    socket =
      cond do
        key == "Enter" and (screen == :menu or Game.over?(game)) -> start_round(socket)
        key == "Escape" and screen == :game -> assign(socket, screen: :menu)
        key == "?" and screen == :game -> hint(socket)
        screen == :game and String.length(key) == 1 -> guess(socket, key)
        true -> socket
      end

    {:noreply, socket}
  end

  def handle_event("key", _params, socket), do: {:noreply, socket}

  # ── Moves ─────────────────────────────────────────────────────────────

  defp start_round(socket) do
    %{category: category, difficulty: difficulty, recent: recent} = socket.assigns
    word = Words.random(category, difficulty, recent)
    game = Game.new(word, category: category, difficulty: difficulty)

    socket
    |> assign(
      screen: :game,
      game: game,
      round: socket.assigns.round + 1,
      recent: Enum.take([word | recent], @recent_limit),
      last_points: 0,
      message: {:info, "#{length(Game.letters(word))} different letters. Good luck."}
    )
    |> push_event("fx", %{kind: "start"})
  end

  defp guess(%{assigns: %{game: %Game{status: :playing} = game}} = socket, letter) do
    letter = String.downcase(letter)

    case Game.guess(game, letter) do
      {:hit, game} ->
        count = length(Game.positions(game, letter))
        times = if count == 1, do: "once", else: "#{count}×"

        socket
        |> assign(game: game, message: {:hit, "#{String.upcase(letter)} appears #{times}."})
        |> push_event("fx", %{
          kind: "hit",
          letter: letter,
          positions: Game.positions(game, letter)
        })
        |> maybe_finish()

      {:miss, game} ->
        socket
        |> assign(
          game: game,
          message: {:miss, "No #{String.upcase(letter)}. #{flame_count(Game.lives(game))} left."}
        )
        |> push_event("fx", %{kind: "miss", letter: letter, lives: Game.lives(game)})
        |> maybe_finish()

      {:already_guessed, _game} ->
        socket
        |> assign(message: {:info, "You already tried #{String.upcase(letter)}."})
        |> push_event("fx", %{kind: "repeat", letter: letter})

      {_other, _game} ->
        socket
    end
  end

  defp guess(socket, _letter), do: socket

  defp hint(%{assigns: %{game: %Game{status: :playing} = game}} = socket) do
    case Game.hint(game) do
      {:ok, letter, game} ->
        socket
        |> assign(
          game: game,
          message: {:hit, "Hint: #{String.upcase(letter)}. It cost you a flame."}
        )
        |> push_event("fx", %{
          kind: "hint",
          letter: letter,
          positions: Game.positions(game, letter),
          lives: Game.lives(game)
        })
        |> maybe_finish()

      {:error, :no_hints, _} ->
        assign(socket, message: {:info, "No hints left this round."})

      {:error, :last_life, _} ->
        assign(socket, message: {:info, "Hints cost a flame, and this is your last one."})

      {:error, _, _} ->
        socket
    end
  end

  defp hint(socket), do: socket

  defp maybe_finish(%{assigns: %{game: %Game{status: :playing}}} = socket), do: socket

  defp maybe_finish(%{assigns: %{game: game, stats: stats}} = socket) do
    stats = Stats.record(stats, game)
    points = Game.score(game)

    socket
    |> assign(stats: stats, last_points: points)
    |> push_event("stats", Stats.to_map(stats))
    |> push_event("fx", %{kind: if(Game.won?(game), do: "win", else: "lose")})
  end

  defp flame_count(1), do: "1 flame"
  defp flame_count(n), do: "#{n} flames"

  # ── Rendering ─────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="app" phx-window-keydown="key" class="flex flex-1 flex-col">
        <.topbar stats={@stats} portfolio_url={@portfolio_url} screen={@screen} />
        <main class="mx-auto flex w-full max-w-6xl flex-1 flex-col px-4 pb-10 sm:px-6">
          <.menu
            :if={@screen == :menu}
            categories={@categories}
            category={@category}
            difficulties={@difficulties}
            difficulty={@difficulty}
            stats={@stats}
          />
          <.board
            :if={@screen == :game}
            game={@game}
            round={@round}
            message={@message}
            keyboard={@keyboard}
            stats={@stats}
            last_points={@last_points}
          />
        </main>
        <footer class="mx-auto w-full max-w-6xl px-4 pb-6 text-xs text-muted sm:px-6">
          Built with Elixir · Phoenix LiveView · GSAP · Three.js.
          <a
            href="https://github.com/U-Harshitha/Hangman-in-Phoenix"
            class="underline decoration-line underline-offset-4 hover:text-chalk"
            target="_blank"
            rel="noopener"
          >
            Source
          </a>
        </footer>
      </div>
    </Layouts.app>
    """
  end

  attr :stats, Stats, required: true
  attr :portfolio_url, :string, required: true
  attr :screen, :atom, required: true

  defp topbar(assigns) do
    ~H"""
    <header class="mx-auto flex w-full max-w-6xl items-center justify-between gap-4 px-4 py-5 sm:px-6">
      <a href={@portfolio_url} class="back-link group" aria-label="Back to portfolio">
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
        :if={@screen == :game}
        type="button"
        phx-click="menu"
        class="brand"
        aria-label="Back to menu"
      >
        Hangman<span class="hidden sm:inline"><span class="text-ember">·</span> <em>in Phoenix</em></span>
      </button>
      <div :if={@screen == :menu} class="brand">
        Hangman<span class="hidden sm:inline"><span class="text-ember">·</span> <em>in Phoenix</em></span>
      </div>
      <dl class="stats" id="stats-bar">
        <div>
          <dt>Score</dt><dd data-stat="score">{@stats.score}</dd>
        </div>
        <div>
          <dt>Streak</dt><dd data-stat="streak">{@stats.streak}</dd>
        </div>
        <div class="hidden sm:block">
          <dt>Wins</dt><dd>{@stats.wins}/{@stats.played}</dd>
        </div>
      </dl>
    </header>
    """
  end

  attr :categories, :list, required: true
  attr :category, :atom, required: true
  attr :difficulties, :list, required: true
  attr :difficulty, :atom, required: true
  attr :stats, Stats, required: true

  defp menu(assigns) do
    ~H"""
    <section
      id="menu"
      phx-hook="Intro"
      class="grid flex-1 items-center gap-10 py-6 lg:grid-cols-[1.05fr_1fr] lg:gap-16"
    >
      <div>
        <p class="kicker" data-intro>An Elixir · Phoenix LiveView game</p>
        <h1 class="hero-title" aria-label="Hangman">
          <span :for={ch <- String.graphemes("Hangman")} class="hero-letter" aria-hidden="true">{ch}</span>
        </h1>
        <p class="mt-5 max-w-md text-lg text-muted" data-intro>
          Guess the word one letter at a time. Every miss puts out a flame.
          Lose all six and the phoenix doesn't rise.
        </p>
        <div class="mt-8 flex flex-wrap items-center gap-3" data-intro>
          <button type="button" phx-click="start" class="btn-primary" id="play">
            Play {Words.label(@category)}
            <svg viewBox="0 0 20 20" class="size-4" aria-hidden="true">
              <path
                d="M4 10h11m-4.5-5.5L16 10l-5.5 5.5"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>
          </button>
          <span class="text-sm text-muted">or press <kbd>Enter</kbd></span>
        </div>
        <dl :if={@stats.played > 0} class="mt-10 flex gap-8 text-sm" data-intro>
          <div>
            <dt class="text-muted">Played</dt><dd class="stat-big">{@stats.played}</dd>
          </div>
          <div>
            <dt class="text-muted">Win rate</dt><dd class="stat-big">{Stats.win_rate(@stats)}%</dd>
          </div>
          <div>
            <dt class="text-muted">Best streak</dt><dd class="stat-big">{@stats.best_streak}</dd>
          </div>
        </dl>
      </div>

      <div class="panel p-5 sm:p-7" data-intro>
        <h2 class="panel-label">Choose a category</h2>
        <div
          class="mt-4 grid grid-cols-2 gap-2.5 sm:grid-cols-3"
          role="radiogroup"
          aria-label="Category"
        >
          <button
            :for={{cat, i} <- Enum.with_index(@categories, 1)}
            type="button"
            role="radio"
            aria-checked={to_string(cat.id == @category)}
            phx-click="pick_category"
            phx-value-category={cat.id}
            class={["choice", cat.id == @category && "is-selected"]}
            data-card
          >
            <span class="choice-index">{String.pad_leading(to_string(i), 2, "0")}</span>
            <span class="choice-label">{cat.label}</span>
            <span class="choice-blurb">{cat.blurb}</span>
          </button>
        </div>

        <h2 class="panel-label mt-7">Difficulty</h2>
        <div class="segmented mt-3" role="radiogroup" aria-label="Difficulty">
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
    </section>
    """
  end

  attr :game, Game, required: true
  attr :round, :integer, required: true
  attr :message, :any, required: true
  attr :keyboard, :list, required: true
  attr :stats, Stats, required: true
  attr :last_points, :integer, required: true

  defp board(assigns) do
    ~H"""
    <section
      id="board"
      phx-hook="Board"
      class="grid flex-1 items-start gap-4 py-1 sm:gap-6 sm:py-2 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)] lg:gap-10"
    >
      <div class="panel relative flex flex-col items-center p-4 sm:p-6">
        <div class="flex w-full items-center justify-between gap-2">
          <span class="chip">{Words.label(@game.category)}</span>
          <span class="chip chip--ghost capitalize">{@game.difficulty} · round {@round}</span>
        </div>
        <.gallows game={@game} round={@round} />
        <.flames lives={Game.lives(@game)} />
      </div>

      <div class="flex flex-col gap-4 sm:gap-6">
        <div class="panel p-4 sm:p-7">
          <div
            id="word"
            class="word"
            role="img"
            aria-label={"Word: " <> Game.masked(@game)}
          >
            <span
              :for={{tile, i} <- Enum.with_index(Game.tiles(@game))}
              class={[
                "tile",
                !tile.letter? && "tile--gap",
                tile.revealed && "is-revealed",
                tile.missed && "is-missed"
              ]}
              data-index={i}
              data-revealed={to_string(tile.revealed)}
            >
              <span :if={tile.letter? and tile.revealed}>{tile.char}</span>
            </span>
          </div>
          <div class="mt-4 flex flex-wrap items-center justify-between gap-3 sm:mt-5">
            <p id="message" class={["message", message_class(@message)]} aria-live="polite">
              {message_text(@message)}
            </p>
            <button
              :if={@game.hints_left > 0 and @game.status == :playing}
              type="button"
              phx-click="hint"
              class="btn-ghost"
              id="hint"
              disabled={Game.lives(@game) <= 1}
            >
              <svg viewBox="0 0 20 20" class="size-4" aria-hidden="true">
                <path
                  d="M10 2.5a5.5 5.5 0 0 0-3.2 10V15h6.4v-2.5A5.5 5.5 0 0 0 10 2.5ZM7.8 17.5h4.4"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="1.6"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
              Hint ({@game.hints_left})
            </button>
          </div>
        </div>

        <div id="keyboard" class="keyboard" aria-label="Letters">
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
          <p class="mt-3 hidden text-center text-xs text-muted sm:block">
            Type on your keyboard · <kbd>?</kbd> hint · <kbd>Esc</kbd> menu
          </p>
        </div>
      </div>

      <.result :if={Game.over?(@game)} game={@game} stats={@stats} points={@last_points} />
    </section>
    """
  end

  attr :game, Game, required: true
  attr :round, :integer, required: true

  # The SVG is phx-update="ignore": the Gallows hook owns the drawing and
  # animates parts in as `data-mistakes` changes on the wrapper.
  defp gallows(assigns) do
    ~H"""
    <div
      id="gallows"
      phx-hook="Gallows"
      data-mistakes={Game.mistakes(@game)}
      data-status={@game.status}
      data-round={@round}
      class="my-2 w-full max-w-[8.5rem] sm:my-4 sm:max-w-[19rem]"
    >
      <svg
        id="gallows-svg"
        phx-update="ignore"
        viewBox="0 0 240 280"
        class="gallows"
        role="img"
        aria-label="Gallows"
      >
        <defs>
          <filter id="chalk" x="-10%" y="-10%" width="120%" height="120%">
            <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" result="noise" />
            <feDisplacementMap in="SourceGraphic" in2="noise" scale="1.6" />
          </filter>
        </defs>
        <g class="gallows-frame" filter="url(#chalk)">
          <path data-frame d="M18 262 Q120 255 222 262" />
          <path data-frame d="M64 262 L64 28" />
          <path data-frame d="M54 30 L180 30" />
          <path data-frame d="M64 74 L108 30" />
          <path data-frame d="M168 30 L168 64" />
        </g>
        <g class="gallows-figure" filter="url(#chalk)">
          <circle data-part="0" cx="168" cy="86" r="22" />
          <path data-part="1" d="M168 108 L168 176" />
          <path data-part="2" d="M168 124 L138 156" />
          <path data-part="3" d="M168 124 L198 156" />
          <path data-part="4" d="M168 176 L142 222" />
          <path data-part="5" d="M168 176 L194 222" />
          <g class="gallows-face">
            <path d="M157 80 l7 7 m0 -7 l-7 7 M172 80 l7 7 m0 -7 l-7 7" />
            <path d="M160 98 q8 -5 16 0" />
          </g>
        </g>
      </svg>
    </div>
    """
  end

  attr :lives, :integer, required: true

  defp flames(assigns) do
    ~H"""
    <div id="flames" class="flames" aria-label={"#{@lives} of #{Game.max_lives()} flames left"}>
      <span
        :for={i <- 1..Game.max_lives()}
        class={["flame", i > @lives && "is-out"]}
        data-flame={i}
        aria-hidden="true"
      >
        <svg viewBox="0 0 24 32">
          <path d="M12 2c1.2 4.5 6.8 7.4 6.8 14.6A6.8 6.8 0 0 1 12 23.4a6.8 6.8 0 0 1-6.8-6.8c0-3.4 1.7-5.4 3.3-7 .3 2.2 1.3 3.5 2.6 4.1C10.7 9.7 11.2 5.6 12 2Z" />
        </svg>
      </span>
    </div>
    """
  end

  attr :game, Game, required: true
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
      <div class="result-card panel">
        <p class="kicker">{if Game.won?(@game), do: "Solved", else: "Out of flames"}</p>
        <h2 id="result-title" class="result-title">
          {if Game.won?(@game), do: "The phoenix rises.", else: "So close."}
        </h2>
        <p class="mt-3 text-muted">The word was</p>
        <p class="result-word">{@game.word}</p>
        <dl class="mt-6 grid grid-cols-3 gap-3 text-center">
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
        <div class="result-actions mt-7 flex flex-col gap-2.5 sm:flex-row">
          <button type="button" phx-click="next" class="btn-primary flex-1 justify-center" id="next">
            Next word <kbd class="kbd-dark">Enter</kbd>
          </button>
          <button type="button" phx-click="menu" class="btn-ghost flex-1 justify-center">
            Change category
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp message_text(nil), do: ""
  defp message_text({_kind, text}), do: text

  defp message_class({:hit, _}), do: "message--hit"
  defp message_class({:miss, _}), do: "message--miss"
  defp message_class(_), do: nil
end
