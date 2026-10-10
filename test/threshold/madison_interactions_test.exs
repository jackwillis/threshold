defmodule Threshold.MadisonInteractionsTest do
  @moduledoc """
  The Quiet Hour (`priv/worlds/madison/interactions.json`). These tests read only that content file;
  they never read the designer's `authored.json`. The places are the four the designer approved, and
  `mix threshold.interactions madison` lints the file against the real authored world.
  """
  use ExUnit.Case, async: true

  alias Threshold.Game.{Player, World}
  alias Threshold.Interactions

  @path Path.expand("../../priv/worlds/madison/interactions.json", __DIR__)
  @square "loc:b8e5c4e0738c"
  @library "loc:9663ad011a8d"
  @church "loc:d9bff30b26bf"
  @hatch "loc:a6b00c477718"

  setup_all do
    {:ok, doc, _hash} = @path |> File.read!() |> Interactions.parse()
    %{doc: doc}
  end

  # A stand-in authored world containing the four approved places, so the lint's place checks pass
  # without reading the real authored file.
  defp stand_in_authored do
    node = %{"kind" => "node", "ref" => "node:1", "point" => [0, 0]}

    locations =
      for id <- [@square, @library, @church, @hatch],
          do: %{"id" => id, "name" => id, "anchor" => node}

    Map.put(Threshold.Authored.empty(), "locations", locations)
  end

  test "the file is valid and lint-clean", %{doc: doc} do
    assert length(doc["interactions"]) == 7
    assert length(doc["discoveries"]) == 7
    assert [] = Interactions.lint(doc, stand_in_authored())
  end

  test "it uses exactly the four approved places", %{doc: doc} do
    assert doc["interactions"] |> Enum.map(& &1["place"]) |> Enum.uniq() |> Enum.sort() ==
             Enum.sort([@square, @library, @church, @hatch])

    by_place = Enum.group_by(doc["interactions"], & &1["place"], & &1["id"])

    assert Enum.sort(by_place[@square]) == ["int:after-open", "int:after-shut", "int:pulse"]
    assert by_place[@library] == ["int:bulletin"]
    assert Enum.sort(by_place[@church]) == ["int:caretaker-clerk", "int:caretaker-copy"]
    assert by_place[@hatch] == ["int:hatch"]
  end

  test "the scenes name no real institution and the corrected text is in place", %{doc: doc} do
    text = Jason.encode!(doc["interactions"]) <> Jason.encode!(doc["discoveries"])

    for real <- [
          "Central Library",
          "Grace Episcopal",
          "Overture",
          "State Street Maintenance",
          "Capitol Lakes"
        ],
        do: refute(text =~ real)

    refute text =~ "maintenance concourse on State Street"
    assert text =~ "beneath the municipal maintenance concourse"
    assert text =~ "Either way, you will remember which"
    assert text =~ "The Square is where it started"
    assert text =~ "the Square is where you first heard it"
  end

  # --- The whole story, over every order of choices -----------------------------------------

  defp world do
    %World{
      name: "madison:authored",
      graph: :authored,
      locations: Map.new([@square, @library, @church, @hatch], &{&1, %{}})
    }
  end

  defp offered(doc, state) do
    for place <- [@square, @library, @church, @hatch],
        %{interaction: i, status: :available} <-
          Interactions.at(doc, world(), %Player{location: place}, state),
        do: i
  end

  # Depth-first over every available interaction and every choice, returning each final state.
  defp endings(doc, state \\ %{discovered: MapSet.new(), completed: MapSet.new()}) do
    case offered(doc, state) do
      [] ->
        [state]

      available ->
        for i <- available, c <- i["choices"], reduce: [] do
          acc ->
            next = %{
              discovered: MapSet.union(state.discovered, MapSet.new(c["discovers"])),
              completed: MapSet.put(state.completed, i["id"])
            }

            acc ++ endings(doc, next)
        end
    end
    |> Enum.uniq()
  end

  test "every route through the story ends in exactly one closing note", %{doc: doc} do
    finals = endings(doc)
    assert finals != []

    for %{completed: done} <- finals do
      closers = MapSet.intersection(done, MapSet.new(["int:after-open", "int:after-shut"]))
      assert MapSet.size(closers) == 1
      assert "int:pulse" in done and "int:bulletin" in done and "int:hatch" in done
      # Exactly one of the two caretaker scenes, matching the library branch.
      assert MapSet.size(
               MapSet.intersection(
                 done,
                 MapSet.new(["int:caretaker-copy", "int:caretaker-clerk"])
               )
             ) == 1
    end

    # Both branches and both endings are reachable.
    all_done = finals |> Enum.flat_map(&MapSet.to_list(&1.completed)) |> MapSet.new()

    assert MapSet.new([
             "int:caretaker-copy",
             "int:caretaker-clerk",
             "int:after-open",
             "int:after-shut"
           ])
           |> MapSet.subset?(all_done)
  end

  test "each branch unlocks the right caretaker scene and no other", %{doc: doc} do
    copy = %{
      discovered: MapSet.new(["disc:pulse", "disc:conduit", "disc:copy"]),
      completed: MapSet.new(["int:pulse", "int:bulletin"])
    }

    clerk = %{
      discovered: MapSet.new(["disc:pulse", "disc:conduit", "disc:clerk"]),
      completed: MapSet.new(["int:pulse", "int:bulletin"])
    }

    assert ["int:caretaker-copy"] =
             for(i <- offered(doc, copy), i["place"] == @church, do: i["id"])

    assert ["int:caretaker-clerk"] =
             for(i <- offered(doc, clerk), i["place"] == @church, do: i["id"])
  end

  test "gating: nothing at B, C or D is offered until its discoveries exist", %{doc: doc} do
    fresh = %{discovered: MapSet.new(), completed: MapSet.new()}
    assert ["int:pulse"] = for(i <- offered(doc, fresh), do: i["id"])
    assert [] = for(i <- offered(doc, fresh), i["place"] in [@library, @church, @hatch], do: i)

    after_pulse = %{discovered: MapSet.new(["disc:pulse"]), completed: MapSet.new(["int:pulse"])}
    assert ["int:bulletin"] = for(i <- offered(doc, after_pulse), do: i["id"])

    with_key = %{
      discovered: MapSet.new(["disc:pulse", "disc:conduit", "disc:copy", "disc:key"]),
      completed: MapSet.new(["int:pulse", "int:bulletin", "int:caretaker-copy"])
    }

    assert ["int:hatch"] = for(i <- offered(doc, with_key), do: i["id"])
  end

  test "the hatch choices lead to different closing notes", %{doc: doc} do
    base = %{
      discovered: MapSet.new(["disc:key"]),
      completed: MapSet.new(["int:pulse", "int:hatch"])
    }

    opened = %{base | discovered: MapSet.put(base.discovered, "disc:threshold")}
    shut = %{base | discovered: MapSet.put(base.discovered, "disc:marked")}
    assert ["int:after-open"] = for(i <- offered(doc, opened), do: i["id"])
    assert ["int:after-shut"] = for(i <- offered(doc, shut), do: i["id"])
  end
end
