defmodule Threshold.References do
  @moduledoc """
  Resolves authored references against the imported geography and reports a status for each.

    * `:ok` - the target exists and still matches what was recorded
    * `:moved` - the target exists but its position or shape differs; needs review
    * `:missing` - the target is gone; the authored object stays, drawn detached

  Nothing here rewrites authored data. Reconnecting is an explicit editor action.
  """

  # About 2 m. Node coordinates are stored to 7 decimals, so smaller differences are noise.
  @node_tolerance_deg 0.00002

  @type status :: :ok | :moved | :missing
  @type ref :: %{object: String.t(), field: String.t(), ref: String.t(), status: status}

  @doc "All geography references in an authored document, with their statuses."
  @spec resolve(Threshold.Authored.t(), Threshold.Geography.t()) :: [ref]
  def resolve(authored, geography) do
    locations =
      for %{"id" => id, "anchor" => anchor} <- authored["locations"],
          anchor["kind"] in ["node", "edge"] do
        %{
          object: id,
          field: "anchor",
          ref: anchor["ref"],
          status: anchor_status(anchor, geography)
        }
      end

    closures =
      for %{"id" => id, "edge" => edge, "geometry_hash" => hash} <- authored["closures"] do
        %{object: id, field: "edge", ref: edge, status: edge_status(edge, hash, geography)}
      end

    locations ++ closures
  end

  @doc "References that need attention (not `:ok`)."
  def needing_review(refs), do: Enum.reject(refs, &(&1.status == :ok))

  defp anchor_status(%{"kind" => "node", "ref" => ref, "point" => [lon, lat]}, geography) do
    case geography.nodes[ref] do
      nil ->
        :missing

      [nlon, nlat] ->
        if abs(nlon - lon) <= @node_tolerance_deg and abs(nlat - lat) <= @node_tolerance_deg,
          do: :ok,
          else: :moved
    end
  end

  defp anchor_status(%{"kind" => "edge", "ref" => ref, "ref_geometry_hash" => hash}, geography),
    do: edge_status(ref, hash, geography)

  defp edge_status(ref, hash, geography) do
    case Map.fetch(geography.edges, ref) do
      :error -> :missing
      {:ok, ^hash} -> :ok
      {:ok, _other} -> :moved
    end
  end
end
