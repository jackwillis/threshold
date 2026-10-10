defmodule Threshold.PlayableTest do
  use ExUnit.Case, async: true

  alias Threshold.Playable

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    File.cp_r!(Path.join(Threshold.World.root(), "tiny"), Path.join(tmp, "tiny"))
    %{dir: Path.join(tmp, "tiny")}
  end

  test "reports diagnostics and location ids for a fresh layer", %{dir: dir} do
    assert %{state: :fresh, diagnostics: %{"locations" => 4}, ids: ids} =
             Playable.status(Path.join(dir, "generated"))

    assert MapSet.member?(ids, "pn:1")
  end

  test "is stale when an input changed after the layer was built", %{dir: dir} do
    File.write!(
      Path.join([dir, "generated", "edges.geojson"]),
      ~s({"type":"FeatureCollection","features":[]})
    )

    assert %{state: :stale} = Playable.status(Path.join(dir, "generated"))
  end

  test "is missing when not built or unreadable", %{dir: dir} do
    File.rm!(Path.join([dir, "generated", "playable.json"]))
    assert :missing = Playable.status(Path.join(dir, "generated"))
    File.write!(Path.join([dir, "generated", "playable.json"]), "{broken")
    assert :missing = Playable.status(Path.join(dir, "generated"))
  end
end
