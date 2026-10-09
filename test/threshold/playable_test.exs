defmodule Threshold.PlayableTest do
  use ExUnit.Case, async: true

  alias Threshold.Playable

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    File.cp_r!(Path.join(Threshold.World.root(), "tiny"), Path.join(tmp, "tiny"))
    %{dir: Path.join(tmp, "tiny")}
  end

  test "reports diagnostics and location ids for a fresh layer", %{dir: dir} do
    assert %{state: :fresh, diagnostics: %{"locations" => 4}, ids: ids} = Playable.status(dir)
    assert MapSet.member?(ids, "pn:1")
  end

  test "is stale when an input changed after the layer was built", %{dir: dir} do
    File.write!(Path.join(dir, "edges.geojson"), ~s({"type":"FeatureCollection","features":[]}))
    assert %{state: :stale} = Playable.status(dir)
  end

  test "is missing when not built or unreadable", %{dir: dir} do
    File.rm!(Path.join(dir, "playable.json"))
    assert :missing = Playable.status(dir)
    File.write!(Path.join(dir, "playable.json"), "{broken")
    assert :missing = Playable.status(dir)
  end
end
