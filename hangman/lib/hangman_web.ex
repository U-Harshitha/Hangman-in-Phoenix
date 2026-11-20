defmodule HangmanWeb do
  @moduledoc """
  The entrypoint for defining the web interface.

  Everything public is served under `/hangman` (static files live in
  `priv/static/hangman`), so the app can sit behind a path-based rewrite
  on another domain without any URL rewriting.
  """

  def static_paths, do: ~w(hangman robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML
      import HangmanWeb.CoreComponents

      alias Phoenix.LiveView.JS
      alias HangmanWeb.Layouts

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: HangmanWeb.Endpoint,
        router: HangmanWeb.Router,
        statics: HangmanWeb.static_paths()
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
