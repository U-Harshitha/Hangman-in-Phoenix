defmodule Hangman.GameTest do
  use ExUnit.Case, async: true
  doctest Hangman.Game

  alias Hangman.Game

  test "new/2 downcases and starts with six lives" do
    game = Game.new("  Phoenix ")
    assert game.word == "phoenix"
    assert Game.lives(game) == 6
    assert game.status == :playing
  end

  test "new/2 rejects words without letters" do
    assert_raise ArgumentError, fn -> Game.new("  ") end
  end

  test "hits keep lives, misses cost one" do
    game = Game.new("elixir")
    assert {:hit, game} = Game.guess(game, "E")
    assert Game.lives(game) == 6
    assert {:miss, game} = Game.guess(game, "q")
    assert Game.lives(game) == 5
    assert game.misses == ["q"]
    assert Game.mistakes(game) == 1
  end

  test "repeated, invalid and post-game guesses are reported, not counted" do
    game = Game.new("elixir")
    {:miss, game} = Game.guess(game, "q")
    assert {:already_guessed, ^game} = Game.guess(game, "q")
    assert {:invalid, ^game} = Game.guess(game, "1")
    assert {:invalid, ^game} = Game.guess(game, "ab")
    assert {:invalid, ^game} = Game.guess(game, nil)

    won = Enum.reduce(~w(e l i x r), game, fn l, g -> elem(Game.guess(g, l), 1) end)
    assert Game.won?(won)
    assert {:game_over, ^won} = Game.guess(won, "z")
  end

  test "six misses lose and reveal every tile" do
    game =
      Enum.reduce(~w(a b c d f g), Game.new("elixir"), fn l, g -> elem(Game.guess(g, l), 1) end)

    assert Game.lost?(game)
    assert Enum.all?(Game.tiles(game), & &1.revealed)
    assert Enum.all?(Game.tiles(game), & &1.missed)
  end

  test "spaces are free in multi-word answers" do
    game = Game.new("new zealand")
    assert Game.masked(game) == "_ _ _   _ _ _ _ _ _ _"
    game = Enum.reduce(~w(n e w z a l d), game, fn l, g -> elem(Game.guess(g, l), 1) end)
    assert Game.won?(game)
  end

  test "hint reveals the most frequent hidden letter and costs a life" do
    game = Game.new("banana", difficulty: :easy)
    assert {:ok, "a", game} = Game.hint(game)
    assert Game.lives(game) == 5
    assert game.hints_left == 1
    assert {:ok, "n", game} = Game.hint(game)
    assert {:error, :no_hints, _} = Game.hint(game)
  end

  test "hint is refused on the last life and on hard" do
    assert {:error, :no_hints, _} = Game.hint(Game.new("banana", difficulty: :hard))

    game =
      Enum.reduce(~w(q w e r t), Game.new("banana"), fn l, g -> elem(Game.guess(g, l), 1) end)

    assert Game.lives(game) == 1
    assert {:error, :last_life, _} = Game.hint(game)
  end

  test "keyboard state and positions" do
    {:hit, game} = Game.guess(Game.new("banana"), "a")
    {:miss, game} = Game.guess(game, "z")
    assert Game.letter_state(game, "a") == :hit
    assert Game.letter_state(game, "z") == :miss
    assert Game.letter_state(game, "b") == :unused
    assert Game.positions(game, "a") == [1, 3, 5]
  end

  test "score rewards difficulty and remaining lives" do
    win = fn difficulty ->
      Enum.reduce(~w(c a t), Game.new("cat", difficulty: difficulty), fn l, g ->
        elem(Game.guess(g, l), 1)
      end)
    end

    assert Game.score(win.(:easy)) == 50 + 6 * 25 + 3 * 5
    assert Game.score(win.(:hard)) > Game.score(win.(:normal))
    assert Game.score(Game.new("cat")) == 0
  end
end
