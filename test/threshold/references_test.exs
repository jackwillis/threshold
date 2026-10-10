defmodule Threshold.ReferencesTest do
  use ExUnit.Case, async: true

  alias Threshold.{Geography, References}

  @geography %{
    nodes: %{"node:1" => [-89.385, 43.074]},
    edges: %{"edge:1-2-101" => "deadbeef"}
  }

  defp authored(locations, closures \\ []) do
    %{"locations" => locations, "connections" => [], "closures" => closures}
  end

  defp node_loc(ref, point),
    do: %{
      "id" => "loc:n",
      "name" => "n",
      "anchor" => %{"kind" => "node", "ref" => ref, "point" => point}
    }

  defp edge_loc(ref, hash),
    do: %{
      "id" => "loc:e",
      "name" => "e",
      "anchor" => %{
        "kind" => "edge",
        "ref" => ref,
        "offset" => 0.5,
        "point" => [0, 0],
        "ref_geometry_hash" => hash
      }
    }

  defp statuses(authored), do: authored |> References.resolve(@geography) |> Enum.map(& &1.status)

  test "node anchors: ok, moved and missing" do
    assert [:ok] = statuses(authored([node_loc("node:1", [-89.385, 43.074])]))
    assert [:ok] = statuses(authored([node_loc("node:1", [-89.3850001, 43.0740001])]))
    assert [:moved] = statuses(authored([node_loc("node:1", [-89.384, 43.074])]))
    assert [:missing] = statuses(authored([node_loc("node:99", [0, 0])]))
  end

  test "edge anchors and closures compare the geometry hash" do
    assert [:ok] = statuses(authored([edge_loc("edge:1-2-101", "deadbeef")]))
    assert [:moved] = statuses(authored([edge_loc("edge:1-2-101", "different")]))
    assert [:missing] = statuses(authored([edge_loc("edge:9-9-9", "deadbeef")]))

    closure = fn ref, hash ->
      %{"id" => "clo:c", "edge" => ref, "kind" => "restricted", "geometry_hash" => hash}
    end

    assert [:ok] = statuses(authored([], [closure.("edge:1-2-101", "deadbeef")]))
    assert [:moved] = statuses(authored([], [closure.("edge:1-2-101", "x")]))
    assert [:missing] = statuses(authored([], [closure.("edge:0-0-0", "deadbeef")]))
  end

  test "free points have no geography reference" do
    free = %{"id" => "loc:f", "name" => "f", "anchor" => %{"kind" => "point", "point" => [0, 0]}}
    assert [] = References.resolve(authored([free]), @geography)
  end

  test "needing_review drops ok references" do
    refs =
      References.resolve(
        authored([node_loc("node:1", [-89.385, 43.074]), node_loc("node:99", [0, 0])]),
        @geography
      )

    assert [%{status: :missing, ref: "node:99"}] = References.needing_review(refs)
  end

  describe "Geography.index/1" do
    test "indexes the fixture network" do
      dir = Path.join([Threshold.World.root(), "tiny", "generated"])
      assert {:ok, %{nodes: nodes, edges: edges}} = Geography.index(dir)
      assert nodes["node:1"] == [-89.385, 43.074]
      assert edges["edge:1-2-101"] == "deadbeef"
    end

    test "missing geography is an error" do
      assert :error = Geography.index("/nonexistent")
    end
  end

  describe "Geography.point_at/3" do
    @bent %{lines: %{"edge:bent" => [[0.0, 0.0], [0.0, 1.0], [1.0, 1.0]]}}

    test "interpolates by length along a bent edge" do
      assert {:ok, [x0, y0]} = Geography.point_at(@bent, "edge:bent", 0)
      assert {x0, y0} == {0.0, 0.0}
      assert {:ok, [0.5, 1.0]} = Geography.point_at(@bent, "edge:bent", 0.75)
      assert {:ok, [1.0, 1.0]} = Geography.point_at(@bent, "edge:bent", 1)
      assert {:ok, [xm, 1.0]} = Geography.point_at(@bent, "edge:bent", 0.5)
      assert xm == 0.0
    end

    test "rejects unknown edges and offsets outside 0..1" do
      assert :error = Geography.point_at(@bent, "edge:nope", 0.5)
      assert :error = Geography.point_at(@bent, "edge:bent", 1.01)
      assert :error = Geography.point_at(@bent, "edge:bent", -0.01)
    end
  end
end
