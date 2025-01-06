defmodule HangmanWeb.GameHTML do
  use HangmanWeb, :html
  import HangmanWeb.Components.HangmanDrawing

  embed_templates "game_html/*"
end
