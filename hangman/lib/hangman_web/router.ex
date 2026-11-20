defmodule HangmanWeb.Router do
  use HangmanWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HangmanWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/hangman", HangmanWeb do
    get "/health", HealthController, :show

    pipe_through :browser
    live "/", GameLive, :index
  end

  # Visiting the bare host (e.g. the Render URL) lands on the game.
  get "/", HangmanWeb.HealthController, :to_game
end
