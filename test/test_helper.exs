if Threshold.Game.Sessions.enabled?() do
  Ecto.Migrator.run(Threshold.Repo, Path.expand("../priv/repo/migrations", __DIR__), :up,
    all: true
  )

  Ecto.Adapters.SQL.Sandbox.mode(Threshold.Repo, :manual)
  ExUnit.start()
else
  ExUnit.start(exclude: [:database])
end
