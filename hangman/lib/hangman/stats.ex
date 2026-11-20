defmodule Hangman.Stats do
  @moduledoc """
  A player's running totals. Kept in the LiveView and mirrored to the
  browser's localStorage, so they survive reloads without a database.
  """

  defstruct played: 0, wins: 0, streak: 0, best_streak: 0, score: 0

  @fields [:played, :wins, :streak, :best_streak, :score]
  @max 10_000_000

  def new, do: %__MODULE__{}

  @doc "Rebuild stats from untrusted client params, ignoring anything odd."
  def from_params(%{} = params) do
    stats =
      Enum.reduce(@fields, new(), fn field, acc ->
        case Map.get(params, Atom.to_string(field)) do
          n when is_integer(n) and n >= 0 and n <= @max -> Map.put(acc, field, n)
          _ -> acc
        end
      end)

    wins = min(stats.wins, stats.played)
    streak = min(stats.streak, wins)
    %{stats | wins: wins, streak: streak, best_streak: min(max(stats.best_streak, streak), wins)}
  end

  def from_params(_), do: new()

  @doc "Fold a finished game into the totals."
  def record(%__MODULE__{} = stats, %Hangman.Game{status: :won} = game) do
    streak = stats.streak + 1

    %{
      stats
      | played: stats.played + 1,
        wins: stats.wins + 1,
        streak: streak,
        best_streak: max(stats.best_streak, streak),
        score: stats.score + Hangman.Game.score(game)
    }
  end

  def record(%__MODULE__{} = stats, %Hangman.Game{status: :lost}) do
    %{stats | played: stats.played + 1, streak: 0}
  end

  def record(stats, _game), do: stats

  def win_rate(%__MODULE__{played: 0}), do: 0
  def win_rate(%__MODULE__{played: played, wins: wins}), do: round(wins * 100 / played)

  def to_map(%__MODULE__{} = stats), do: Map.take(stats, @fields)
end
