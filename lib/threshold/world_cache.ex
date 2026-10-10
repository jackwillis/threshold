defmodule Threshold.WorldCache do
  @moduledoc """
  Keeps the few most recently built movement worlds (`Threshold.Game.World`), so a LiveView event
  does not re-read, re-hash and re-resolve the whole map every time.

  An entry is immutable and keyed by everything the built world depends on:

    * the worlds directory, world name and graph mode (`:authored` or `:generated`);
    * the generated snapshot id, a content digest of all five generated files (published
      snapshots never change, so the large files need not be read or hashed again);
    * the SHA-256 of `authored.json` and of `boundary.geojson`.

  A changed authored file, boundary, regenerated snapshot or graph choice therefore addresses a
  different entry; nothing is invalidated by hand. Worlds are not cached when the geography is
  stale or missing, or when it is a plain `generated/` directory (the unversioned `"working"`
  snapshot, which could change in place). A build is stored only if its key is unchanged after
  the build, so inputs edited mid-build are never recorded under the old key.

  `Threshold.Game.World.revision`, which guards saved progress, is computed from the bytes by the
  builder exactly as before, so cached and uncached loads return identical worlds.
  """

  alias Threshold.Authored

  @keep 4
  @index {__MODULE__, :index}

  @spec fetch(String.t(), atom, (-> {:ok, struct} | {:error, term})) ::
          {:ok, struct} | {:error, term}
  def fetch(name, graph, build) do
    case key(name, graph) do
      nil ->
        build.()

      key ->
        case :persistent_term.get({__MODULE__, key}, nil) do
          nil -> build_and_store(name, graph, key, build)
          world -> {:ok, world}
        end
    end
  end

  @doc "Forgets every cached world (tests, and anything that wants a cold start)."
  def clear do
    for key <- :persistent_term.get(@index, []), do: :persistent_term.erase({__MODULE__, key})
    :persistent_term.put(@index, [])
    :ok
  end

  defp build_and_store(name, graph, key, build) do
    with {:ok, world} <- build.() do
      if key(name, graph) == key, do: remember(key, world)
      {:ok, world}
    end
  end

  defp key(name, graph) do
    with {:ok, world} <- Threshold.World.load(name),
         :fresh <- world.staleness,
         generation when is_binary(generation) and generation != "working" <- world.generation,
         {:ok, authored_text} <- File.read(Path.join(world.dir, "authored.json")) do
      {Threshold.World.root(), name, graph, generation, Authored.hash(authored_text),
       world.boundary_hash}
    else
      _ -> nil
    end
  end

  defp remember(key, world) do
    recent = [key | List.delete(:persistent_term.get(@index, []), key)]
    {keep, drop} = Enum.split(recent, @keep)
    :persistent_term.put({__MODULE__, key}, world)
    :persistent_term.put(@index, keep)
    for old <- drop, do: :persistent_term.erase({__MODULE__, old})
    :ok
  end
end
