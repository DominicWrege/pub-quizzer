# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :pub_quizzer,
  ecto_repos: [PubQuizzer.Repo],
  generators: [timestamp_type: :utc_datetime],
  # Etag-served files (non-vsn requests, e.g. uploads) revalidate on every
  # request — only fingerprinted (?vsn=...) assets may be cached for a year.
  cache_control_for_etags: "public",
  cache_control_for_vsn_requests: "public, max-age=31536000, immutable"

# SQLite tuning, applied in every environment. WAL lets any number of readers
# proceed without blocking the single writer, and a generous busy_timeout makes
# concurrent writers wait for the write lock instead of raising "database is
# locked" (SQLITE_BUSY). Set explicitly so we don't depend on library defaults.
config :pub_quizzer, PubQuizzer.Repo,
  journal_mode: :wal,
  synchronous: :normal,
  busy_timeout: 15_000,
  foreign_keys: :on

config :pub_quizzer, PubQuizzer.Mailer, adapter: Swoosh.Adapters.Local

config :pub_quizzer, :mailer, from_email: System.get_env("MAIL_FROM", "noreply@localhost")

config :swoosh, :api_client, Swoosh.ApiClient.Req

# Configure the endpoint
config :pub_quizzer, PubQuizzerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PubQuizzerWeb.ErrorHTML, json: PubQuizzerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PubQuizzer.PubSub,
  live_view: [signing_salt: "GSiIWsaB"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  pub_quizzer: [
    args:
      ~w(js/app.ts --bundle --minify --target=es2017 --outdir=../priv/static/assets/js --entry-names=app),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.13",
  pub_quizzer: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../", __DIR__)
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
