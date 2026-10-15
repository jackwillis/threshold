defmodule Threshold.Traversal do
  @moduledoc """
  Shared street access policy for generated movement and authored routing.

  Boundary coverage is checked against geometry by each graph builder; pipeline edge flags
  are diagnostic metadata, not an authority for runtime movement.
  """
  @access ~w(public unknown conditional mixed)
  @vehicle_service ~w(driveway parking_aisle drive-through emergency_access)

  @spec walkable?(map(), MapSet.t()) :: :ok | {:blocked, :closure | :access}
  def walkable?(properties, closures) do
    cond do
      MapSet.member?(closures, properties["id"]) -> {:blocked, :closure}
      properties["access_status"] not in @access -> {:blocked, :access}
      properties["service"] in @vehicle_service -> {:blocked, :access}
      true -> :ok
    end
  end
end
