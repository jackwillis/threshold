defmodule Threshold.Playable do
  @moduledoc """
  Status of the derived playable-location layer (`playable.json`, built by `threshold-gis playable`).
  The layer is generated from the imported geography, so it is stale if those inputs changed.
  """

  @inputs ~w(edges.geojson nodes.geojson context.geojson)

  @type status :: %{
          state: :fresh | :stale,
          diagnostics: map,
          params: map,
          ids: MapSet.t(String.t())
        }

  @doc "Returns `:missing` when no playable layer was built, else its diagnostics and freshness."
  @spec status(Path.t()) :: :missing | status
  def status(dir) do
    with {:ok, text} <- File.read(Path.join(dir, "playable.json")),
         {:ok, %{"inputs" => inputs, "diagnostics" => diagnostics} = doc} <- Jason.decode(text) do
      %{
        state: if(current_inputs(dir) == inputs, do: :fresh, else: :stale),
        diagnostics: diagnostics,
        params: doc["params"] || %{},
        ids: MapSet.new(doc["locations"] || [], & &1["id"])
      }
    else
      _ -> :missing
    end
  end

  defp current_inputs(dir) do
    Map.new(@inputs, fn name ->
      hash =
        case File.read(Path.join(dir, name)) do
          {:ok, bytes} -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
          _ -> nil
        end

      {name, hash}
    end)
  end
end
