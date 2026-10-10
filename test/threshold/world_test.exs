defmodule Threshold.WorldTest do
  use ExUnit.Case, async: true

  alias Threshold.World

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    # Copy the fixture so tests can edit it.
    File.cp_r!(Path.join(World.root(), "tiny"), Path.join(tmp, "tiny"))
    %{dir: Path.join(tmp, "tiny")}
  end

  test "loads the fixture world as fresh" do
    assert {:ok, %{name: "tiny", staleness: :fresh, provenance: %{"nodes" => 4}}} =
             World.load("tiny")
  end

  test "unknown or unsafe world names are not found" do
    assert {:error, :not_found} = World.load("nope")
    assert {:error, :not_found} = World.load("../etc")
    assert :error = World.dir("a/b")
  end

  test "only whitelisted layers have paths" do
    assert {:ok, _} = World.layer_path("tiny", "edges")
    assert :error = World.layer_path("tiny", "config")
    assert :error = World.layer_path("tiny", "../config")
  end

  test "missing provenance means geography has not been built", %{dir: dir} do
    File.rm!(Path.join([dir, "generated", "provenance.json"]))
    assert :missing = World.staleness(dir, %{}, %{}, nil)
  end

  test "changed boundary, config and source each make the geography stale", %{dir: dir} do
    {:ok, world} = World.load("tiny")
    %{config: config, boundary: boundary, provenance: prov} = world

    assert {:stale, [r1]} = World.staleness(dir, %{config | "buffer_m" => 500}, boundary, prov)
    assert r1 =~ "configuration"

    moved = put_in(boundary, ["geometry", "coordinates"], [[[0, 0], [1, 0], [1, 1], [0, 0]]])
    assert {:stale, [r2]} = World.staleness(dir, config, moved, prov)
    assert r2 =~ "Boundary"

    File.write!(Path.join(dir, "source/manifest.json"), ~s({"sha256": "different"}))
    assert {:stale, [r3]} = World.staleness(dir, config, boundary, prov)
    assert r3 =~ "snapshot"
  end
end
