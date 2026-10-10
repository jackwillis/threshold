defmodule Threshold.Game.CompletedInteraction do
  @moduledoc "An interaction the local player has finished (once), with the choice made."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "completed_interactions" do
    field(:progress_id, :binary_id)
    field(:interaction_id, :string)
    field(:choice_id, :string)
    field(:turn, :integer)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
