defmodule HangmanWeb.XrayTest do
  use ExUnit.Case, async: true

  alias HangmanWeb.Xray
  alias HangmanWeb.Xray.Source

  test "every section carries real, highlighted code" do
    for section <- Xray.sections() do
      assert section.code =~ ~r/\S/, "#{section.id} has no code"
      assert File.exists?(Source.path(section.file))
      assert section.html =~ "<span class=\"t-"
    end
  end

  test "function extraction returns every clause of a function" do
    code = Source.function("lib/hangman/game.ex", :guess)
    assert code =~ "def guess(%__MODULE__{status: status} = game, _letter)"
    assert code =~ "def guess(game, _letter), do: {:invalid, game}"
    refute code =~ "def hint"
  end

  test "highlighting escapes HTML" do
    html = Source.highlight(~s(x = "<script>" # <b>))
    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
  end

  test "runtime facts describe the current process" do
    facts = Xray.runtime()
    assert facts.pid == inspect(self())
    assert facts.processes > 0
  end

  test "the supervision chain runs from the BEAM down to the caller" do
    chain = Xray.chain(self())
    assert hd(chain).name == "the BEAM"
    assert List.last(chain).name =~ inspect(self())
  end

  test "line counts are taken at compile time" do
    assert Xray.loc().elixir > 500
    assert Xray.loc().js > 100
  end
end
