defmodule Threshold.MadisonGeographyTest do
  # Invariants of the committed generated Madison geography under the game's traversal rules.
  # Reads only generated files and the boundary, never the designer's authored.json.
  use ExUnit.Case, async: true
  alias Threshold.{Authored, Game}
  alias Threshold.Game.{Player, World}

  @dir Path.expand("../../priv/worlds/madison", __DIR__)

  setup_all do
    load = fn path -> path |> File.read!() |> Jason.decode!() end
    playable = load.(Path.join(@dir, "generated/playable.json"))
    edges = load.(Path.join(@dir, "generated/edges.geojson"))["features"]
    boundary = load.(Path.join(@dir, "boundary.geojson"))["geometry"]
    {:ok, world} = World.new("madison", playable, edges, boundary, Authored.empty())
    %{world: world, playable: playable}
  end

  test "the active generated snapshot is complete and readable" do
    assert {:ok, %{dir: dir}} = Threshold.Generated.active(@dir)
    for file <- Threshold.Generated.files(), do: assert(File.regular?(Path.join(dir, file)))
  end

  test "every playable connection is a continuous walk or excluded by a known rule", %{
    world: world,
    playable: playable
  } do
    assert map_size(world.connections) + map_size(world.unavailable) ==
             length(playable["connections"])

    assert map_size(world.connections) > 1000
    # No connection may fail for a structural reason (broken or discontinuous source edges).
    assert world.unavailable
           |> Map.values()
           |> Enum.uniq()
           |> Enum.all?(&(&1 in [:boundary, :access, :closure]))
  end

  test "valid connections start and end on their locations and are reversible", %{world: world} do
    for {id, conn} <- world.connections do
      coordinates = conn["geometry"]["coordinates"]
      assert hd(coordinates) == world.locations[conn["from"]]["point"], id
      assert List.last(coordinates) == world.locations[conn["to"]]["point"], id

      back =
        Game.available_moves(world, %Player{location: conn["to"]})
        |> Enum.find(&(&1.connection == id))

      assert back && back.destination == conn["from"], id
      assert back.geometry["coordinates"] == Enum.reverse(coordinates), id
    end
  end

  test "an unavailable connection never appears as a move", %{world: world} do
    offered =
      for {loc, _} <- world.locations,
          m <- Game.available_moves(world, %Player{location: loc}),
          into: MapSet.new(),
          do: m.connection

    assert MapSet.disjoint?(offered, MapSet.new(Map.keys(world.unavailable)))
  end
end
