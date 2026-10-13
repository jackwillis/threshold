defmodule Threshold.AuthoredInteractionsTest do
  use ExUnit.Case, async: true

  alias Threshold.{Authored, Interactions}

  @moduletag :tmp_dir
  @tiny Path.expand("../fixtures/worlds/tiny", __DIR__)

  setup %{tmp_dir: tmp} do
    dir = Path.join(tmp, "tiny")
    File.cp_r!(@tiny, dir)
    {:ok, authored, _} = Authored.load(dir)

    place = %{
      "id" => "loc:scene",
      "name" => "Scene place",
      "anchor" => %{"kind" => "node", "ref" => "node:1", "point" => [-89.385, 43.074]}
    }

    authored = Map.put(authored, "locations", [place])
    File.write!(Path.join(dir, "authored.json"), Authored.encode(authored))

    interactions = %{
      "format_version" => 1,
      "discoveries" => [%{"id" => "disc:clue", "label" => "A clue"}],
      "interactions" =>
        for id <- ["int:first", "int:second"] do
          %{
            "id" => id,
            "place" => "loc:scene",
            "title" => "Investigate",
            "requires" => [],
            "scene" => %{"title" => "Scene", "body" => ["A fixture scene."]},
            "choices" => [%{"id" => "read", "label" => "Read", "discovers" => ["disc:clue"]}]
          }
        end
    }

    File.write!(Path.join(dir, "interactions.json"), Interactions.encode(interactions))
    {:ok, _, hash} = Authored.load(dir)
    %{dir: dir, authored: authored, hash: hash, interactions: interactions}
  end

  test "deleting a referenced place rejects the save and names every interaction", ctx do
    before = bytes(ctx.dir)
    deleted = Map.put(ctx.authored, "locations", [])

    assert {:error, errors} = Authored.save(ctx.dir, deleted, ctx.hash)
    assert length(errors) == 2
    assert Enum.any?(errors, &(&1 =~ "int:first" and &1 =~ "loc:scene"))
    assert Enum.any?(errors, &(&1 =~ "int:second" and &1 =~ "loc:scene"))
    assert bytes(ctx.dir) == before
    assert Path.wildcard(Path.join(ctx.dir, "*.tmp")) == []
  end

  test "changing a stable id rejects orphan references without repairing them", ctx do
    before = bytes(ctx.dir)
    changed = put_in(ctx.authored, ["locations", Access.at(0), "id"], "loc:replacement")

    assert {:error, errors} = Authored.save(ctx.dir, changed, ctx.hash)
    assert Enum.any?(errors, &(&1 =~ "int:first"))
    assert Enum.any?(errors, &(&1 =~ "int:second"))
    assert bytes(ctx.dir) == before
  end

  test "display name and notes changes save normally with no advisory result", ctx do
    interactions_before = File.read!(Path.join(ctx.dir, "interactions.json"))

    changed =
      ctx.authored
      |> put_in(["locations", Access.at(0), "name"], "Renamed display")
      |> put_in(["locations", Access.at(0), "notes"], "Updated fixture notes")

    assert {:ok, new_hash} = Authored.save(ctx.dir, changed, ctx.hash)
    assert new_hash != ctx.hash
    assert {:ok, ^changed, ^new_hash} = Authored.load(ctx.dir)
    assert File.read!(Path.join(ctx.dir, "interactions.json")) == interactions_before
  end

  test "effects granting undeclared discoveries reject save and preserve both files", ctx do
    invalid =
      put_in(
        ctx.interactions,
        ["interactions", Access.at(0), "choices", Access.at(0), "discovers"],
        [
          "disc:undeclared"
        ]
      )

    File.write!(Path.join(ctx.dir, "interactions.json"), Interactions.encode(invalid))
    before = bytes(ctx.dir)

    assert {:error, errors} = Authored.save(ctx.dir, ctx.authored, ctx.hash)
    assert Enum.any?(errors, &(&1 =~ "disc:undeclared" and &1 =~ "not a declared discovery"))
    assert bytes(ctx.dir) == before
  end

  test "malformed sibling JSON prevents saving without replacing either file", ctx do
    File.write!(Path.join(ctx.dir, "interactions.json"), "{broken")
    before = bytes(ctx.dir)
    assert {:error, errors} = Authored.save(ctx.dir, ctx.authored, ctx.hash)
    assert Enum.any?(errors, &(&1 =~ "interactions.json: invalid JSON"))
    assert bytes(ctx.dir) == before
  end

  test "a stale base still returns conflict before sibling validation", ctx do
    changed = put_in(ctx.authored, ["locations", Access.at(0), "name"], "Other writer")
    File.write!(Path.join(ctx.dir, "authored.json"), Authored.encode(changed))
    File.write!(Path.join(ctx.dir, "interactions.json"), "{broken")
    before = bytes(ctx.dir)

    assert {:error, :conflict} = Authored.save(ctx.dir, ctx.authored, ctx.hash)
    assert bytes(ctx.dir) == before
  end

  test "absent and empty interactions allow deleting places", ctx do
    path = Path.join(ctx.dir, "interactions.json")
    File.rm!(path)
    deleted = Map.put(ctx.authored, "locations", [])
    assert {:ok, new_hash} = Authored.save(ctx.dir, deleted, ctx.hash)
    refute File.exists?(path)

    File.write!(path, Interactions.encode(Interactions.empty()))
    assert {:ok, _} = Authored.save(ctx.dir, ctx.authored, new_hash)
  end

  test "valid sibling content retains one winner for competing saves", ctx do
    results =
      1..8
      |> Enum.map(fn writer ->
        Task.async(fn ->
          changed = put_in(ctx.authored, ["locations", Access.at(0), "name"], "Writer #{writer}")
          Authored.save(ctx.dir, changed, ctx.hash)
        end)
      end)
      |> Task.await_many(60_000)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :conflict})) == 7
    assert {:ok, _, _} = Authored.load(ctx.dir)
    assert {:ok, interactions, _} = Interactions.load(ctx.dir)
    assert interactions == ctx.interactions
    assert Path.wildcard(Path.join(ctx.dir, "*.tmp")) == []
  end

  defp bytes(dir) do
    for name <- ["authored.json", "interactions.json"], into: %{} do
      {name, File.read!(Path.join(dir, name))}
    end
  end
end
