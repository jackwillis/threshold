defmodule Threshold.WalkingAccessTest do
  use ExUnit.Case, async: true

  alias Threshold.{Authored, Geography, Polyline, References, RouteResolver}
  alias Threshold.Authored.Edit

  @geography %{
    nodes: %{"node:1" => [-89.385, 43.074], "node:2" => [-89.38, 43.075]},
    edges: %{"edge:1-2-101" => "hash101"},
    lines: %{"edge:1-2-101" => [[-89.385, 43.074], [-89.38, 43.075]]}
  }

  @edge_feature %{
    "id" => "edge:1-2-101",
    "geometry" => %{
      "type" => "LineString",
      "coordinates" => [[-89.385, 43.074], [-89.38, 43.075]]
    },
    "properties" => %{
      "id" => "edge:1-2-101",
      "from" => "node:1",
      "to" => "node:2",
      "length_m" => 100.0,
      "access_status" => "unknown",
      "inside_playable" => true
    }
  }

  defp free(id, point \\ [-89.3825, 43.0746]),
    do: %{"id" => id, "name" => id, "anchor" => %{"kind" => "point", "point" => point}}

  defp at_node(id),
    do: %{
      "id" => id,
      "name" => id,
      "anchor" => %{"kind" => "node", "ref" => "node:2", "point" => [-89.38, 43.075]}
    }

  defp doc(locations, connections \\ []),
    do: %{Authored.empty() | "locations" => locations, "connections" => connections}

  describe "schema" do
    test "access is optional and its absence is left alone" do
      assert {:ok, normalized} = Authored.validate(doc([free("loc:a")]))
      refute Map.has_key?(hd(normalized["locations"]), "access")
    end

    test "a node or edge access validates; a point or garbage does not" do
      node = %{"kind" => "node", "ref" => "node:1", "point" => [-89.385, 43.074]}
      assert {:ok, _} = Authored.validate(doc([Map.put(free("loc:a"), "access", node)]))

      point = %{"kind" => "point", "point" => [-89.385, 43.074]}

      assert {:error, [message]} =
               Authored.validate(doc([Map.put(free("loc:a"), "access", point)]))

      assert message =~ "locations[0].access"

      assert {:error, _} = Authored.validate(doc([Map.put(free("loc:a"), "access", "street")]))

      bad_edge = %{"kind" => "edge", "ref" => "edge:1-2-101", "offset" => 2, "point" => [0, 0]}
      assert {:error, _} = Authored.validate(doc([Map.put(free("loc:a"), "access", bad_edge)]))
    end

    test "a document with access round-trips through encode and parse" do
      {:ok, edited} =
        Edit.set_access(doc([free("loc:a")]), "loc:a", edge_request(0.5), @geography)

      assert {:ok, parsed, _} = Authored.parse(Authored.encode(edited))
      assert parsed == edited
    end
  end

  defp edge_request(offset), do: %{"kind" => "edge", "ref" => "edge:1-2-101", "offset" => offset}

  describe "edit" do
    test "setting access derives the position on the server and leaves the marker alone" do
      before = doc([free("loc:a")])

      assert {:ok, edited} =
               Edit.set_access(
                 before,
                 "loc:a",
                 Map.put(edge_request(0.5), "point", [0, 0]),
                 @geography
               )

      [loc] = edited["locations"]
      assert loc["anchor"] == hd(before["locations"])["anchor"]

      assert %{
               "kind" => "edge",
               "offset" => 0.5,
               "ref_geometry_hash" => "hash101",
               "point" => point
             } =
               loc["access"]

      assert point == Polyline.at(@geography.lines["edge:1-2-101"], 0.5)
    end

    test "access must be a street or intersection that exists" do
      d = doc([free("loc:a")])

      assert {:error, _} =
               Edit.set_access(d, "loc:a", %{"kind" => "point", "point" => [0, 0]}, @geography)

      assert {:error, _} =
               Edit.set_access(d, "loc:a", %{"kind" => "node", "ref" => "node:9"}, @geography)

      assert {:error, _} = Edit.set_access(d, "loc:a", edge_request(1.5), @geography)
      assert {:error, _} = Edit.set_access(d, "loc:zz", edge_request(0.5), @geography)
    end

    test "clearing access restores the previous behaviour" do
      {:ok, d} = Authored.validate(doc([free("loc:a")]))
      {:ok, with_access} = Edit.set_access(d, "loc:a", edge_request(0.5), @geography)
      assert {:ok, ^d} = Edit.clear_access(with_access, "loc:a")
    end

    test "moving the marker leaves access where it was" do
      {:ok, d} = Edit.set_access(doc([free("loc:a")]), "loc:a", edge_request(0.5), @geography)
      access = hd(d["locations"])["access"]

      {:ok, moved} =
        Edit.move_location(d, "loc:a", %{"kind" => "point", "point" => [-89.3, 43.0]}, @geography)

      assert hd(moved["locations"])["access"] == access
      assert hd(moved["locations"])["anchor"]["point"] == [-89.3, 43.0]
    end
  end

  describe "route resolution" do
    defp resolve(locations, connections),
      do: RouteResolver.resolve(doc(locations, connections), [@edge_feature])

    defp link,
      do: %{
        "id" => "conn:x",
        "from" => "loc:a",
        "to" => "loc:b",
        "kind" => "fictional",
        "geometry" => nil
      }

    test "a free point without access stays unwalkable" do
      report = resolve([free("loc:a"), at_node("loc:b")], [link()])
      assert [%{status: :unanchored}] = report.connections
    end

    test "a free point with access is walkable from its access, and keeps its display point" do
      {:ok, d} =
        Edit.set_access(
          doc([free("loc:a"), at_node("loc:b")]),
          "loc:a",
          edge_request(0.5),
          @geography
        )

      report = RouteResolver.resolve(%{d | "connections" => [link()]}, [@edge_feature])

      assert [%{status: :ok, path_m: 50.0}] = report.connections
      place = Enum.find(report.places, &(&1.id == "loc:a"))
      assert place.class == :mid_block
      assert place.point == [-89.3825, 43.0746]
      assert place.access
    end

    test "access wins over a street anchor: the place is reached where access says" do
      anchor_on_node = at_node("loc:a")
      access = %{"kind" => "node", "ref" => "node:1", "point" => [-89.385, 43.074]}
      loc = Map.put(anchor_on_node, "access", access)
      report = resolve([loc, at_node("loc:b")], [link()])
      assert [%{status: :ok, path_m: 100.0}] = report.connections
    end

    test "existing places without access resolve exactly as before" do
      report = resolve([at_node("loc:a"), at_node("loc:b")], [link()])
      assert [%{status: :same_position}] = report.connections
      refute Enum.any?(report.places, & &1[:access])
    end
  end

  describe "references" do
    test "a moved or missing access street is reported against the place" do
      access = %{
        "kind" => "edge",
        "ref" => "edge:1-2-101",
        "offset" => 0.5,
        "point" => [0, 0],
        "ref_geometry_hash" => "old"
      }

      d = doc([Map.put(free("loc:a"), "access", access)])

      assert [%{object: "loc:a", field: "access", status: :moved}] =
               References.resolve(d, @geography)

      gone = put_in(d, ["locations", Access.at(0), "access", "ref"], "edge:9-9-9")
      assert [%{field: "access", status: :missing}] = References.resolve(gone, @geography)
    end
  end

  describe "nearest street" do
    test "finds the street and its offset within range, otherwise nothing" do
      assert {:ok, %{request: %{"ref" => "edge:1-2-101", "offset" => offset}, distance_m: metres}} =
               Geography.nearest_street(@geography, [-89.3825, 43.0746], 60)

      assert offset > 0.3 and offset < 0.7
      assert metres > 0 and metres < 60
      assert Geography.nearest_street(@geography, [-89.3, 43.0], 60) == :none
    end
  end
end
