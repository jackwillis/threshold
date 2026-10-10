defmodule Threshold.Game.Sessions do
  @moduledoc "Durable, atomic single-step walks for the single local player."
  import Ecto.Query
  alias Threshold.{Game, Repo}
  alias Threshold.Game.{CompletedInteraction, Discovery, Player, Progress, World}

  @migrate_note "the database needs the latest migration (run mix ecto.migrate)."

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
        # The upsert below keeps the row's id, so cascading deletes would not fire: a new walk
        # discards discoveries and completed interactions explicitly.
        clear_interaction_progress(world)

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

  # The interaction tables come from a later migration than the saves table. Until the designer
  # applies it to a database, a world with interactions reports that instead of failing.
  @doc false
  def interaction_tables? do
    match?(
      {:ok, %{rows: [[name]]}} when not is_nil(name),
      Repo.query("select to_regclass('player_discoveries')::text")
    )
  end

  defp clear_interaction_progress(world) do
    case interaction_tables?() && Repo.get_by(Progress, world: world.name, player_key: "local") do
      false ->
        :ok

      nil ->
        :ok

      %{id: id} ->
        Repo.delete_all(from(d in Discovery, where: d.progress_id == ^id))
        Repo.delete_all(from(c in CompletedInteraction, where: c.progress_id == ^id))
        :ok
    end
  end

  # --- Interactions -------------------------------------------------------------------

  @doc "The player's discoveries and completed interactions, for rendering. One read each; no lock."
  @spec interaction_state(%World{}) ::
          {:ok, %{discovered: MapSet.t(), completed: MapSet.t()}} | {:error, String.t()}
  def interaction_state(%World{} = world) do
    if interaction_tables?(), do: read_interaction_state(world), else: {:error, @migrate_note}
  end

  defp read_interaction_state(world) do
    case Repo.get_by(Progress, world: world.name, player_key: "local") do
      nil ->
        {:ok, %{discovered: MapSet.new(), completed: MapSet.new()}}

      %{id: id} ->
        {:ok,
         %{
           discovered: id |> discoveries() |> MapSet.new(),
           completed:
             MapSet.new(
               Repo.all(
                 from(c in CompletedInteraction,
                   where: c.progress_id == ^id,
                   select: c.interaction_id
                 )
               )
             )
         }}
    end
  end

  defp discoveries(progress_id),
    do:
      Repo.all(from(d in Discovery, where: d.progress_id == ^progress_id, select: d.discovery_id))

  @doc """
  Completes an interaction with one of its choices: the only write interactions make. One
  transaction under the same row lock as `move/3`. It checks, with nothing written on failure: the
  world revision and saved location (`restore/2`), the expected turn, that the interaction exists and
  the player is at its place now, that every required discovery is already recorded (read inside the
  lock, so it cannot be forged by sending a request for a hidden interaction), that it is not already
  completed, and that the choice belongs to it. Completion spends no turn.
  """
  @spec complete_interaction(%World{}, map, integer, String.t(), String.t()) ::
          {:ok, %{completed: %CompletedInteraction{}, discovered: [String.t()]}}
          | {:error,
             :stale_turn
             | :unavailable
             | :already_completed
             | :unknown_choice
             | :missing_save
             | String.t()}
  def complete_interaction(%World{} = world, content, expected_turn, interaction_id, choice_id) do
    Repo.transaction(fn ->
      progress =
        Repo.one(
          from(p in Progress,
            where: p.world == ^world.name and p.player_key == "local",
            lock: "FOR UPDATE"
          )
        )

      with {:progress, %Progress{}} <- {:progress, progress},
           {:ok, %Player{turn: ^expected_turn} = player} <-
             restore_or_stale(world, progress, expected_turn),
           {:ok, interaction} <- find_interaction(content, interaction_id),
           have = MapSet.new(discoveries(progress.id)),
           :ok <- available(world, player, interaction, have),
           :ok <- not_completed(progress.id, interaction_id),
           {:ok, choice} <- find_choice(interaction, choice_id) do
        record(progress, player, interaction, choice, have)
      else
        {:progress, nil} -> Repo.rollback(:missing_save)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp restore_or_stale(world, progress, expected_turn) do
    case restore(world, progress) do
      {:ok, %Player{turn: ^expected_turn}} = ok -> ok
      {:ok, _player} -> {:error, :stale_turn}
      {:error, _} = error -> error
    end
  end

  defp find_interaction(content, id) do
    case Enum.find(content["interactions"], &(&1["id"] == id)) do
      nil -> {:error, :unavailable}
      interaction -> {:ok, interaction}
    end
  end

  defp available(world, player, interaction, have) do
    if Game.at_place?(world, player, interaction["place"]) and
         Enum.all?(interaction["requires"], &MapSet.member?(have, &1)),
       do: :ok,
       else: {:error, :unavailable}
  end

  defp not_completed(progress_id, interaction_id) do
    if Repo.exists?(
         from(c in CompletedInteraction,
           where: c.progress_id == ^progress_id and c.interaction_id == ^interaction_id
         )
       ),
       do: {:error, :already_completed},
       else: :ok
  end

  defp find_choice(interaction, id) do
    case Enum.find(interaction["choices"], &(&1["id"] == id)) do
      nil -> {:error, :unknown_choice}
      choice -> {:ok, choice}
    end
  end

  defp record(progress, player, interaction, choice, have) do
    now = DateTime.utc_now()
    fresh = Enum.reject(Enum.uniq(choice["discovers"]), &MapSet.member?(have, &1))

    rows =
      for id <- fresh,
          do: %{
            id: Ecto.UUID.generate(),
            progress_id: progress.id,
            discovery_id: id,
            turn: player.turn,
            source_interaction_id: interaction["id"],
            inserted_at: now
          }

    Repo.insert_all(Discovery, rows,
      on_conflict: :nothing,
      conflict_target: [:progress_id, :discovery_id]
    )

    completed =
      Repo.insert!(%CompletedInteraction{
        progress_id: progress.id,
        interaction_id: interaction["id"],
        choice_id: choice["id"],
        turn: player.turn
      })

    %{completed: completed, discovered: fresh}
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
