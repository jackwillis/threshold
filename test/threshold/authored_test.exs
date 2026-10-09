defmodule Threshold.AuthoredTest do
  use ExUnit.Case, async: true

  alias Threshold.Authored

  @moduletag :tmp_dir

  defp doc(overrides \\ %{}) do
    Map.merge(
      %{
        "format_version" => 1,
        "locations" => [
          %{
            "id" => "loc:a1",
            "name" => "Corner",
            "anchor" => %{"kind" => "node", "ref" => "node:1", "point" => [-89.385, 43.074]}
          },
          %{
            "id" => "loc:b2",
            "name" => "Mid-block",
            "notes" => "n",
            "anchor" => %{
              "kind" => "edge",
              "ref" => "edge:1-2-101",
              "offset" => 0.5,
              "point" => [-89.3825, 43.0745],
              "ref_geometry_hash" => "deadbeef"
            }
          },
          %{
            "id" => "loc:c3",
            "name" => "Nowhere",
            "anchor" => %{"kind" => "point", "point" => [-89.38, 43.07]}
          }
        ],
        "connections" => [
          %{"id" => "conn:x1", "from" => "loc:a1", "to" => "loc:c3", "kind" => "fictional"}
        ],
        "closures" => [
          %{
            "id" => "clo:y1",
            "edge" => "edge:3-4-102",
            "kind" => "restricted",
            "geometry_hash" => "deadbeef",
            "reason" => "locked gate"
          }
        ]
      },
      overrides
    )
  end

  defp errors(data), do: elem(Authored.validate(data), 1)

  test "a complete document validates and defaults are filled in" do
    assert {:ok, normalized} = Authored.validate(doc())
    assert [%{"notes" => ""}, %{"notes" => "n"}, %{"notes" => ""}] = normalized["locations"]
    assert [%{"notes" => "", "geometry" => nil}] = normalized["connections"]
  end

  test "the empty document is valid" do
    assert {:ok, _} = Authored.validate(Authored.empty())
  end

  describe "playable_overrides" do
    test "are optional and default to empty" do
      {:ok, normalized} = Authored.validate(doc())
      assert normalized["playable_overrides"] == []
    end

    test "accept retain and suppress" do
      overrides = [
        %{"id" => "pn:123", "action" => "retain"},
        %{"id" => "pn:456", "action" => "suppress"}
      ]

      assert {:ok, %{"playable_overrides" => ^overrides}} =
               Authored.validate(doc(%{"playable_overrides" => overrides}))
    end

    test "reject bad ids, actions, duplicates and extra keys" do
      bad = fn o -> errors(doc(%{"playable_overrides" => o})) end

      assert Enum.any?(
               bad.([%{"id" => "loc:1", "action" => "retain"}]),
               &(&1 =~ "must look like")
             )

      assert Enum.any?(
               bad.([%{"id" => "pn:1", "action" => "delete"}]),
               &(&1 =~ "must be one of retain, suppress")
             )

      assert Enum.any?(
               bad.([
                 %{"id" => "pn:1", "action" => "retain"},
                 %{"id" => "pn:1", "action" => "suppress"}
               ]),
               &(&1 =~ "duplicate id")
             )

      assert Enum.any?(
               bad.([%{"id" => "pn:1", "action" => "retain", "why" => "x"}]),
               &(&1 =~ "unknown key")
             )

      assert ["playable_overrides: must be a list"] = bad.("nope")
    end

    test "are written sorted by id" do
      {:ok, d} =
        Authored.validate(
          doc(%{
            "playable_overrides" => [
              %{"id" => "pn:9", "action" => "retain"},
              %{"id" => "pn:2", "action" => "suppress"}
            ]
          })
        )

      assert Authored.encode(d) =~ ~r/"pn:2".*"pn:9"/s
    end
  end

  test "reports a wrong or missing version" do
    assert ["format_version: unsupported version 2" <> _] = errors(doc(%{"format_version" => 2}))
    assert "format_version: missing" in errors(Map.delete(doc(), "format_version"))
  end

  test "unknown keys are errors so typos cannot hide" do
    data =
      doc(%{
        "locations" => [
          %{
            "id" => "loc:a1",
            "name" => "x",
            "nmae" => "typo",
            "anchor" => %{"kind" => "point", "point" => [0, 0]}
          }
        ]
      })

    assert ~s(locations[0]: unknown key "nmae") in errors(data)
  end

  test "anchor problems are specific" do
    bad = fn anchor ->
      errors(doc(%{"locations" => [%{"id" => "loc:a1", "name" => "x", "anchor" => anchor}]}))
    end

    assert ["locations[0].anchor.kind: \"wall\" is not one of node, edge, point"] =
             bad.(%{"kind" => "wall"})

    assert Enum.any?(
             bad.(%{"kind" => "point", "point" => [200, 0]}),
             &(&1 =~ "[longitude, latitude]")
           )

    assert Enum.any?(
             bad.(%{"kind" => "node", "ref" => "edge:1", "point" => [0, 0]}),
             &(&1 =~ "must be a node id")
           )

    off = %{
      "kind" => "edge",
      "ref" => "edge:1-2-3",
      "offset" => 1.5,
      "point" => [0, 0],
      "ref_geometry_hash" => "h"
    }

    assert Enum.any?(bad.(off), &(&1 =~ "between 0 and 1"))
  end

  test "duplicate ids, bad id formats and dangling connections are reported" do
    dup = doc(%{"closures" => [Enum.at(doc()["closures"], 0), Enum.at(doc()["closures"], 0)]})
    assert ~s(closures: duplicate id "clo:y1") in errors(dup)

    assert Enum.any?(
             errors(
               doc(%{
                 "closures" => [
                   %{
                     "id" => "nope",
                     "edge" => "edge:1",
                     "kind" => "restricted",
                     "geometry_hash" => "h"
                   }
                 ]
               })
             ),
             &(&1 =~ "closures[0].id")
           )

    dangling =
      doc(%{
        "connections" => [
          %{"id" => "conn:x1", "from" => "loc:a1", "to" => "loc:zz", "kind" => "fictional"}
        ]
      })

    assert ~s(connections[0].to: no location "loc:zz") in errors(dangling)

    self_loop =
      doc(%{
        "connections" => [
          %{"id" => "conn:x1", "from" => "loc:a1", "to" => "loc:a1", "kind" => "fictional"}
        ]
      })

    assert Enum.any?(errors(self_loop), &(&1 =~ "must be different"))
  end

  test "connection geometry is reserved" do
    conn = %{
      "id" => "conn:x1",
      "from" => "loc:a1",
      "to" => "loc:c3",
      "kind" => "fictional",
      "geometry" => %{}
    }

    assert Enum.any?(errors(doc(%{"connections" => [conn]})), &(&1 =~ "not supported yet"))
  end

  test "non-object documents are rejected" do
    assert {:error, ["document: must be a JSON object"]} = Authored.validate([])
  end

  test "encoding is deterministic, sorted and round-trips", %{tmp_dir: dir} do
    {:ok, valid} = Authored.validate(doc())
    shuffled = Map.update!(valid, "locations", &Enum.reverse/1)
    assert Authored.encode(valid) == Authored.encode(shuffled)

    File.write!(Path.join(dir, "authored.json"), Authored.encode(valid))
    assert {:ok, ^valid, hash} = Authored.load(dir)
    assert hash == Authored.hash(Authored.encode(valid))
    assert Authored.encode(valid) =~ ~r/\n\z/
  end

  describe "load/1" do
    test "reports unreadable and malformed files", %{tmp_dir: dir} do
      assert {:error, ["authored.json: cannot read" <> _]} = Authored.load(dir)
      File.write!(Path.join(dir, "authored.json"), "{nope")
      assert {:error, ["authored.json: invalid JSON" <> _]} = Authored.load(dir)
    end
  end

  describe "save/3" do
    setup %{tmp_dir: dir} do
      File.write!(Path.join(dir, "authored.json"), Authored.encode(Authored.empty()))
      {:ok, _, hash} = Authored.load(dir)
      %{hash: hash}
    end

    test "writes atomically and returns the new hash", %{tmp_dir: dir, hash: hash} do
      {:ok, new_doc} = Authored.validate(doc())
      assert {:ok, new_hash} = Authored.save(dir, new_doc, hash)
      assert new_hash != hash
      assert {:ok, ^new_doc, ^new_hash} = Authored.load(dir)
      refute File.exists?(Path.join(dir, "authored.json.tmp"))
    end

    test "refuses to overwrite a file that changed since it was loaded", %{
      tmp_dir: dir,
      hash: hash
    } do
      {:ok, new_doc} = Authored.validate(doc())
      File.write!(Path.join(dir, "authored.json"), Authored.encode(new_doc))
      before = File.read!(Path.join(dir, "authored.json"))

      assert {:error, :conflict} = Authored.save(dir, Authored.empty(), hash)
      assert File.read!(Path.join(dir, "authored.json")) == before
    end

    test "refuses invalid documents and leaves the file alone", %{tmp_dir: dir, hash: hash} do
      before = File.read!(Path.join(dir, "authored.json"))
      assert {:error, [_ | _]} = Authored.save(dir, %{"format_version" => 1}, hash)
      assert File.read!(Path.join(dir, "authored.json")) == before
    end
  end
end
