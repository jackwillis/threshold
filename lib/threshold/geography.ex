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
      %{^ref => [[_, lat0] | _] = line} when offset >= 0 and offset <= 1 ->
        scale = :math.cos(lat0 * :math.pi() / 180)
        segments = Enum.zip(line, tl(line))

        lengths =
          for {[x1, y1], [x2, y2]} <- segments,
              do: :math.sqrt(:math.pow((x2 - x1) * scale, 2) + :math.pow(y2 - y1, 2))

        {:ok, along(segments, lengths, offset * Enum.sum(lengths))}

      _ ->
        :error
    end
  end

  def point_at(_geography, _ref, _offset), do: :error

  defp along([{from, to} | rest], [length | lengths], target) do
    if target <= length or rest == [] do
      interpolate(from, to, if(length == 0, do: 0.0, else: min(target / length, 1.0)))
    else
      along(rest, lengths, target - length)
    end
  end

  defp interpolate([x1, y1], [x2, y2], t),
    do: [Float.round(x1 + (x2 - x1) * t, 7), Float.round(y1 + (y2 - y1) * t, 7)]

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
