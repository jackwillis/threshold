defmodule Threshold.Geography do
  @moduledoc """
  A compact index of the imported network, used to check that authored references still resolve.
  Parsing the full GeoJSON is slow, so the index is cached per file (path, size and mtime).
  """

  @type t :: %{nodes: %{String.t() => [float]}, edges: %{String.t() => String.t()}}

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
              edges: Map.new(edges, &{&1["id"], &1["properties"]["geometry_hash"]})
            }

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

  defp read_features(path) do
    with {:ok, text} <- File.read(path),
         {:ok, %{"features" => features}} <- Jason.decode(text) do
      {:ok, features}
    else
      _ -> :error
    end
  end
end
