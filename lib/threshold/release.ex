defmodule Threshold.Release do
  @moduledoc """
  Database tasks that run without Mix or starting the web application.

      bin/threshold eval "Threshold.Release.migrate()"
  """

  @doc "Applies all pending migrations to the configured database."
  def migrate do
    Application.load(:threshold)

    for repo <- Application.fetch_env!(:threshold, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end
end
