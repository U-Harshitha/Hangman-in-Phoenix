defmodule Hangman.WordsTest do
  use ExUnit.Case, async: true

  alias Hangman.{Game, Words}

  test "every category has playable words" do
    for %{id: id, count: count} <- Words.categories() do
      assert count >= 30, "#{id} only has #{count} words"
      assert Enum.all?(Words.all(id), &(Game.letters(&1) != []))
    end
  end

  test "parse_category only accepts known ids" do
    assert Words.parse_category("animals") == :animals
    assert Words.parse_category("../etc/passwd") == nil
    assert Words.parse_category(nil) == nil
  end

  test "random/3 honours difficulty and exclusions" do
    for _ <- 1..50 do
      assert String.length(Words.random(:classic, :easy)) in 4..6
      assert String.length(Words.random(:classic, :hard)) >= 8
    end

    [only | rest] = Words.all(:space) |> Enum.filter(&(String.length(&1) >= 8))
    assert Words.random(:space, :hard, rest) == only
  end
end
