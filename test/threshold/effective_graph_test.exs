defmodule Threshold.EffectiveGraphTest do
  use ExUnit.Case, async: false
  alias Threshold.{Authored, EffectiveGraph, Game}
  alias Threshold.Game.Player

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    File.cp_r!(Path.join(Threshold.World.root(), "tiny"), Path.join(tmp, "tiny"))
    previous = Application.get_env(:threshold, :worlds_dir)
    Application.put_env(:threshold, :worlds_dir, tmp)
    on_exit(fn -> Application.put_env(:threshold, :worlds_dir, previous) end)
    %{dir: Path.join(tmp, "tiny")}
  end

  defp edge_anchor(offset),
    do: %{
      "kind" => "edge",
      "ref" => "edge:1-2-101",
      "offset" => offset,
      "point" => [-89.3825, 43.0745],
      "ref_geometry_hash" => "deadbeef"
    }

  defp place(id, anchor, extra \\ %{}),
    do: Map.merge(%{"id" => id, "name" => "New location", "anchor" => anchor}, extra)

  defp node(ref, point), do: %{"kind" => "node", "ref" => ref, "point" => point}

  defp link(id, from, to),
    do: %{"id" => id, "from" => from, "to" => to, "kind" => "fictional", "geometry" => nil}

  # A (node:1) -- B (mid-block) -- C (node:2); free point D; E on the unconnected street 3-4.
  defp write_authored(dir, overrides \\ %{}) do
    doc =
      Map.merge(
        Authored.empty(),
        Map.merge(
          %{
            "locations" => [
              place("loc:a", node("node:1", [-89.385, 43.074]), %{
                "name" => "The corner",
                "notes" => "Quiet."
              }),
              place("loc:b", edge_anchor(0.5)),
              place("loc:c", node("node:2", [-89.38, 43.075])),
              place("loc:d", %{"kind" => "point", "point" => [-89.381, 43.0751]}),
              place("loc:e", node("node:3", [-89.375, 43.076]))
            ],
            "connections" => [
              link("conn:ab", "loc:a", "loc:b"),
              link("conn:bc", "loc:b", "loc:c"),
              link("conn:ad", "loc:a", "loc:d"),
              link("conn:ce", "loc:c", "loc:e")
            ],
            "spawns" => [%{"id" => "spawn:default", "location" => "pn:1", "default" => true}]
          },
          overrides
        )
      )

    File.write!(Path.join(dir, "authored.json"), Authored.encode(doc))
  end

  test "authored places become locations and resolvable connections become real walks", %{
    dir: dir
  } do
    write_authored(dir)
    assert {:ok, world} = EffectiveGraph.load("tiny")

    assert world.name == "tiny:authored" and world.graph == :authored
    assert Map.keys(world.locations) |> Enum.sort() == ["loc:a", "loc:b", "loc:c", "loc:e"]
    assert Map.keys(world.connections) |> Enum.sort() == ["conn:ab", "conn:bc"]
    assert world.unavailable == %{"conn:ad" => :unanchored, "conn:ce" => :no_path}

    ab = world.connections["conn:ab"]
    assert hd(ab["geometry"]["coordinates"]) == world.locations["loc:a"]["point"]
    assert List.last(ab["geometry"]["coordinates"]) == world.locations["loc:b"]["point"]
    assert world.locations["loc:b"]["point"] == [-89.3825, 43.0745]
    assert_in_delta ab["length_m"], 50.0, 0.1
  end

  test "movement on the authored graph is one hop along the real route and one turn", %{dir: dir} do
    write_authored(dir)
    {:ok, world} = EffectiveGraph.load("tiny")

    assert {:ok, %Player{location: "loc:a"} = player, %{"location" => "loc:a"}} =
             Game.start(world)

    assert ["loc:b"] == Game.numbered_moves(world, player) |> Enum.map(& &1.destination)
    assert {:error, :unavailable} = Game.move(world, player, "loc:c")
    assert {:ok, at_b, route} = Game.move(world, player, "loc:b")
    assert at_b.turn == 1 and route.length_m == world.connections["conn:ab"]["length_m"]

    # From the mid-block place both neighbours are offered, numbered clockwise from north.
    assert [%{key: "1"}, %{key: "2"}] = Game.numbered_moves(world, at_b)
    assert {:ok, %{location: "loc:c", turn: 2}, back} = Game.move(world, at_b, "loc:c")
    assert hd(back.geometry["coordinates"]) == world.locations["loc:b"]["point"]
    # An authored link whose walk does not exist is not a move.
    assert {:error, :unavailable} = Game.move(world, %Player{location: "loc:c"}, "loc:e")
  end

  test "only places with a name or notes are offered for inspection", %{dir: dir} do
    write_authored(dir)
    {:ok, world} = EffectiveGraph.load("tiny")
    assert [%{"id" => "loc:a", "name" => "The corner", "notes" => "Quiet."}] = world.places
    assert [%{"id" => "loc:a"}] = Game.nearby(world, %Player{location: "loc:a"})
    assert [] = Game.nearby(world, %Player{location: "loc:b"})
  end

  test "an authored closure removes the walk and names no path through it", %{dir: dir} do
    closure = %{
      "id" => "clo:1",
      "edge" => "edge:1-2-101",
      "kind" => "restricted",
      "geometry_hash" => "deadbeef"
    }

    write_authored(dir, %{"closures" => [closure]})
    {:ok, world} = EffectiveGraph.load("tiny")
    assert world.connections == %{}
    assert world.unavailable["conn:ab"] == :closure
  end

  test "spawns map to the nearest authored place; an unmappable default is an error", %{dir: dir} do
    spawns = [
      %{"id" => "spawn:default", "location" => "pn:1", "default" => true},
      %{"id" => "spawn:far", "location" => "pn:3", "default" => false}
    ]

    write_authored(dir, %{"spawns" => spawns})
    assert {:ok, world} = EffectiveGraph.load("tiny")

    assert [%{"location" => "loc:a"}, %{"location" => "loc:e"}] =
             Enum.sort_by(world.spawns, & &1["id"])

    write_authored(dir, %{
      "spawns" => [%{"id" => "spawn:default", "location" => "pn:4", "default" => true}]
    })

    assert {:error, "The default spawn is not within 25 m" <> _} = EffectiveGraph.load("tiny")
  end

  test "the revision changes with the authored file and the loader never writes", %{dir: dir} do
    write_authored(dir)
    before = File.read!(Path.join(dir, "authored.json"))
    {:ok, first} = EffectiveGraph.load("tiny")
    assert File.read!(Path.join(dir, "authored.json")) == before
    write_authored(dir, %{"closures" => []} |> Map.put("connections", []))
    {:ok, second} = EffectiveGraph.load("tiny")
    assert first.revision != second.revision
  end
end
