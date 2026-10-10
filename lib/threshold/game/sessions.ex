defmodule Threshold.Game.Sessions do
  @moduledoc "Durable, atomic single-step walks for the single local player."
  import Ecto.Query
  alias Threshold.{Game, Repo}
  alias Threshold.Game.{Player, Progress, World}

  def enabled?, do: Application.get_env(:threshold, :database_enabled, false)

  def load_or_start(%World{} = world) do
    if enabled?() do
      case Repo.get_by(Progress, world: world.name, player_key: "local") do
        nil -> start(world)
        progress -> restore(world, progress)
      end
    else
      {:error, "Configure THRESHOLD_DATABASE_URL and run mix ecto.migrate to save a walk."}
    end
  end

  def reset(%World{} = world) do
    with {:ok, player, _spawn} <- Game.start(world) do
      Repo.transaction(fn ->
        Repo.insert!(Progress.changeset(%Progress{}, attrs(world, player)),
          on_conflict: {:replace, [:world_revision, :location, :turn, :visited, :updated_at]},
          conflict_target: [:world, :player_key]
        )

        player
      end)
    end
  end

  def move(%World{} = world, expected_turn, destination) do
    Repo.transaction(fn ->
      progress =
        Repo.one(
          from(p in Progress,
            where: p.world == ^world.name and p.player_key == "local",
            lock: "FOR UPDATE"
          )
        )

      case progress && restore(world, progress) do
        {:ok, %Player{turn: ^expected_turn} = player} ->
          case Game.move(world, player, destination) do
            {:ok, moved, route} ->
              Repo.update!(Progress.changeset(progress, attrs(world, moved)))
              {moved, route}

            {:error, reason} ->
              Repo.rollback(reason)
          end

        {:ok, _player} ->
          Repo.rollback(:stale_turn)

        {:error, reason} ->
          Repo.rollback(reason)

        nil ->
          Repo.rollback(:missing_save)
      end
    end)
  end

  defp start(world) do
    with {:ok, player, _spawn} <- Game.start(world) do
      Repo.insert!(Progress.changeset(%Progress{}, attrs(world, player)),
        on_conflict: :nothing,
        conflict_target: [:world, :player_key]
      )

      restore(world, Repo.get_by!(Progress, world: world.name, player_key: "local"))
    end
  end

  defp restore(world, progress) do
    cond do
      progress.world_revision != world.revision ->
        {:error, "The authored world has changed. Start a new walk to use this revision."}

      not Map.has_key?(world.locations, progress.location) ->
        {:error, "The saved location is missing. Repair the world or start a new walk."}

      true ->
        {:ok,
         %Player{
           location: progress.location,
           turn: progress.turn,
           visited: MapSet.new(progress.visited)
         }}
    end
  end

  defp attrs(world, player) do
    %{
      world: world.name,
      player_key: "local",
      world_revision: world.revision,
      location: player.location,
      turn: player.turn,
      visited: Enum.sort(player.visited)
    }
  end
end
