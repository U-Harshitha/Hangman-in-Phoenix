defmodule HangmanWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :hangman

  @session_options [
    store: :cookie,
    key: "_hangman_key",
    signing_salt: "iAJlPZ1w",
    same_site: "Lax"
  ]

  # Long-polling matters here: Vercel rewrites don't proxy WebSockets, so
  # when the game is opened through the portfolio domain the client falls
  # back to HTTP long-polling automatically (see assets/js/app.js).
  socket "/hangman/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :hangman,
    gzip: not code_reloading?,
    only: HangmanWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug HangmanWeb.Router
end
