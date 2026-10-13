defmodule Threshold.Readiness do
  @moduledoc "Read-only checks for the dependencies needed to serve the configured playable world."

  alias Threshold.Repo

  def check do
    with :ok <- database(), :ok <- schema(), :ok <- world(), do: :ok
  end

  defp database do
    if Application.get_env(:threshold, :database_enabled) do
      case query("SELECT 1") do
        {:ok, _} -> :ok
        _ -> {:error, "database_unavailable"}
      end
    else
      {:error, "database_unavailable"}
    end
  end

  defp schema do
    versions =
      Application.app_dir(:threshold, "priv/repo/migrations")
      |> Path.join("*.exs")
      |> Path.wildcard()
      |> Enum.map(fn path ->
        path |> Path.basename() |> String.split("_") |> hd() |> String.to_integer()
      end)

    with {:ok, %{rows: rows}} <- query("SELECT version FROM schema_migrations"),
         true <- Enum.all?(versions, &([&1] in rows)),
         {:ok, _} <-
           query(
             "SELECT id, world, player_key, world_revision, location, turn, visited, inserted_at, updated_at FROM player_progress LIMIT 0"
           ),
         {:ok, _} <-
           query(
             "SELECT id, progress_id, discovery_id, turn, source_interaction_id, inserted_at FROM player_discoveries LIMIT 0"
           ),
         {:ok, _} <-
           query(
             "SELECT id, progress_id, interaction_id, choice_id, turn, inserted_at FROM completed_interactions LIMIT 0"
           ) do
      :ok
    else
      _ -> {:error, "migrations_pending"}
    end
  end

  defp query(sql) do
    Ecto.Adapters.SQL.query(Repo, sql, [], timeout: 1_000, queue: false, log: false)
  rescue
    _ -> {:error, :unavailable}
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp world do
    name = Application.get_env(:threshold, :default_world, "madison")
    graph = Application.get_env(:threshold, :play_graph, "authored")
    graph = if graph in [:authored, "authored"], do: :authored, else: :generated

    with {:ok, _} <- Threshold.Game.World.load(name, graph: graph),
         {:ok, dir} <- Threshold.World.dir(name),
         {:ok, _, _} <- Threshold.Interactions.load(dir) do
      :ok
    else
      _ -> {:error, "world_unavailable"}
    end
  rescue
    _ -> {:error, "world_unavailable"}
  end
end
