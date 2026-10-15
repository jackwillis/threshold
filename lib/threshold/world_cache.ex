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

  @spec fetch(String.t(), atom, (-> {:ok, struct} | {:error, term})) ::
          {:ok, struct} | {:error, term}
  def fetch(name, graph, build) do
    case key(name, graph) do
      nil ->
        build.()

      key ->
        Threshold.BoundedCache.fetch(:worlds, key, fn ->
          build_and_store(name, graph, key, build)
        end)
    end
  end

  @doc "Forgets every cached world (tests, and anything that wants a cold start)."
  def clear, do: Threshold.BoundedCache.clear(:worlds)

  defp build_and_store(name, graph, key, build) do
    with {:ok, world} <- build.() do
      if key(name, graph) == key, do: {:ok, world}, else: {:uncached, world}
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
end
