# CI must exercise the PostgreSQL-backed tests; never let them be skipped silently there.
if System.get_env("CI") == "true" and not Threshold.Game.Sessions.enabled?() do
  raise "CI requires THRESHOLD_TEST_DATABASE_URL so database tests are not skipped"
end

if Threshold.Game.Sessions.enabled?() do
  Ecto.Migrator.run(Threshold.Repo, Path.expand("../priv/repo/migrations", __DIR__), :up,
    all: true
  )

  Ecto.Adapters.SQL.Sandbox.mode(Threshold.Repo, :manual)
  ExUnit.start()
else
  ExUnit.start(exclude: [:database])
end
