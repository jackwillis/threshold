defmodule Threshold.AttachmentAuditTest do
  use ExUnit.Case, async: true
  alias Threshold.{Authored, AttachmentAudit}
  alias Threshold.Game.World

  # Fixture: pn:1 -- pn:2 is walkable; pn:3 and pn:4 are not connected to them (access filtered).
  defp world do
    dir = Path.join(Threshold.World.root(), "tiny")
    load = fn file -> dir |> Path.join(file) |> File.read!() |> Jason.decode!() end

    authored =
      Map.put(Authored.empty(), "spawns", [
        %{"id" => "spawn:default", "location" => "pn:1", "default" => true}
      ])

    {:ok, world} =
      World.new(
        "tiny",
        load.("generated/playable.json"),
        load.("generated/edges.geojson")["features"],
        load.("boundary.geojson")["geometry"],
        authored
      )

    world
  end

  defp loc(id, point, extra \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "name" => id,
        "anchor" => %{"kind" => "point", "point" => point}
      },
      extra
    )
  end

  defp conn(id, from, to),
    do: %{"id" => id, "from" => from, "to" => to, "kind" => "fictional", "geometry" => nil}

  defp audit(locations, connections) do
    doc = %{Authored.empty() | "locations" => locations, "connections" => connections}
    AttachmentAudit.audit(doc, world())
  end

  defp place(report, id), do: Enum.find(report.places, &(&1.id == id))

  test "classifies attached, missing-target and unattached places without changing anything" do
    locations = [
      loc("loc:a", [-89.385, 43.0741], %{"movement_location" => "pn:2"}),
      loc("loc:b", [-89.38, 43.075], %{"movement_location" => "pn:999"}),
      loc("loc:c", [-89.3849, 43.0741])
    ]

    report = audit(locations, [])

    assert %{status: :attached, reachable: true} = place(report, "loc:a")
    assert %{status: :missing_target, suggestion: nil} = place(report, "loc:b")

    assert %{status: :unattached, suggestion: %{id: "pn:1"}, reachable: true} =
             place(report, "loc:c")

    assert %{by_status: %{attached: 1, missing_target: 1, unattached: 1}} = report.summary
  end

  test "a place on a source edge is offered that edge's connection endpoints" do
    anchor = %{
      "kind" => "edge",
      "ref" => "edge:1-2-101",
      "offset" => 0.5,
      "point" => [-89.3825, 43.0745]
    }

    report = audit([loc("loc:mid", anchor["point"], %{"anchor" => anchor})], [])

    assert %{suggestion: %{via: :source_edge}, flags: flags} = place(report, "loc:mid")
    # Both ends of a mid-block place are about equally close, so it is flagged ambiguous.
    assert :ambiguous in flags
    assert report.summary.unattached_with_edge_suggestion == 1
  end

  test "a suggestion that the spawn cannot reach is flagged disconnected, not reachable" do
    report = audit([loc("loc:far", [-89.375, 43.076])], [])
    assert %{suggestion: %{id: "pn:3"}, reachable: false, flags: flags} = place(report, "loc:far")
    assert :disconnected in flags
  end

  test "a place with no playable location nearby has no candidate" do
    report = audit([loc("loc:nowhere", [-88.0, 42.0])], [])

    assert %{suggestion: nil, reachable: nil, flags: [:disconnected]} =
             place(report, "loc:nowhere")
  end

  test "connections compare the walk with the straight line and keep their kind" do
    locations = [
      loc("loc:a", [-89.385, 43.0741], %{"movement_location" => "pn:1"}),
      loc("loc:b", [-89.38, 43.075], %{"movement_location" => "pn:2"}),
      loc("loc:c", [-89.375, 43.076], %{"movement_location" => "pn:3"}),
      loc("loc:d", [-89.3851, 43.0741], %{"movement_location" => "pn:1"})
    ]

    connections = [
      conn("conn:ab", "loc:a", "loc:b"),
      conn("conn:ac", "loc:a", "loc:c"),
      conn("conn:ad", "loc:a", "loc:d")
    ]

    report = audit(locations, connections)
    by_id = Map.new(report.connections, &{&1.id, &1})

    assert %{class: :plausible_walk, kind: "fictional", walk_m: walk} = by_id["conn:ab"]
    assert walk > 0
    assert %{class: :no_walking_route, walk_m: nil, endpoints_reachable: false} = by_id["conn:ac"]
    assert %{class: :same_access_point} = by_id["conn:ad"]
    assert report.summary.connections_by_kind == %{"fictional" => 3}
  end

  test "the audit does not modify the authored document it is given" do
    doc = %{Authored.empty() | "locations" => [loc("loc:x", [-89.385, 43.0741])]}
    assert AttachmentAudit.audit(doc, world()) |> is_map()
    assert doc["locations"] == [loc("loc:x", [-89.385, 43.0741])]
    refute Map.has_key?(hd(doc["locations"]), "movement_location")
  end
end
