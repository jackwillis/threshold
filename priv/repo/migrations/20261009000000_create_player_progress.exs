defmodule Threshold.Repo.Migrations.CreatePlayerProgress do
  use Ecto.Migration

  def change do
    create table(:player_progress, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :world, :text, null: false
      add :player_key, :text, null: false
      add :world_revision, :text, null: false
      add :location, :text, null: false
      add :turn, :bigint, null: false, default: 0
      add :visited, {:array, :text}, null: false, default: []
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:player_progress, [:world, :player_key])
    create constraint(:player_progress, :nonnegative_turn, check: "turn >= 0")
  end
end
