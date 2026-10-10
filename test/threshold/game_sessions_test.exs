defmodule Threshold.GameSessionsTest do
  use ExUnit.Case, async: false
  alias Threshold.{Authored, Repo}
  alias Threshold.Game.{Progress, Sessions, World}
  @moduletag :database

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
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

    %{world: world}
  end

  test "restores durable progress, rejects replay and leaves invalid movement unchanged", %{
    world: world
  } do
    assert {:ok, player} = Sessions.load_or_start(world)
    assert player.turn == 0
    assert {:error, :unavailable} = Sessions.move(world, 0, "pn:3")
    assert Repo.get_by!(Progress, world: "tiny").turn == 0
    assert {:ok, {moved, _route}} = Sessions.move(world, 0, "pn:2")
    assert moved.turn == 1
    assert {:error, :stale_turn} = Sessions.move(world, 0, "pn:1")
    assert {:ok, ^moved} = Sessions.load_or_start(world)
    assert {:ok, {back, _}} = Sessions.move(world, 1, "pn:1")
    assert back.turn == 2 and MapSet.size(back.visited) == 2
  end

  test "a destination more than one hop away is refused and spends no turn", %{world: world} do
    connection =
      Map.merge(world.connections["pc:1-2"], %{
        "id" => "pc:2-3",
        "from" => "pn:2",
        "to" => "pn:3",
        "geometry" => %{
          "type" => "LineString",
          "coordinates" => [world.locations["pn:2"]["point"], world.locations["pn:3"]["point"]]
        }
      })

    world = %{world | connections: Map.put(world.connections, "pc:2-3", connection)}
    assert {:ok, _} = Sessions.load_or_start(world)
    assert {:error, :unavailable} = Sessions.move(world, 0, "pn:3")
    assert %{turn: 0, location: "pn:1"} = Repo.get_by!(Progress, world: "tiny")
    assert {:ok, {moved, _}} = Sessions.move(world, 0, "pn:2")
    assert {:ok, {onward, _}} = Sessions.move(world, 1, "pn:3")
    assert onward.turn == 2 and onward.visited == MapSet.new(["pn:1", "pn:2", "pn:3"])
    assert moved.turn == 1
  end

  test "changed worlds require an explicit reset", %{world: world} do
    assert {:ok, _} = Sessions.load_or_start(world)
    changed = %{world | revision: "new-world"}
    assert {:error, message} = Sessions.load_or_start(changed)
    assert message =~ "world has changed"
    assert {:error, ^message} = Sessions.move(changed, 0, "pn:2")
    assert {:ok, reset} = Sessions.reset(changed)
    assert reset.turn == 0
    assert {:ok, ^reset} = Sessions.load_or_start(changed)
  end
end
