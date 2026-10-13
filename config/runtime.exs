import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/threshold start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
# Point the app at another directory of worlds (e.g. a scratch copy for experiments).
if worlds_dir = System.get_env("THRESHOLD_WORLDS_DIR") do
  config :threshold, :worlds_dir, Path.expand(worlds_dir)
end

if System.get_env("PHX_SERVER") do
  config :threshold, ThresholdWeb.Endpoint, server: true
end

if config_env() != :prod do
  config :threshold, ThresholdWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))]
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :threshold, ThresholdWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/threshold_web/router\.ex$"E,
        ~r"lib/threshold_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

# Release settings are runtime-only: a build does not need credentials.
if config_env() == :prod do
  required = ~w(SECRET_KEY_BASE THRESHOLD_DATABASE_URL)
  missing = Enum.filter(required, &(System.get_env(&1) in [nil, ""]))

  if missing != [] do
    raise "Missing required production environment variables: #{Enum.join(missing, ", ")}"
  end

  positive_integer = fn name, default ->
    case Integer.parse(System.get_env(name, default)) do
      {value, ""} when value > 0 -> value
      _ -> raise "#{name} must be a positive integer"
    end
  end

  port = positive_integer.("PORT", "4000")
  if port > 65_535, do: raise("PORT must be between 1 and 65535")

  bind_address = System.get_env("PHX_BIND_ADDRESS", "127.0.0.1")

  ip =
    case :inet.parse_address(String.to_charlist(bind_address)) do
      {:ok, address} -> address
      {:error, _} -> raise "PHX_BIND_ADDRESS must be an IPv4 or IPv6 address"
    end

  server =
    case System.get_env("PHX_SERVER", "false") do
      value when value in ["true", "1"] -> true
      value when value in ["false", "0"] -> false
      _ -> raise "PHX_SERVER must be true, false, 1 or 0"
    end

  config :threshold, ThresholdWeb.Endpoint,
    url: [host: System.get_env("PHX_HOST", "localhost"), port: port, scheme: "http"],
    http: [ip: ip, port: port],
    server: server,
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")

  config :threshold, :database_enabled, true

  config :threshold, Threshold.Repo,
    url: System.fetch_env!("THRESHOLD_DATABASE_URL"),
    pool_size: positive_integer.("POOL_SIZE", "5")
end

# Gameplay persistence is optional for the editor. Tests never use the development URL.
database_url =
  System.get_env(
    if config_env() == :test, do: "THRESHOLD_TEST_DATABASE_URL", else: "THRESHOLD_DATABASE_URL"
  )

if database_url && config_env() != :prod do
  # Accepted test databases: `threshold_test`, a name ending `_test`, or a per-session scratch
  # name `threshold_test_<suffix>`. The development database (`threshold_game`) never matches.
  if config_env() == :test and
       not String.match?(
         URI.parse(database_url).path || "",
         ~r{^/(threshold_test(_[a-z0-9_]+)?|[a-z0-9_]*_test)$}
       ) do
    raise "THRESHOLD_TEST_DATABASE_URL must name a dedicated test database: threshold_test, " <>
            "threshold_test_<suffix> or a name ending _test"
  end

  config :threshold, :database_enabled, true
  config :threshold, Threshold.Repo, url: database_url, pool_size: 5

  if config_env() == :test do
    config :threshold, Threshold.Repo, pool: Ecto.Adapters.SQL.Sandbox
  end
end
