import Config

# The whole app lives under /hangman so it can be proxied 1:1 from
# https://harshitha-upadhyayula.vercel.app/hangman (see README).
config :hangman, HangmanWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HangmanWeb.ErrorHTML, json: HangmanWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Hangman.PubSub,
  live_view: [signing_salt: "vcGbosUo"]

config :esbuild,
  version: "0.25.4",
  hangman: [
    args:
      ~w(js/app.js --bundle --format=esm --splitting --target=es2022 --outdir=../priv/static/hangman/assets/js --chunk-names=chunks/[name]-[hash] --external:/hangman/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.1.12",
  hangman: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/hangman/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
