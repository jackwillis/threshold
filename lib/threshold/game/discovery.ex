defmodule Threshold.Game.Discovery do
  @moduledoc "A discovery the local player has made, scoped to one durable session."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "player_discoveries" do
    field(:progress_id, :binary_id)
    field(:discovery_id, :string)
    field(:turn, :integer)
    field(:source_interaction_id, :string)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
