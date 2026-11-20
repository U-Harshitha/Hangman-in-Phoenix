defmodule Hangman.Words do
  @moduledoc """
  The word bank, compiled into the module from `priv/words/*.txt`.

  Reading the files at compile time (instead of `File.read!("assets/...")`
  at runtime, as v1 did) means the words ship inside the release and the
  app no longer depends on the current working directory.
  """

  @categories [
    {:classic, "Classic", "Everyday English words"},
    {:animals, "Animals", "Wild, wet & wonderful"},
    {:food, "Food", "Snacks from around the world"},
    {:countries, "Countries", "Pack your passport"},
    {:tech, "Tech", "For the developers"},
    {:space, "Space", "Look up tonight"}
  ]

  @words_dir Path.expand("../../priv/words", __DIR__)

  @bank (for {id, _label, _blurb} <- @categories, into: %{} do
           path = Path.join(@words_dir, "#{id}.txt")
           @external_resource path

           words =
             path
             |> File.read!()
             |> String.split("\n", trim: true)
             |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
             |> Enum.filter(&Regex.match?(~r/^[a-z][a-z \-]{2,}[a-z]$/, &1))
             |> Enum.uniq()

           {id, words}
         end)

  @ids Enum.map(@categories, &elem(&1, 0))

  @doc "All categories as maps, in display order."
  def categories do
    for {id, label, blurb} <- @categories do
      %{id: id, label: label, blurb: blurb, count: length(Map.fetch!(@bank, id))}
    end
  end

  def category_ids, do: @ids

  @doc "Safely turn user input (a string from the client) into a category id."
  def parse_category(value) when is_binary(value) do
    Enum.find(@ids, fn id -> Atom.to_string(id) == value end)
  end

  def parse_category(_), do: nil

  def label(id),
    do:
      Enum.find_value(@categories, fn
        {^id, label, _} -> label
        _ -> nil
      end)

  @doc "Every word in a category."
  def all(category) when category in @ids, do: Map.fetch!(@bank, category)

  @doc """
  A random word for `category`, sized for `difficulty`:
  easy 4-6 letters, normal 5-9, hard 8+. Words in `exclude` are skipped
  when possible so players don't see repeats.
  """
  def random(category, difficulty \\ :normal, exclude \\ []) when category in @ids do
    words = all(category)
    sized = Enum.filter(words, &fits?(&1, difficulty))
    pool = if sized == [], do: words, else: sized

    case pool -- exclude do
      [] -> Enum.random(pool)
      fresh -> Enum.random(fresh)
    end
  end

  defp fits?(word, difficulty) do
    n = word |> String.replace(~r/[^a-z]/, "") |> String.length()

    case difficulty do
      :easy -> n in 4..6
      :normal -> n in 5..9
      :hard -> n >= 8
    end
  end
end
