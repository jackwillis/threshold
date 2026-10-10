defmodule Threshold.InteractionsFixture do
  @moduledoc """
  The tiny synthetic world for interaction tests: two authored places (`loc:a` at `pn:1`, `loc:b`
  at `pn:2`) joined by one playable connection, plus the two-interaction content in
  `test/fixtures/interactions/synthetic.json`. Never the Madison world.
  """
  alias Threshold.{Authored, Interactions}
  alias Threshold.Game.World

  def content do
    {:ok, doc, _hash} =
      Path.expand("../fixtures/interactions/synthetic.json", __DIR__)
      |> File.read!()
      |> Interactions.parse()

    doc
  end

  def authored do
    place = fn id, name, movement ->
      %{
        "id" => id,
        "name" => name,
        "notes" => "",
        "anchor" => %{"kind" => "point", "point" => [-89.38, 43.075]},
        "movement_location" => movement
      }
    end

    Map.merge(Authored.empty(), %{
      "spawns" => [%{"id" => "spawn:default", "location" => "pn:1", "default" => true}],
      "locations" => [place.("loc:a", "Corner A", "pn:1"), place.("loc:b", "Corner B", "pn:2")]
    })
  end

  def world(overrides \\ %{}) do
    dir = Path.join(Threshold.World.root(), "tiny")
    load = fn file -> dir |> Path.join(file) |> File.read!() |> Jason.decode!() end

    {:ok, world} =
      World.new(
        "tiny",
        load.("generated/playable.json"),
        load.("generated/edges.geojson")["features"],
        load.("boundary.geojson")["geometry"],
        Map.merge(authored(), overrides)
      )

    world
  end
end
