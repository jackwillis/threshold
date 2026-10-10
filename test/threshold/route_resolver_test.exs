defmodule Threshold.RouteResolverTest do
  use ExUnit.Case, async: true
  alias Threshold.{Authored, RouteResolver}

  # A -100- B -100- C, a long direct A -300- C, an isolated D -100- E, and B -50- F -50- G where
  # B-F is restricted (so G is only reachable through a rule).
  defp edge(id, from, to, length, extra \\ %{}) do
    %{
      "id" => id,
      "type" => "Feature",
      "geometry" => %{"type" => "LineString", "coordinates" => [[0, 0], [0, 1]]},
      "properties" =>
        Map.merge(
          %{
            "id" => id,
            "from" => from,
            "to" => to,
            "length_m" => length,
            "access_status" => "unknown",
            "inside_playable" => true
          },
          extra
        )
    }
  end

  defp edges,
    do: [
      edge("e:ab", "n:a", "n:b", 100),
      edge("e:bc", "n:b", "n:c", 100),
      edge("e:ac", "n:a", "n:c", 300),
      edge("e:de", "n:d", "n:e", 100),
      edge("e:bf", "n:b", "n:f", 50, %{"access_status" => "restricted"}),
      edge("e:fg", "n:f", "n:g", 50)
    ]

  defp node(id, node), do: loc(id, %{"kind" => "node", "ref" => node, "point" => [0.0, 0.0]})

  defp mid(id, edge, offset),
    do:
      loc(id, %{
        "kind" => "edge",
        "ref" => edge,
        "offset" => offset,
        "point" => [0.0, 0.5],
        "ref_geometry_hash" => "h"
      })

  defp loc(id, anchor), do: %{"id" => id, "name" => id, "anchor" => anchor}

  defp link(from, to),
    do: %{
      "id" => "conn:#{from}-#{to}",
      "from" => from,
      "to" => to,
      "kind" => "fictional",
      "geometry" => nil
    }

  defp resolve(locations, connections, closures \\ []) do
    doc = %{
      Authored.empty()
      | "locations" => locations,
        "connections" => connections,
        "closures" => closures
    }

    RouteResolver.resolve(doc, edges(), %{"n:a" => "pn:a"})
  end

  defp conn(report, from, to),
    do: Enum.find(report.connections, &(&1.from == from and &1.to == to))

  test "a walk follows the shortest street path and reports the edges it uses" do
    report = resolve([node("loc:1", "n:a"), node("loc:2", "n:c")], [link("loc:1", "loc:2")])

    assert %{status: :ok, path_m: 200.0, edges: ["e:ab", "e:bc"], blockers: []} =
             conn(report, "loc:1", "loc:2")

    assert report.places |> hd() |> Map.get(:playable) == "pn:a"
  end

  test "a place halfway down a block splits its edge and is routable from both ends" do
    report =
      resolve([node("loc:a", "n:a"), mid("loc:m", "e:ac", 0.5), node("loc:c", "n:c")], [
        link("loc:a", "loc:m"),
        link("loc:m", "loc:c")
      ])

    assert Enum.find(report.places, &(&1.id == "loc:m")).class == :mid_block
    assert %{status: :ok, path_m: 150.0, edges: ["e:ac"]} = conn(report, "loc:a", "loc:m")
    assert %{status: :ok, path_m: 150.0} = conn(report, "loc:m", "loc:c")
  end

  test "two places on one edge are chained in offset order" do
    report =
      resolve([mid("loc:x", "e:ac", 0.75), mid("loc:y", "e:ac", 0.25)], [link("loc:y", "loc:x")])

    assert %{status: :ok, path_m: 150.0} = conn(report, "loc:y", "loc:x")
  end

  test "a place within a few metres of an intersection is that intersection" do
    report = resolve([mid("loc:n", "e:ab", 0.03), node("loc:a", "n:a")], [link("loc:n", "loc:a")])

    assert %{class: :near_intersection, node: "n:a", snap_m: 3.0} =
             Enum.find(report.places, &(&1.id == "loc:n"))

    assert %{status: :same_position, path_m: +0.0} = conn(report, "loc:n", "loc:a")
  end

  test "an authored closure reroutes the walk, or blocks it and names the edge" do
    locations = [node("loc:a", "n:a"), node("loc:c", "n:c")]
    closure = %{"id" => "clo:1", "edge" => "e:bc", "kind" => "restricted", "geometry_hash" => "h"}

    assert %{status: :ok, path_m: 300.0, edges: ["e:ac"]} =
             resolve(locations, [link("loc:a", "loc:c")], [closure]) |> conn("loc:a", "loc:c")

    both = [closure, %{closure | "id" => "clo:2", "edge" => "e:ac"}]
    blocked = resolve(locations, [link("loc:a", "loc:c")], both) |> conn("loc:a", "loc:c")
    assert %{status: :blocked, blockers: blockers} = blocked
    assert Enum.all?(blockers, &(&1.reason == :closure))
  end

  test "a rule blocks a route that exists geographically; a disconnected network has no path" do
    report =
      resolve([node("loc:a", "n:a"), node("loc:g", "n:g"), node("loc:d", "n:d")], [
        link("loc:a", "loc:g"),
        link("loc:a", "loc:d")
      ])

    assert %{status: :blocked, blockers: [%{edge: "e:bf", reason: :access}]} =
             conn(report, "loc:a", "loc:g")

    assert %{status: :no_path} = conn(report, "loc:a", "loc:d")
  end

  test "free points and missing edges are reported, never guessed" do
    free = loc("loc:free", %{"kind" => "point", "point" => [0.0, 0.5]})
    missing = mid("loc:gone", "e:nope", 0.5)

    report =
      resolve([node("loc:a", "n:a"), free, missing], [
        link("loc:a", "loc:free"),
        link("loc:a", "loc:gone")
      ])

    assert %{status: :unanchored, note: "loc:free is a free point" <> _} =
             conn(report, "loc:a", "loc:free")

    assert %{status: :unanchored, note: "loc:gone references e:nope" <> _} =
             conn(report, "loc:a", "loc:gone")

    assert %{nearest_edge: %{distance_m: _}} = Enum.find(report.places, &(&1.id == "loc:free"))
  end

  test "long walks relative to the straight line are flagged as detours" do
    near = [
      loc("loc:a", %{"kind" => "node", "ref" => "n:a", "point" => [0.0, 0.0]}),
      loc("loc:c", %{"kind" => "node", "ref" => "n:c", "point" => [0.0, 0.0001]})
    ]

    closure = %{"id" => "clo:1", "edge" => "e:bc", "kind" => "restricted", "geometry_hash" => "h"}

    assert %{status: :ok, detour: true} =
             resolve(near, [link("loc:a", "loc:c")], [closure]) |> conn("loc:a", "loc:c")
  end
end
