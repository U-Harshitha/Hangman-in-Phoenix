import Config

if System.get_env("PHX_SERVER") do
  config :hangman, HangmanWeb.Endpoint, server: true
end

# Where the "← Portfolio" link in the header points.
config :hangman,
       :portfolio_url,
       System.get_env("PORTFOLIO_URL", "https://harshitha-upadhyayula.vercel.app")

if config_env() == :prod do
  # Phoenix needs a >= 64 byte secret. Hosting dashboards (e.g. Render's
  # `generateValue`) often hand out shorter random strings, so stretch
  # anything shorter with SHA-512 instead of crashing on boot.
  secret_key_base =
    case System.get_env("SECRET_KEY_BASE") do
      nil ->
        raise "environment variable SECRET_KEY_BASE is missing (generate one with: mix phx.gen.secret)"

      secret when byte_size(secret) < 64 ->
        :crypto.hash(:sha512, secret) |> Base.encode64()

      secret ->
        secret
    end

  host = System.get_env("PHX_HOST") || System.get_env("RENDER_EXTERNAL_HOSTNAME") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  # Extra origins allowed to open the LiveView socket, e.g. the Vercel
  # portfolio that proxies /hangman to this server. Comma separated:
  #   CHECK_ORIGINS=//harshitha-upadhyayula.vercel.app,//www.example.com
  extra_origins =
    System.get_env("CHECK_ORIGINS", "//harshitha-upadhyayula.vercel.app")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)

  config :hangman, HangmanWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: Enum.uniq(["//#{host}", "//localhost" | extra_origins]),
    # 0.0.0.0 is what Render (and most PaaS) expect; set BIND_IPV6=true for
    # hosts that route over IPv6 (e.g. Fly.io private networking).
    http: [
      ip:
        if(System.get_env("BIND_IPV6") == "true",
          do: {0, 0, 0, 0, 0, 0, 0, 0},
          else: {0, 0, 0, 0}
        ),
      port: port
    ],
    secret_key_base: secret_key_base
end
