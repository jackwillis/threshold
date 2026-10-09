defmodule Threshold.Game.Progress do
  @moduledoc "The local player's durable progress. Geography remains in world files."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "player_progress" do
    field(:world, :string)
    field(:player_key, :string, default: "local")
    field(:world_revision, :string)
    field(:location, :string)
    field(:turn, :integer, default: 0)
    field(:visited, {:array, :string}, default: [])
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(progress, attrs) do
    progress
    |> cast(attrs, [:world, :player_key, :world_revision, :location, :turn, :visited])
    |> validate_required([:world, :player_key, :world_revision, :location, :turn, :visited])
    |> validate_number(:turn, greater_than_or_equal_to: 0)
    |> unique_constraint([:world, :player_key])
  end
end
