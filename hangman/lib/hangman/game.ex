defmodule Hangman.Game do
  @moduledoc """
  Pure, immutable hangman rules.

  A game is a plain struct; every move returns a tagged tuple with the new
  game so the LiveView (or a test) can react to *what happened*, not just
  the resulting state:

      iex> game = Hangman.Game.new("elixir")
      iex> {:hit, game} = Hangman.Game.guess(game, "e")
      iex> {:miss, game} = Hangman.Game.guess(game, "z")
      iex> Hangman.Game.lives(game)
      5

  Only the letters `a..z` are guessable. Anything else in a word (spaces,
  hyphens) is shown from the start, so multi-word answers like
  `"new zealand"` work naturally.
  """

  @max_lives 6
  @letters for c <- ?a..?z, do: <<c>>

  @type difficulty :: :easy | :normal | :hard
  @type status :: :playing | :won | :lost
  @type t :: %__MODULE__{
          word: String.t(),
          category: atom(),
          difficulty: difficulty(),
          guessed: MapSet.t(String.t()),
          misses: [String.t()],
          lives: non_neg_integer(),
          hints_left: non_neg_integer(),
          hints_used: non_neg_integer(),
          status: status()
        }

  @enforce_keys [:word]
  defstruct word: "",
            category: :classic,
            difficulty: :normal,
            guessed: MapSet.new(),
            misses: [],
            lives: @max_lives,
            hints_left: 1,
            hints_used: 0,
            status: :playing

  @doc "Start a new game for `word`. Options: `:category`, `:difficulty`."
  @spec new(String.t(), keyword()) :: t()
  def new(word, opts \\ []) when is_binary(word) do
    word = word |> String.trim() |> String.downcase()

    if letters(word) == [] do
      raise ArgumentError, "a hangman word needs at least one letter, got: #{inspect(word)}"
    end

    difficulty = Keyword.get(opts, :difficulty, :normal)

    %__MODULE__{
      word: word,
      category: Keyword.get(opts, :category, :classic),
      difficulty: difficulty,
      hints_left: hints_for(difficulty)
    }
  end

  @doc "How many hints each difficulty gets."
  @spec hints_for(difficulty()) :: non_neg_integer()
  def hints_for(:easy), do: 2
  def hints_for(:normal), do: 1
  def hints_for(:hard), do: 0

  def max_lives, do: @max_lives
  def alphabet, do: @letters

  @doc """
  Guess a single letter.

  Returns `{:hit, game}`, `{:miss, game}`, `{:already_guessed, game}`,
  `{:invalid, game}` or `{:game_over, game}`.
  """
  @spec guess(t(), String.t()) ::
          {:hit | :miss | :already_guessed | :invalid | :game_over, t()}
  def guess(%__MODULE__{status: status} = game, _letter) when status != :playing,
    do: {:game_over, game}

  def guess(%__MODULE__{} = game, letter) when is_binary(letter) do
    letter = String.downcase(letter)

    cond do
      letter not in @letters ->
        {:invalid, game}

      MapSet.member?(game.guessed, letter) ->
        {:already_guessed, game}

      String.contains?(game.word, letter) ->
        {:hit, settle(%{game | guessed: MapSet.put(game.guessed, letter)})}

      true ->
        game = %{
          game
          | guessed: MapSet.put(game.guessed, letter),
            misses: game.misses ++ [letter],
            lives: game.lives - 1
        }

        {:miss, settle(game)}
    end
  end

  def guess(game, _letter), do: {:invalid, game}

  @doc """
  Spend a hint: reveals the hidden letter that uncovers the most tiles.
  A hint costs one life, so it is refused when only one life is left.
  """
  @spec hint(t()) :: {:ok, String.t(), t()} | {:error, :no_hints | :last_life | :game_over, t()}
  def hint(%__MODULE__{status: status} = game) when status != :playing,
    do: {:error, :game_over, game}

  def hint(%__MODULE__{hints_left: 0} = game), do: {:error, :no_hints, game}
  def hint(%__MODULE__{lives: lives} = game) when lives <= 1, do: {:error, :last_life, game}

  def hint(%__MODULE__{} = game) do
    letter =
      game.word
      |> String.graphemes()
      |> Enum.filter(&(&1 in @letters and not MapSet.member?(game.guessed, &1)))
      |> Enum.frequencies()
      |> Enum.max_by(fn {_letter, count} -> count end)
      |> elem(0)

    game = %{
      game
      | guessed: MapSet.put(game.guessed, letter),
        hints_left: game.hints_left - 1,
        hints_used: game.hints_used + 1,
        lives: game.lives - 1
    }

    {:ok, letter, settle(game)}
  end

  @doc "Lives remaining."
  def lives(%__MODULE__{lives: lives}), do: lives

  @doc "Body parts drawn on the gallows (0..6)."
  def mistakes(%__MODULE__{lives: lives}), do: @max_lives - lives

  def won?(%__MODULE__{status: status}), do: status == :won
  def lost?(%__MODULE__{status: status}), do: status == :lost
  def over?(%__MODULE__{status: status}), do: status != :playing

  @doc """
  The word as a list of tiles: `%{char: "a", revealed: true, letter?: true}`.
  When the game is lost every tile is revealed, with `missed: true` on the
  ones the player never found.
  """
  def tiles(%__MODULE__{} = game) do
    for char <- String.graphemes(game.word) do
      letter? = char in @letters
      found? = not letter? or MapSet.member?(game.guessed, char)

      %{
        char: char,
        letter?: letter?,
        revealed: found? or game.status == :lost,
        missed: letter? and not found? and game.status == :lost
      }
    end
  end

  @doc "The masked word as plain text, e.g. `\"e _ i _ i _\"`."
  def masked(%__MODULE__{} = game) do
    game
    |> tiles()
    |> Enum.map_join(" ", fn
      %{letter?: false, char: char} -> char
      %{revealed: true, missed: false, char: char} -> char
      _ -> "_"
    end)
  end

  @doc "`:hit`, `:miss` or `:unused` for an on-screen keyboard key."
  def letter_state(%__MODULE__{} = game, letter) do
    cond do
      not MapSet.member?(game.guessed, letter) -> :unused
      String.contains?(game.word, letter) -> :hit
      true -> :miss
    end
  end

  @doc "Tile positions (0-based) where `letter` appears."
  def positions(%__MODULE__{word: word}, letter) do
    word
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.flat_map(fn {char, i} -> if char == letter, do: [i], else: [] end)
  end

  @doc "Points for a finished game. Lost games score 0."
  def score(%__MODULE__{status: :won} = game) do
    base = %{easy: 50, normal: 100, hard: 200}[game.difficulty]
    base + game.lives * 25 + length(letters(game.word)) * 5
  end

  def score(%__MODULE__{}), do: 0

  @doc "Unique guessable letters in a word."
  def letters(word) do
    word |> String.graphemes() |> Enum.filter(&(&1 in @letters)) |> Enum.uniq()
  end

  defp settle(%__MODULE__{} = game) do
    cond do
      Enum.all?(letters(game.word), &MapSet.member?(game.guessed, &1)) -> %{game | status: :won}
      game.lives <= 0 -> %{game | status: :lost}
      true -> game
    end
  end
end
