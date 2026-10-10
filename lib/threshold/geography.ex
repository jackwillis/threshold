defmodule Threshold.Geography do
  @moduledoc """
  A compact index of the imported network (read from one generated snapshot directory), used to check that authored references still resolve.
  Parsing the full GeoJSON is slow, so the index is cached per file (path, size and mtime).
  """

  @type t :: %{
          nodes: %{String.t() => [float]},
          edges: %{String.t() => String.t()},
          lines: %{String.t() => [[float]]}
        }

  @spec index(Path.t()) :: {:ok, t} | :error
  def index(dir) do
    nodes_path = Path.join(dir, "nodes.geojson")
    edges_path = Path.join(dir, "edges.geojson")

    with {:ok, nodes_stat} <- File.stat(nodes_path, time: :posix),
         {:ok, edges_stat} <- File.stat(edges_path, time: :posix) do
      key =
        {__MODULE__, nodes_path, nodes_stat.size, nodes_stat.mtime, edges_stat.size,
         edges_stat.mtime}

      case :persistent_term.get(key, nil) do
        nil ->
          with {:ok, nodes} <- read_features(nodes_path),
               {:ok, edges} <- read_features(edges_path) do
            index = %{
              nodes: Map.new(nodes, &{&1["id"], &1["geometry"]["coordinates"]}),
              edges: Map.new(edges, &{&1["id"], &1["properties"]["geometry_hash"]}),
              lines: Map.new(edges, &{&1["id"], &1["geometry"]["coordinates"]})
            }

            drop_other_snapshots(nodes_path)
            :persistent_term.put(key, index)
            {:ok, index}
          end

        index ->
          {:ok, index}
      end
    else
      _ -> :error
    end
  end

  @doc """
  The position `offset` (0..1, a fraction of the edge's length) along an imported edge, computed
  from the edge geometry itself so that a stored anchor never depends on client coordinates.
  """
  @spec point_at(t, String.t(), number) :: {:ok, [float]} | :error
  def point_at(%{lines: lines}, ref, offset) when is_number(offset) do
    case lines do
      %{^ref => [_, _ | _] = line} when offset >= 0 and offset <= 1 ->
        {:ok, Threshold.Polyline.at(line, offset)}

      _ ->
        :error
    end
  end

  def point_at(_geography, _ref, _offset), do: :error

  @doc """
  The street closest to `point` within `max_m` metres, as an edge request ready for
  `Threshold.Authored.Edit.set_access/4`, or `:none`.
  """
  @spec nearest_street(t, [number], number) ::
          {:ok, %{request: map, distance_m: float}} | :none
  def nearest_street(%{lines: lines}, point, max_m) do
    lines
    |> Enum.filter(fn {_, line} -> match?([_, _ | _], line) end)
    |> Enum.map(fn {ref, line} ->
      {fraction, metres} = Threshold.Polyline.nearest(line, point)
      {metres, ref, fraction}
    end)
    |> Enum.min(fn -> nil end)
    |> case do
      {metres, ref, fraction} when metres <= max_m ->
        {:ok,
         %{
           request: %{"kind" => "edge", "ref" => ref, "offset" => Float.round(fraction, 6)},
           distance_m: Float.round(metres, 1)
         }}

      _ ->
        :none
    end
  end

  # Snapshots are immutable and replaced wholesale; keep only the newest index per world.
  defp drop_other_snapshots(nodes_path) do
    family = nodes_path |> Path.dirname() |> Path.dirname()

    for {{__MODULE__, path, _, _, _, _} = key, _} <- :persistent_term.get(),
        path != nodes_path and path |> Path.dirname() |> Path.dirname() == family do
      :persistent_term.erase(key)
    end

    :ok
  end

  @doc "Clears cached indexes after an explicit regeneration, including same-size writes."
  def invalidate(dir) do
    path = Path.join(dir, "nodes.geojson")

    for {{__MODULE__, ^path, _, _, _, _} = key, _} <- :persistent_term.get() do
      :persistent_term.erase(key)
    end

    :ok
  end

  defp read_features(path) do
    with {:ok, text} <- File.read(path),
         {:ok, %{"features" => features}} <- Jason.decode(text) do
      {:ok, features}
    else
      _ -> :error
    end
  end
end
