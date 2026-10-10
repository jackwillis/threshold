defmodule Threshold.GameSessionsConcurrencyTest do
  # These tests need real, independent connections: the shared sandbox used elsewhere funnels
  # every task through one connection and would hide races. The test database is disposable.
  use ExUnit.Case, async: false
  alias Threshold.{Authored, Repo}
  alias Threshold.Game.{Progress, Sessions, World}
  @moduletag :database

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Repo.delete_all(Progress)

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
      Repo.delete_all(Progress)
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    end)

    %{world: world()}
  end

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

  defp progress, do: Repo.get_by!(Progress, world: "tiny")

  defp tally(results),
    do:
      Enum.frequencies_by(results, fn
        {:ok, _} -> :ok
        {:error, reason} -> reason
      end)

  test "competing moves from one turn advance the saved turn exactly once", %{world: world} do
    {:ok, _} = Sessions.load_or_start(world)

    results =
      for _ <- 1..16, do: Task.async(fn -> Sessions.move(world, 0, "pn:2") end)

    assert %{ok: 1, stale_turn: 15} = results |> Task.await_many() |> tally()
    assert %{turn: 1, location: "pn:2"} = progress()
  end

  test "a replayed request and a failed move leave the save unchanged", %{world: world} do
    {:ok, _} = Sessions.load_or_start(world)
    assert {:ok, _} = Sessions.move(world, 0, "pn:2")
    assert {:error, :stale_turn} = Sessions.move(world, 0, "pn:2")
    assert {:error, :unavailable} = Sessions.move(world, 1, "pn:4")
    assert %{turn: 1, location: "pn:2", visited: ["pn:1", "pn:2"]} = progress()
  end

  test "concurrent initialization creates one save", %{world: world} do
    results = for _ <- 1..12, do: Task.async(fn -> Sessions.load_or_start(world) end)
    assert %{ok: 12} = results |> Task.await_many() |> tally()
    assert Repo.aggregate(Progress, :count) == 1
    assert %{turn: 0, location: "pn:1"} = progress()
  end

  test "resets racing moves always leave a coherent save", %{world: world} do
    {:ok, _} = Sessions.load_or_start(world)

    tasks =
      for _ <- 1..8 do
        [
          Task.async(fn -> Sessions.move(world, 0, "pn:2") end),
          Task.async(fn -> Sessions.reset(world) end)
        ]
      end

    Task.await_many(List.flatten(tasks))
    saved = progress()
    assert {saved.turn, saved.location} in [{0, "pn:1"}, {1, "pn:2"}]
    assert saved.visited == if(saved.turn == 0, do: ["pn:1"], else: ["pn:1", "pn:2"])
  end

  test "a world revision mismatch blocks moves without changing the save", %{world: world} do
    {:ok, _} = Sessions.load_or_start(world)
    changed = %{world | revision: "another-revision"}

    results = for _ <- 1..6, do: Task.async(fn -> Sessions.move(changed, 0, "pn:2") end)

    assert Task.await_many(results)
           |> Enum.all?(&match?({:error, "The authored world has changed" <> _}, &1))

    assert %{turn: 0, location: "pn:1"} = progress()
  end
end
