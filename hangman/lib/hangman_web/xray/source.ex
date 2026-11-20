defmodule HangmanWeb.Xray.Source do
  @moduledoc """
  Compile-time helpers that pull *real* source code out of this project
  for X-ray mode, so the code on screen is always the code that's running.

    * `function/3` parses an Elixir file and slices out every clause of a
      named function using the AST's line metadata.
    * `marked/2` slices the text between `xray:<name>` and `xray:end`
      marker comments (used for JavaScript and config).
    * `highlight/1` is a tiny syntax highlighter that returns safe HTML.
  """

  @root Path.expand("../../..", __DIR__)

  def path(relative), do: Path.join(@root, relative)

  @doc "All clauses of `name` (a def or defp) in `relative` file, as text."
  def function(relative, name, opts \\ []) do
    source = File.read!(path(relative))
    lines = String.split(source, "\n")

    {:ok, ast} =
      Code.string_to_quoted(source, token_metadata: true, columns: true, file: relative)

    {_, ranges} =
      Macro.prewalk(ast, [], fn
        {kind, meta, [head | _]} = node, acc when kind in [:def, :defp] ->
          if fun_name(head) == name do
            # do/end clauses carry an :end line; one-liners (`do:`) don't.
            last = get_in(meta, [:end, :line]) || max_line(node)
            {node, [{meta[:line], last} | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    case Enum.sort(ranges) do
      [] ->
        raise ArgumentError, "xray: no function #{name} in #{relative}"

      ranges ->
        {first, _} = List.first(ranges)
        {_, last} = List.last(ranges)
        first = first - doc_lines(lines, first, Keyword.get(opts, :with_doc, false))

        lines
        |> Enum.slice((first - 1)..(last - 1))
        |> dedent()
    end
  end

  @doc "Text between `xray:<name>` and `xray:end` markers in `relative`."
  def marked(relative, name) do
    lines = relative |> path() |> File.read!() |> String.split("\n")

    start =
      Enum.find_index(lines, &String.contains?(&1, "xray:#{name}")) ||
        raise ArgumentError, "xray: no marker #{name} in #{relative}"

    stop =
      lines
      |> Enum.drop(start + 1)
      |> Enum.find_index(&String.contains?(&1, "xray:end"))

    lines |> Enum.slice((start + 1)..(start + stop)) |> dedent()
  end

  defp max_line(node) do
    {_, max} =
      Macro.prewalk(node, 0, fn
        {_, meta, _} = n, acc when is_list(meta) -> {n, max(acc, meta[:line] || 0)}
        n, acc -> {n, acc}
      end)

    max
  end

  defp fun_name({:when, _, [head | _]}), do: fun_name(head)
  defp fun_name({name, _, _}) when is_atom(name), do: name
  defp fun_name(_), do: nil

  # Include the @doc/@spec lines right above a function when asked.
  defp doc_lines(_lines, _first, false), do: 0

  defp doc_lines(lines, first, true) do
    lines
    |> Enum.take(first - 1)
    |> Enum.reverse()
    |> Enum.take_while(&(String.trim(&1) =~ ~r/^(@spec|@doc ")/))
    |> length()
  end

  defp dedent(lines) do
    indent =
      lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(fn l -> String.length(l) - String.length(String.trim_leading(l)) end)
      |> Enum.min(fn -> 0 end)

    lines
    |> Enum.map(&String.slice(&1, indent..-1//1))
    |> Enum.join("\n")
    |> String.trim_trailing()
  end

  @token ~r/(?<comment>#(?!\{)[^\n]*|\/\/[^\n]*)|(?<string>"(?:\\.|[^"\\])*"|`(?:\\.|[^`\\])*`)|(?<atom>:[a-z_][a-zA-Z0-9_?!]*|\b[a-z_][a-zA-Z0-9_]*:(?=\s))|(?<kw>\b(?:defp|def|defmodule|do|end|fn|case|cond|when|if|else|with|import|alias|use|const|let|return|switch|new|true|false|nil|for|of|in)\b)|(?<mod>\b[A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*)|(?<num>\b\d+(?:\.\d+)?\b)/

  @classes ~w(c s a k m n)

  @doc "Escape + highlight code. Returns an HTML-safe string."
  def highlight(code) do
    matches = Regex.scan(@token, code, return: :index)

    {html, pos} =
      Enum.reduce(matches, {[], 0}, fn [{start, len} | groups], {acc, pos} ->
        class =
          groups
          |> Enum.zip(@classes)
          |> Enum.find_value(fn {{s, _}, class} -> if s >= 0, do: class end)

        plain = binary_part(code, pos, start - pos)
        token = binary_part(code, start, len)

        {[acc, escape(plain), ~s(<span class="t-#{class}">), escape(token), "</span>"],
         start + len}
      end)

    IO.iodata_to_binary([html, escape(binary_part(code, pos, byte_size(code) - pos))])
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
