defmodule Threshold.InteractionsTest do
  use ExUnit.Case, async: true

  alias Threshold.{Authored, Interactions}

  @fixture Path.expand("../fixtures/interactions/synthetic.json", __DIR__)

  defp fixture, do: @fixture |> File.read!() |> Jason.decode!()

  defp errors(doc) do
    assert {:error, errors} = Interactions.validate(doc)
    errors
  end

  defp authored(places) do
    locations =
      for {id, kind} <- places do
        anchor =
          case kind do
            :node -> %{"kind" => "node", "ref" => "node:1", "point" => [0, 0]}
            :free -> %{"kind" => "point", "point" => [0, 0]}
          end

        %{"id" => id, "name" => id, "anchor" => anchor}
      end

    %{Authored.empty() | "locations" => locations}
  end

  describe "validation" do
    test "the synthetic fixture and the empty document are valid" do
      assert {:ok, _} = Interactions.validate(fixture())
      assert {:ok, _} = Interactions.validate(Interactions.empty())
    end

    test "unknown keys, a bad version and a non-object are rejected" do
      assert Enum.any?(errors(Map.put(fixture(), "extra", 1)), &(&1 =~ "unknown key \"extra\""))

      assert Enum.any?(
               errors(%{fixture() | "format_version" => 2}),
               &(&1 =~ "unsupported version")
             )

      assert {:error, ["document: must be a JSON object"]} = Interactions.validate([])

      doc = update_in(fixture(), ["interactions", Access.at(0)], &Map.put(&1, "oops", true))
      assert Enum.any?(errors(doc), &(&1 =~ "interactions[0]: unknown key \"oops\""))
    end

    test "id formats are enforced" do
      doc =
        fixture()
        |> put_in(["discoveries", Access.at(0), "id"], "tapping")
        |> put_in(["interactions", Access.at(0), "id"], "door")
        |> put_in(["interactions", Access.at(0), "place"], "a")
        |> put_in(["interactions", Access.at(0), "choices", Access.at(0), "id"], "Not Valid")

      messages = errors(doc)
      assert Enum.any?(messages, &(&1 =~ "discoveries[0].id"))
      assert Enum.any?(messages, &(&1 =~ "interactions[0].id"))
      assert Enum.any?(messages, &(&1 =~ "interactions[0].place"))
      assert Enum.any?(messages, &(&1 =~ "choices[0].id"))
    end

    test "duplicate ids are reported" do
      doc = update_in(fixture()["interactions"], &(&1 ++ [hd(&1)]))
      assert Enum.any?(errors(doc), &(&1 =~ "duplicate id \"int:door\""))

      doc =
        update_in(fixture(), ["interactions", Access.at(0), "choices"], &(&1 ++ [hd(&1)]))

      assert Enum.any?(errors(doc), &(&1 =~ "duplicate choice id \"knock\""))
    end

    test "discoveries must be declared, wherever they are named" do
      required = put_in(fixture(), ["interactions", Access.at(1), "requires"], ["disc:nope"])
      assert [message] = errors(required)
      assert message =~ "interactions[1].requires" and message =~ "not a declared discovery"

      granted =
        put_in(fixture(), ["interactions", Access.at(0), "choices", Access.at(0), "discovers"], [
          "disc:nope"
        ])

      assert [message] = errors(granted)
      assert message =~ "choices[0].discovers"
    end

    test "scenes need a title and at least one paragraph, and an interaction at least one choice" do
      doc = put_in(fixture(), ["interactions", Access.at(0), "scene", "body"], [])
      assert Enum.any?(errors(doc), &(&1 =~ "scene.body"))

      doc = put_in(fixture(), ["interactions", Access.at(0), "scene", "body"], [" "])
      assert Enum.any?(errors(doc), &(&1 =~ "body[0]"))

      doc = put_in(fixture(), ["interactions", Access.at(0), "scene", "title"], "")
      assert Enum.any?(errors(doc), &(&1 =~ "scene.title"))

      doc = put_in(fixture(), ["interactions", Access.at(0), "choices"], [])
      assert Enum.any?(errors(doc), &(&1 =~ "choices: must be a non-empty list"))
    end

    test "requires and discovers must be lists of ids without duplicates" do
      doc = put_in(fixture(), ["interactions", Access.at(1), "requires"], "disc:tapping")
      assert Enum.any?(errors(doc), &(&1 =~ "requires: must be a list"))

      doc =
        put_in(fixture(), ["interactions", Access.at(1), "requires"], [
          "disc:tapping",
          "disc:tapping"
        ])

      assert Enum.any?(errors(doc), &(&1 =~ "duplicate"))
    end
  end

  describe "loading and encoding" do
    @describetag :tmp_dir

    test "a world without interactions.json has none", %{tmp_dir: tmp} do
      assert {:ok, doc, nil} = Interactions.load(tmp)
      assert doc == Interactions.empty()
    end

    test "load returns the validated document and a content hash", %{tmp_dir: tmp} do
      File.cp!(@fixture, Path.join(tmp, "interactions.json"))
      assert {:ok, doc, hash} = Interactions.load(tmp)
      assert doc == fixture()
      assert hash == Authored.hash(File.read!(@fixture))
    end

    test "invalid JSON and invalid content are errors, not crashes", %{tmp_dir: tmp} do
      File.write!(Path.join(tmp, "interactions.json"), "{")
      assert {:error, [message]} = Interactions.load(tmp)
      assert message =~ "invalid JSON"

      File.write!(Path.join(tmp, "interactions.json"), ~s({"format_version": 1}))
      assert {:error, errors} = Interactions.load(tmp)
      assert "document: missing \"discoveries\"" in errors
    end

    test "encoding is deterministic and round-trips; bodies and choices keep their order" do
      doc = fixture()
      reordered = %{doc | "interactions" => Enum.reverse(doc["interactions"])}
      assert Interactions.encode(doc) == Interactions.encode(reordered)

      assert {:ok, parsed, _} = Interactions.parse(Interactions.encode(doc))
      assert parsed == doc
      assert hd(hd(parsed["interactions"])["choices"])["id"] == "knock"
      assert Interactions.encode(doc) =~ "\"format_version\": 1"
    end
  end

  describe "lint" do
    defp kinds(warnings), do: warnings |> Enum.map(&{&1.kind, &1.id}) |> Enum.sort()

    test "the synthetic world with both places walkable has no warnings" do
      assert [] = Interactions.lint(fixture(), authored(%{"loc:a" => :node, "loc:b" => :node}))
    end

    test "a place missing from authored.json is reported, not dropped" do
      warnings = Interactions.lint(fixture(), authored(%{"loc:a" => :node}))
      assert [{:missing_place, "int:lamp"}] = kinds(warnings)
      assert hd(warnings).message =~ "loc:b"
    end

    test "a free point with no walking access is unwalkable; with access it is fine" do
      assert [{:unwalkable_place, "int:lamp"}] =
               kinds(
                 Interactions.lint(fixture(), authored(%{"loc:a" => :node, "loc:b" => :free}))
               )

      doc = authored(%{"loc:a" => :node, "loc:b" => :free})

      doc =
        update_in(doc["locations"], fn [a, b] ->
          [a, Map.put(b, "access", %{"kind" => "node", "ref" => "node:2", "point" => [0, 0]})]
        end)

      assert [] = Interactions.lint(fixture(), doc)
    end

    test "requirements nothing can grant, including circular ones, make an interaction unreachable" do
      places = authored(%{"loc:a" => :node, "loc:b" => :node})

      # int:door is the only thing that grants disc:tapping; make it require disc:tapping itself.
      circular = put_in(fixture(), ["interactions", Access.at(0), "requires"], ["disc:tapping"])

      assert [{:unreachable_interaction, "int:door"}, {:unreachable_interaction, "int:lamp"}] =
               kinds(Interactions.lint(circular, places))

      # Nothing grants it at all.
      ungranted =
        put_in(
          fixture(),
          ["interactions", Access.at(0), "choices", Access.at(0), "discovers"],
          []
        )

      assert {:undiscoverable_discovery, "disc:tapping"} in kinds(
               Interactions.lint(ungranted, places)
             )

      assert {:unreachable_interaction, "int:lamp"} in kinds(Interactions.lint(ungranted, places))
    end

    test "a granted discovery that nothing requires is noted" do
      doc = put_in(fixture(), ["interactions", Access.at(1), "requires"], [])

      assert [{:unused_discovery, "disc:tapping"}] =
               kinds(Interactions.lint(doc, authored(%{"loc:a" => :node, "loc:b" => :node})))
    end
  end
end

defmodule Threshold.InteractionsReadModelTest do
  use ExUnit.Case, async: true

  alias Threshold.{Interactions, InteractionsFixture}
  alias Threshold.Game.Player

  @content InteractionsFixture.content()
  defp state(discovered \\ [], completed \\ []),
    do: %{discovered: MapSet.new(discovered), completed: MapSet.new(completed)}

  defp at(world, location, state),
    do: Interactions.at(@content, world, %Player{location: location}, state)

  defp summary(list), do: Enum.map(list, &{&1.interaction["id"], &1.status})

  test "an interaction with no requirements is available at its place only" do
    world = InteractionsFixture.world()
    assert [{"int:door", :available}] = summary(at(world, "pn:1", state()))
    assert [] = at(world, "pn:2", state())
    assert [] = at(world, "pn:9", state())
  end

  test "an interaction with unmet requirements is hidden, then appears once discovered" do
    world = InteractionsFixture.world()
    assert [] = at(world, "pn:2", state())
    assert [] = at(world, "pn:2", state(["disc:other"]))
    assert [{"int:lamp", :available}] = summary(at(world, "pn:2", state(["disc:tapping"])))
  end

  test "a completed interaction is listed as completed, not available" do
    world = InteractionsFixture.world()

    assert [{"int:door", :completed}] =
             summary(at(world, "pn:1", state(["disc:tapping"], ["int:door"])))
  end

  test "the same rule holds on the authored graph, where the place is the standing node" do
    world = %{
      InteractionsFixture.world()
      | graph: :authored,
        locations: %{"loc:a" => %{}, "loc:b" => %{}}
    }

    assert [{"int:door", :available}] = summary(at(world, "loc:a", state()))
    assert [] = at(world, "loc:b", state())
    assert [{"int:lamp", :available}] = summary(at(world, "loc:b", state(["disc:tapping"])))
  end

  test "an interaction on an unnamed place is still found, though nearby/2 hides the place" do
    # On the authored graph EffectiveGraph lists only places with a name or notes, so `places` is empty.
    world = %{
      InteractionsFixture.world()
      | graph: :authored,
        places: [],
        locations: %{"loc:a" => %{}}
    }

    player = %Player{location: "loc:a"}
    assert [] = Threshold.Game.nearby(world, player)
    assert [{"int:door", :available}] = summary(at(world, "loc:a", state()))
  end
end
