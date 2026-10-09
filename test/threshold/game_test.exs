defmodule Threshold.GameTest do
  use ExUnit.Case, async: true
  alias Threshold.{Authored, Game}
  alias Threshold.Game.{Geometry, Player, World}

  defp data do
    dir = Path.join(Threshold.World.root(), "tiny")
    load = fn file -> dir |> Path.join(file) |> File.read!() |> Jason.decode!() end

    authored =
      Map.put(Authored.empty(), "spawns", [
        %{"id" => "spawn:default", "location" => "pn:1", "default" => true}
      ])

    {load.("playable.json"), load.("edges.geojson")["features"],
     load.("boundary.geojson")["geometry"], authored}
  end

  defp world(edit \\ fn data -> data end) do
    {playable, edges, boundary, authored} = edit.(data())
    {:ok, world} = World.new("tiny", playable, edges, boundary, authored)
    world
  end

  test "starts only at the authored default and allows one-hop movement/backtracking" do
    world = world()
    assert {:ok, player, %{"id" => "spawn:default"}} = Game.start(world)
    assert player.location == "pn:1" and player.turn == 0
    assert [%{destination: "pn:2"}] = Game.available_moves(world, player)
    assert {:ok, moved, route} = Game.move(world, player, "pn:2")
    assert moved.turn == 1 and moved.visited == MapSet.new(["pn:1", "pn:2"])
    assert hd(route.geometry["coordinates"]) == world.locations["pn:1"]["point"]
    assert {:ok, back, reversed} = Game.move(world, moved, "pn:1")
    assert back.location == "pn:1" and back.turn == 2
    assert reversed.geometry["coordinates"] == Enum.reverse(route.geometry["coordinates"])
    assert {:error, :unavailable} = Game.move(world, player, "pn:3")
    assert player.location == "pn:1" and player.turn == 0 and MapSet.size(player.visited) == 1
  end

  test "two-stop previews are deduplicated, exclude closer locations, and cannot be used as moves" do
    world = world()
    connection = world.connections["pc:1-2"]

    link = fn id, from, to ->
      Map.merge(connection, %{
        "id" => id,
        "from" => from,
        "to" => to,
        "geometry" => %{
          "type" => "LineString",
          "coordinates" => [world.locations[from]["point"], world.locations[to]["point"]]
        }
      })
    end

    # Two legal paths to pn:4, plus a cycle between immediate neighbors.
    world = %{
      world
      | connections:
          Map.new(
            [
              connection,
              link.("pc:1-3", "pn:1", "pn:3"),
              link.("pc:2-3", "pn:2", "pn:3"),
              link.("pc:2-4", "pn:2", "pn:4"),
              link.("pc:3-4", "pn:3", "pn:4")
            ],
            &{&1["id"], &1}
          )
    }

    player = %Player{location: "pn:1"}
    assert [%{destination: "pn:4", point: point}] = Game.two_stop_preview(world, player)
    assert point == world.locations["pn:4"]["point"]
    assert {:error, :unavailable} = Game.move(world, player, "pn:4")
    assert player.turn == 0

    assert [%{destination: "pn:3"}] =
             Game.two_stop_preview(
               %{world | connections: Map.take(world.connections, ["pc:1-2", "pc:2-3"])},
               player
             )
  end

  test "two-stop previews do not cross restricted connections" do
    world = world()
    # The imported pn:3-pn:4 route was filtered out by the access policy.
    connection = Map.merge(world.connections["pc:1-2"], %{"id" => "pc:1-3", "to" => "pn:3"})
    world = %{world | connections: Map.put(world.connections, "pc:1-3", connection)}
    assert Game.two_stop_preview(world, %Player{location: "pn:1"}) == []
  end

  test "missing/defaultless/isolated spawns are rejected" do
    assert {:error, _} = Game.start(%{world() | spawns: []})

    assert {:error, _} =
             Game.start(%{world() | spawns: [%{"location" => "pn:3", "default" => true}]})

    {p, e, b, a} = data()

    assert {:error, _} =
             World.new(
               "tiny",
               p,
               e,
               b,
               Map.put(a, "spawns", [
                 %{"id" => "spawn:bad", "location" => "pn:999", "default" => true}
               ])
             )
  end

  test "access policy checks source edges and allows uncertain virtual routes" do
    for access <- ~w(public unknown conditional mixed) do
      world =
        world(fn {p, edges, b, a} ->
          {p, put_in(edges, [Access.at(0), "properties", "access_status"], access), b, a}
        end)

      assert {:ok, _, _} = Game.start(world)
    end

    world = world()
    assert world.unavailable["pc:3-4"] == :access
    assert Game.available_moves(world, %Player{location: "pn:3"}) == []
  end

  test "authored closures block constituent edges without modifying imported geography" do
    world =
      world(fn {p, e, b, a} ->
        closure = %{
          "id" => "clo:gate",
          "edge" => "edge:1-2-101",
          "kind" => "restricted",
          "geometry_hash" => "deadbeef"
        }

        {p, e, b, Map.put(a, "closures", [closure])}
      end)

    assert world.unavailable["pc:1-2"] == :closure
    assert Game.available_moves(world, %Player{location: "pn:1"}) == []
  end

  test "a closure on an interior constituent edge blocks the whole multi-edge move" do
    world =
      world(fn {p, edges, b, a} ->
        edge = hd(edges)
        [first, last] = edge["geometry"]["coordinates"]
        middle = Enum.zip_with(first, last, &((&1 + &2) / 2))

        one =
          edge
          |> Map.put("id", "edge:1-99-101")
          |> put_in(["properties", "id"], "edge:1-99-101")
          |> put_in(["properties", "to"], "node:99")
          |> put_in(["geometry", "coordinates"], [first, middle])

        two =
          edge
          |> Map.put("id", "edge:99-2-102")
          |> put_in(["properties", "id"], "edge:99-2-102")
          |> put_in(["properties", "from"], "node:99")
          |> put_in(["geometry", "coordinates"], [middle, last])

        p = put_in(p, ["connections", Access.at(0), "edge_ids"], [one["id"], two["id"]])

        closure = %{
          "id" => "clo:interior",
          "edge" => two["id"],
          "kind" => "restricted",
          "geometry_hash" => "deadbeef"
        }

        {:ok, open} = World.new("tiny", p, [one, two | tl(edges)], b, a)
        assert {:ok, _, _} = Game.start(open)
        {p, [one, two | tl(edges)], b, Map.put(a, "closures", [closure])}
      end)

    assert world.unavailable["pc:1-2"] == :closure
    assert Game.available_moves(world, %Player{location: "pn:1"}) == []
  end

  test "route excursion and mismatched generated geometry are rejected" do
    world =
      world(fn {p, edges, b, a} ->
        [first, last] = hd(edges)["geometry"]["coordinates"]

        edges =
          put_in(edges, [Access.at(0), "geometry", "coordinates"], [first, [-89.40, 43.075], last])

        {p, edges, b, a}
      end)

    assert world.unavailable["pc:1-2"] == :boundary

    world =
      world(fn {p, e, b, a} ->
        {put_in(p, ["connections", Access.at(0), "geometry"], %{
           "type" => "LineString",
           "coordinates" => [[0, 0], [1, 1]]
         }), e, b, a}
      end)

    assert world.unavailable["pc:1-2"] == :invalid_route
  end

  test "route coverage handles concave boundaries and boundary segments" do
    polygon = %{
      "type" => "Polygon",
      "coordinates" => [[[0, 0], [4, 0], [4, 4], [3, 4], [3, 1], [1, 1], [1, 4], [0, 4], [0, 0]]]
    }

    route = fn coordinates -> %{"type" => "LineString", "coordinates" => coordinates} end
    refute Geometry.covered?(route.([[0.5, 3], [3.5, 3]]), polygon)
    assert Geometry.covered?(route.([[0.5, 3], [0.5, 0.5], [3.5, 0.5], [3.5, 3]]), polygon)
    assert Geometry.covered?(route.([[0, 0], [4, 0]]), polygon)
  end

  test "nearby places require an explicit movement attachment" do
    world =
      world(fn {p, e, b, a} ->
        place = %{
          "id" => "loc:place",
          "name" => "Unmarked door",
          "notes" => "A faint tapping.",
          "movement_location" => "pn:2",
          "anchor" => %{"kind" => "point", "point" => [-89.38, 43.075]}
        }

        {p, e, b, Map.put(a, "locations", [place])}
      end)

    assert Game.nearby(world, %Player{location: "pn:1"}) == []
    assert [%{"name" => "Unmarked door"}] = Game.nearby(world, %Player{location: "pn:2"})
  end

  test "schema validates multiple spawn definitions, one default, and explicit place attachments" do
    {_, _, _, authored} = data()
    assert {:ok, doc} = Authored.validate(authored)
    assert length(doc["spawns"]) == 1

    duplicate =
      Map.put(authored, "spawns", [
        hd(authored["spawns"]),
        %{"id" => "spawn:other", "location" => "pn:2", "default" => true}
      ])

    assert {:error, errors} = Authored.validate(duplicate)
    assert Enum.any?(errors, &String.contains?(&1, "one default"))
    assert {:error, _} = Authored.validate(Map.put(authored, "spawns", "broken"))
    assert {:error, _} = Authored.validate(Map.put(authored, "spawns", nil))
  end
end
