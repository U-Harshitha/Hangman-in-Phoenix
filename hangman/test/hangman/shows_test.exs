defmodule Hangman.ShowsTest do
  use ExUnit.Case, async: true

  alias Hangman.{Game, Shows}

  test "every show has a playable trivia bank" do
    for %{id: id, count: count, titles: titles, hit: hit, miss: miss} <- Shows.all() do
      assert count >= 30, "#{id} only has #{count} entries"
      assert titles != [] and hit != [] and miss != []

      for %{word: word, clue: clue} <- Shows.entries(id) do
        assert Game.letters(word) != [], "#{word} has no letters"
        assert clue != "", "#{word} has no clue"
        refute String.contains?(String.downcase(clue), word), "clue gives away #{word}"
      end
    end
  end

  test "parse only accepts known channels" do
    assert Shows.parse("friends") == :friends
    assert Shows.parse("surf") == :surf
    assert Shows.parse("../etc/passwd") == nil
    assert Shows.parse(nil) == nil
  end

  test "random/3 honours difficulty, exclusions and channel surfing" do
    for _ <- 1..40 do
      {:friends, %{word: easy}} = Shows.random(:friends, :easy)
      assert Shows.letter_count(easy) in 4..7
      {:big_bang, %{word: hard}} = Shows.random(:big_bang, :hard)
      assert Shows.letter_count(hard) >= 9
      {show, _} = Shows.random(:surf, :normal)
      assert show in Shows.ids()
    end

    [only | rest] =
      :brooklyn_99 |> Shows.entries() |> Enum.filter(&(Shows.letter_count(&1.word) >= 9))

    assert {:brooklyn_99, ^only} = Shows.random(:brooklyn_99, :hard, Enum.map(rest, & &1.word))
  end

  test "episode titles cycle" do
    first = Shows.episode_title(:friends, 1)
    assert first =~ "The One"
    assert Shows.episode_title(:friends, 1 + length(Shows.get(:friends).titles)) == first
  end
end
