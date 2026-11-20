defmodule HangmanWeb.HealthController do
  use HangmanWeb, :controller

  @doc "Used by the host's health check and the keep-warm workflow."
  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> text("ok")
  end

  def to_game(conn, _params), do: redirect(conn, to: ~p"/hangman")
end
