defmodule Hangman.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Hangman.PubSub},
      HangmanWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Hangman.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    HangmanWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
