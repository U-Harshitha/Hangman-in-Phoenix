defmodule Hangman.StatsTest do
  use ExUnit.Case, async: true

  alias Hangman.{Game, Stats}

  test "from_params ignores junk and keeps totals consistent" do
    assert Stats.from_params(nil) == Stats.new()
    assert Stats.from_params(%{"score" => "lots", "played" => -1}) == Stats.new()

    stats = Stats.from_params(%{"played" => 2, "wins" => 9, "streak" => 9, "score" => 120})
    assert stats.wins == 2
    assert stats.streak == 2
    assert stats.best_streak == 2
    assert stats.score == 120
  end

  test "record wins and losses" do
    won = Enum.reduce(~w(o k), Game.new("ok"), fn l, g -> elem(Game.guess(g, l), 1) end)
    lost = Enum.reduce(~w(a b c d e f), Game.new("ok"), fn l, g -> elem(Game.guess(g, l), 1) end)

    stats = Stats.new() |> Stats.record(won) |> Stats.record(won)
    assert %{played: 2, wins: 2, streak: 2, best_streak: 2} = stats
    assert stats.score == 2 * Game.score(won)

    stats = Stats.record(stats, lost)
    assert %{played: 3, wins: 2, streak: 0, best_streak: 2} = stats
    assert Stats.win_rate(stats) == 67
  end
end
