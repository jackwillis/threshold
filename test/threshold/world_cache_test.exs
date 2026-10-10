defmodule Threshold.WorldCacheTest do
  use ExUnit.Case, async: false

  alias Threshold.{Authored, Generated, WorldCache}
  alias Threshold.Game.World

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    File.cp_r!(Path.join(Threshold.World.root(), "tiny"), Path.join(tmp, "tiny"))
    previous = Application.get_env(:threshold, :worlds_dir)
    Application.put_env(:threshold, :worlds_dir, tmp)
    on_exit(fn -> Application.put_env(:threshold, :worlds_dir, previous) end)
    WorldCache.clear()
    on_exit(&WorldCache.clear/0)

    dir = Path.join(tmp, "tiny")
    # Published snapshots are content-addressed and cacheable; a plain directory is not.
    {:ok, _} = Generated.publish(dir, Path.join(dir, "generated"))
    write_authored(dir, "The corner")
    %{dir: dir}
  end

  defp write_authored(dir, name) do
    node = fn ref, point -> %{"kind" => "node", "ref" => ref, "point" => point} end

    doc =
      Map.merge(Authored.empty(), %{
        "spawns" => [%{"id" => "spawn:default", "location" => "pn:1", "default" => true}],
        "locations" => [
          %{"id" => "loc:a", "name" => name, "anchor" => node.("node:1", [-89.385, 43.074])},
          %{"id" => "loc:b", "name" => "B", "anchor" => node.("node:2", [-89.38, 43.075])}
        ],
        "connections" => [
          %{"id" => "conn:ab", "from" => "loc:a", "to" => "loc:b", "kind" => "fictional"}
        ]
      })

    File.write!(Path.join(dir, "authored.json"), Authored.encode(doc))
  end

  defp load(graph \\ :authored), do: World.load("tiny", graph: graph)

  test "an unchanged world is built once and then shared", %{} do
    assert {:ok, first} = load()
    assert {:ok, second} = load()
    assert first == second
    # The cached copy is the very same term, not a rebuild.
    key = {Threshold.WorldCache, hd(:persistent_term.get({Threshold.WorldCache, :index}))}
    assert :persistent_term.get(key) == first
  end

  test "the cached world equals an uncached build, revision included", %{dir: dir} do
    {:ok, cached} = load()
    WorldCache.clear()
    File.touch!(Path.join(dir, "authored.json"))
    assert {:ok, ^cached} = load()
  end

  test "editing authored.json produces a new world", %{dir: dir} do
    {:ok, before} = load()
    write_authored(dir, "Renamed")
    {:ok, after_edit} = load()

    assert after_edit.revision != before.revision
    assert after_edit.places == before.places or after_edit.locations != before.locations
    assert after_edit.locations["loc:a"]["name"] == "Renamed"
    assert before.locations["loc:a"]["name"] == "The corner"

    write_authored(dir, "The corner")
    {:ok, reverted} = load()
    assert reverted == before
  end

  test "changing the playable boundary is never answered from the cache", %{dir: dir} do
    assert {:ok, _} = load()
    path = Path.join(dir, "boundary.geojson")

    shifted =
      path
      |> File.read!()
      |> Jason.decode!()
      |> update_in(["geometry", "coordinates", Access.at(0), Access.at(1)], fn [x, y] ->
        [x - 0.001, y]
      end)

    File.write!(path, Jason.encode!(shifted))
    # The geography no longer matches the boundary, so the old world must not be served.
    assert {:error, _} = load()
  end

  test "a regenerated snapshot is a different entry", %{dir: dir} do
    {:ok, before} = load()
    scratch = Path.join(dir, "scratch")
    File.cp_r!(Path.join(dir, "generated"), scratch)
    path = Path.join(scratch, "playable.json")
    File.write!(path, File.read!(path) <> "\n")
    {:ok, id} = Generated.publish(dir, scratch)

    {:ok, after_publish} = load()
    assert after_publish.generation == id
    assert after_publish.generation != before.generation
  end

  test "graph modes are separate entries" do
    {:ok, authored} = load(:authored)
    assert authored.graph == :authored

    case load(:generated) do
      {:ok, generated} -> assert generated.graph == :generated
      {:error, _} -> :ok
    end

    assert {:ok, ^authored} = load(:authored)
  end

  test "a plain generated directory is not cached", %{dir: dir} do
    File.rm!(Path.join(dir, "generated"))

    File.cp_r!(
      Path.join(dir, "generations") |> Path.join(hd(File.ls!(Path.join(dir, "generations")))),
      Path.join(dir, "generated")
    )

    WorldCache.clear()
    assert {:ok, %{generation: "working"}} = load()
    assert :persistent_term.get({Threshold.WorldCache, :index}, []) == []
  end

  test "only the most recent worlds are kept", %{dir: dir} do
    for n <- 1..6 do
      write_authored(dir, "Name #{n}")
      assert {:ok, _} = load()
    end

    assert length(:persistent_term.get({Threshold.WorldCache, :index})) == 4
  end
end
