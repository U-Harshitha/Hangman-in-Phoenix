defmodule Hangman.Shows do
  @moduledoc """
  The four sitcom "channels": who they are, how they talk, and their
  trivia word banks (compiled in from `priv/words/<show>.txt`).

  Each word file line is `answer | clue`. Reading them at compile time
  means the words ship inside the release, with no runtime file paths.
  """

  @shows [
    %{
      id: :friends,
      channel: 1,
      name: "Friends",
      mascot: "Marcel",
      tagline: "Don't let Marcel drop.",
      hit: ["How you doin'?", "Pivot! Nailed it.", "Could this BE any better?"],
      miss: ["Oh. My. God.", "We were on a break from that letter.", "Unagi failed you."],
      win: "The One Where You Won",
      lose: "The One Where Marcel Fell",
      lose_line: "Marcel's off to the San Diego Zoo.",
      titles: [
        "The One With the Missing Letters",
        "The One Where Marcel Hangs Around",
        "The One With All the Vowels",
        "The One Where Everyone Guesses",
        "The One With the Spelling Bee"
      ]
    },
    %{
      id: :big_bang,
      channel: 2,
      name: "The Big Bang Theory",
      short: "Big Bang Theory",
      mascot: "the Atom",
      tagline: "Six misses and the atom goes bang.",
      hit: ["Bazinga!", "Fascinating.", "Correct. Obviously."],
      miss: ["That's my spot. And my letter.", "A flaw in your hypothesis.", "Insufficient data."],
      win: "The Solved Word Hypothesis",
      lose: "The Big Bang",
      lose_line: "Critical mass reached. Back to the whiteboard.",
      titles: [
        "The Vowel Hypothesis",
        "The Consonant Conundrum",
        "The Letter Fluctuation",
        "The Alphabet Approximation",
        "The Lexical Bifurcation"
      ]
    },
    %{
      id: :modern_family,
      channel: 3,
      name: "Modern Family",
      mascot: "Fizbo",
      tagline: "Every miss, Fizbo gets closer.",
      hit: ["Phil's-osophy approved.", "Family hug!", "That's a Dunphy-level guess."],
      miss: [
        "Somewhere, a clown honks.",
        "Fizbo is getting ready.",
        "Not even Phil would guess that."
      ],
      win: "Family Game Night Champion",
      lose: "Fizbo Has Arrived",
      lose_line: "Fizbo is here, and Mitchell is not happy.",
      titles: [
        "Game Night at Jay's",
        "Phil's Big Guess",
        "Cam's Dramatic Reveal",
        "The Dunphy Spelling Bee",
        "Claire Keeps Score"
      ]
    },
    %{
      id: :brooklyn_99,
      channel: 4,
      name: "Brooklyn Nine-Nine",
      short: "Brooklyn 99",
      mascot: "Cheddar",
      tagline: "Keep Cheddar out of the lineup.",
      hit: ["Noice.", "Cool cool cool.", "Toit."],
      miss: ["BONE?!", "Cool cool cool. No doubt. No.", "That's a lineup-worthy mistake."],
      win: "Case Closed",
      lose: "Cheddar Gets Booked",
      lose_line: "Cheddar is in the lineup. Holt is furious.",
      titles: [
        "The Missing Letters Heist",
        "The Vowel Caper",
        "The Consonant Case",
        "A Halloween Heist of Letters",
        "The Pontiac Speller"
      ]
    }
  ]

  @words_dir Path.expand("../../priv/words", __DIR__)

  @bank (for %{id: id} <- @shows, into: %{} do
           path = Path.join(@words_dir, "#{id}.txt")
           @external_resource path

           entries =
             path
             |> File.read!()
             |> String.split("\n", trim: true)
             |> Enum.reject(&String.starts_with?(&1, "#"))
             |> Enum.map(fn line ->
               [word, clue] = line |> String.split("|", parts: 2) |> Enum.map(&String.trim/1)
               %{word: String.downcase(word), clue: clue}
             end)
             |> Enum.filter(&Regex.match?(~r/^[a-z][a-z \-']{2,}[a-z]$/, &1.word))
             |> Enum.uniq_by(& &1.word)

           {id, entries}
         end)

  @ids Enum.map(@shows, & &1.id)

  @doc "All shows in channel order, with word counts."
  def all do
    for show <- @shows do
      show
      |> Map.put_new(:short, show.name)
      |> Map.put(:count, length(Map.fetch!(@bank, show.id)))
    end
  end

  def ids, do: @ids

  @doc "A show by id."
  def get(id) when id in @ids, do: Enum.find(all(), &(&1.id == id))

  @doc "Safely turn client input into a show id; `\"surf\"` means all shows."
  def parse(value) when is_binary(value) do
    if value == "surf", do: :surf, else: Enum.find(@ids, &(Atom.to_string(&1) == value))
  end

  def parse(_), do: nil

  @doc "Every `%{word, clue}` entry for a show."
  def entries(id) when id in @ids, do: Map.fetch!(@bank, id)

  def total_words, do: @bank |> Map.values() |> Enum.map(&length/1) |> Enum.sum()

  @doc """
  Pick a random entry for `id` (or `:surf` for any show), sized for
  `difficulty`: easy 4-7 letters, normal 5-11, hard 9+. Words in `exclude`
  are skipped when possible. Returns `{show_id, %{word, clue}}`.
  """
  def random(id, difficulty \\ :normal, exclude \\ [])

  def random(:surf, difficulty, exclude), do: random(Enum.random(@ids), difficulty, exclude)

  def random(id, difficulty, exclude) when id in @ids do
    entries = entries(id)
    sized = Enum.filter(entries, &fits?(&1.word, difficulty))
    pool = if sized == [], do: entries, else: sized

    entry =
      case Enum.reject(pool, &(&1.word in exclude)) do
        [] -> Enum.random(pool)
        fresh -> Enum.random(fresh)
      end

    {id, entry}
  end

  @doc "An episode title for round `n` of a show."
  def episode_title(id, n) when id in @ids do
    titles = get(id).titles
    Enum.at(titles, rem(n - 1, length(titles)))
  end

  def letter_count(word), do: word |> String.replace(~r/[^a-z]/, "") |> String.length()

  defp fits?(word, difficulty) do
    n = letter_count(word)

    case difficulty do
      :easy -> n in 4..7
      :normal -> n in 5..11
      :hard -> n >= 9
    end
  end
end
