defmodule Threshold.GeneratedTest do
  use ExUnit.Case, async: true

  alias Threshold.Generated

  @moduletag :tmp_dir

  # A source directory whose five files all carry `marker`, so a reader can tell generations apart.
  defp build(dir, name, marker) do
    source = Path.join(dir, name)
    File.mkdir_p!(source)
    for file <- Generated.files(), do: File.write!(Path.join(source, file), marker)
    source
  end

  defp read_all(snapshot_dir),
    do: Enum.map(Generated.files(), &File.read!(Path.join(snapshot_dir, &1)))

  setup %{tmp_dir: tmp} do
    world = Path.join(tmp, "world")
    File.mkdir_p!(world)
    %{world: world, tmp: tmp}
  end

  test "publishes a snapshot behind an atomic symlink and converts a plain directory", %{
    world: world,
    tmp: tmp
  } do
    plain = build(world, "generated", "plain")
    assert {:ok, %{dir: ^plain, generation: "working"}} = Generated.active(world)

    assert {:ok, id} = Generated.publish(world, build(tmp, "one", "one"))
    assert {:ok, %{dir: dir, generation: ^id}} = Generated.active(world)
    assert {:ok, _} = File.read_link(Path.join(world, "generated"))
    assert read_all(dir) == List.duplicate("one", 5)

    # The plain directory was kept as a snapshot rather than discarded.
    assert Path.wildcard(Path.join([world, "generations", "*"])) |> length() == 2
    assert Generated.snapshot(world, "nope") == :error
    assert Generated.snapshot(world, "../../x") == :error
    assert {:ok, %{generation: ^id}} = Generated.snapshot(world, id)
  end

  test "republishing identical content keeps the same generation", %{world: world, tmp: tmp} do
    {:ok, id} = Generated.publish(world, build(tmp, "a", "same"))
    assert {:ok, ^id} = Generated.publish(world, build(tmp, "b", "same"))
    assert length(Path.wildcard(Path.join([world, "generations", "*"]))) == 1
  end

  test "a failed publication leaves the active snapshot untouched", %{world: world, tmp: tmp} do
    {:ok, id} = Generated.publish(world, build(tmp, "good", "good"))
    broken = build(tmp, "broken", "broken")
    File.rm!(Path.join(broken, "playable.json"))

    assert {:error, "Cannot publish: missing generated playable.json."} =
             Generated.publish(world, broken)

    assert {:ok, %{dir: dir, generation: ^id}} = Generated.active(world)
    assert read_all(dir) == List.duplicate("good", 5)
    assert Path.wildcard(Path.join(world, ".generated-*")) == []
    assert Path.wildcard(Path.join([world, "generations", ".staging-*"])) == []
  end

  test "keeps the active snapshot and the two most recent others", %{world: world, tmp: tmp} do
    ids = for n <- 1..5, do: elem(Generated.publish(world, build(tmp, "b#{n}", "m#{n}")), 1)

    remaining =
      Path.wildcard(Path.join([world, "generations", "*"])) |> Enum.map(&Path.basename/1)

    assert length(remaining) == 3
    assert List.last(ids) in remaining
  end

  test "readers never observe a mix of generations while publications race", %{
    world: world,
    tmp: tmp
  } do
    {:ok, _} = Generated.publish(world, build(tmp, "seed", "seed"))
    sources = for n <- 1..40, do: build(tmp, "g#{n}", "gen-#{n}")

    readers =
      for _ <- 1..4 do
        Task.async(fn ->
          Stream.repeatedly(fn ->
            {:ok, %{dir: dir}} = Generated.active(world)
            # Snapshots may be pruned after being superseded; only a complete read is checked.
            try do
              read_all(dir) |> Enum.uniq() |> length()
            rescue
              File.Error -> 1
            end
          end)
          |> Enum.take(1500)
          |> Enum.max()
        end)
      end

    for source <- sources, do: {:ok, _} = Generated.publish(world, source)
    assert Task.await_many(readers, 60_000) == [1, 1, 1, 1]
  end
end
