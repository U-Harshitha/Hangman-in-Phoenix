import Config

config :hangman, HangmanWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "sF+yVY8x/3jn5o+Cv73UKaIWhzCBF9i8CYwVdjFGa/n4RkiRS6gWZlR6VFeGR/Mj",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true
