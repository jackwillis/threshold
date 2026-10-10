defmodule Threshold.Repo.Migrations.CreateInteractionProgress do
  use Ecto.Migration

  # Discoveries and completed interactions belong to one durable session (a player_progress row).
  # Ids are plain text, not foreign keys into interactions.json, so editing content never breaks
  # saved rows. The unique indexes make a replayed completion harmless even without app checks.
  def change do
    create table(:player_discoveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :progress_id, references(:player_progress, type: :binary_id, on_delete: :delete_all), null: false
      add :discovery_id, :text, null: false
      add :turn, :bigint, null: false
      add :source_interaction_id, :text, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:player_discoveries, [:progress_id, :discovery_id])

    create table(:completed_interactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :progress_id, references(:player_progress, type: :binary_id, on_delete: :delete_all), null: false
      add :interaction_id, :text, null: false
      add :choice_id, :text, null: false
      add :turn, :bigint, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:completed_interactions, [:progress_id, :interaction_id])
  end
end
