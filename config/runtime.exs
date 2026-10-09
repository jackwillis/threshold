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

config :threshold, ThresholdWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

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

# Threshold is a local, single-user tool. A prod-mode run binds to loopback only.
# Public hosting would need a deliberate review of this block (TLS, host, exposure).
if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "environment variable SECRET_KEY_BASE is missing (generate with: mix phx.gen.secret)"

  config :threshold, ThresholdWeb.Endpoint,
    url: [
      host: "localhost",
      port: String.to_integer(System.get_env("PORT", "4000")),
      scheme: "http"
    ],
    http: [ip: {127, 0, 0, 1}],
    secret_key_base: secret_key_base
end
