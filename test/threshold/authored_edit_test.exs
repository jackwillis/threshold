defmodule Threshold.Authored.EditTest do
  use ExUnit.Case, async: true

  alias Threshold.Authored
  alias Threshold.Authored.Edit

  @geography %{
    nodes: %{"node:1" => [-89.385, 43.074], "node:2" => [-89.38, 43.075]},
    edges: %{"edge:1-2-101" => "hash101", "edge:3-4-102" => "hash102"}
  }

  defp empty, do: Authored.empty()

  defp with_location(request \\ %{"kind" => "point", "point" => [-89.38, 43.07]}) do
    {:ok, doc, id} = Edit.add_location(empty(), request, @geography)
    {doc, id}
  end

  test "spawn marks are idempotent and switching defaults preserves their identities" do
    assert {:ok, first} = Edit.add_spawn(empty(), "pn:1")
    assert [%{"default" => true, "id" => first_id}] = first["spawns"]
    assert {:ok, ^first} = Edit.add_spawn(first, "pn:1")
    assert {:ok, both} = Edit.add_spawn(first, "pn:2")
    assert [%{"id" => ^first_id}, %{"default" => false, "id" => second_id}] = both["spawns"]
    assert {:ok, chosen} = Edit.set_default_spawn(both, "pn:2")

    assert [%{"id" => ^first_id, "default" => false}, %{"id" => ^second_id, "default" => true}] =
             chosen["spawns"]

    assert {:ok, removed} = Edit.remove_spawn(chosen, "pn:2")
    assert [%{"id" => ^first_id, "default" => false}] = removed["spawns"]
    assert {:ok, _} = Edit.set_default_spawn(removed, "pn:1")
    assert {:error, _} = Edit.add_spawn(empty(), "invented-point")
  end

  test "closure reconnect rejects absent and already closed targets" do
    {:ok, doc, first} = Edit.add_closure(empty(), "edge:1-2-101", @geography)
    {:ok, doc, _} = Edit.add_closure(doc, "edge:3-4-102", @geography)

    assert {:error, "That street already has a closure."} =
             Edit.reconnect_closure(doc, first, "edge:3-4-102", @geography)

    assert {:error, "That street is not in the imported geography."} =
             Edit.reconnect_closure(doc, first, "edge:gone", @geography)

    assert {:error, "No such closure."} =
             Edit.reconnect_closure(doc, "clo:gone", "edge:1-2-101", @geography)
  end

  describe "locations" do
    test "adds a free point, a node and an edge anchor" do
      {doc, id} = with_location()

      assert [%{"id" => ^id, "name" => "New location", "anchor" => %{"kind" => "point"}}] =
               doc["locations"]

      {:ok, doc, _} =
        Edit.add_location(
          doc,
          %{"kind" => "node", "ref" => "node:1", "point" => [0, 0]},
          @geography
        )

      assert %{"anchor" => %{"kind" => "node", "ref" => "node:1", "point" => [-89.385, 43.074]}} =
               List.last(doc["locations"])

      req = %{
        "kind" => "edge",
        "ref" => "edge:1-2-101",
        "offset" => 0.4,
        "point" => [-89.383, 43.0744]
      }

      {:ok, doc, _} = Edit.add_location(doc, req, @geography)

      assert %{"anchor" => %{"ref_geometry_hash" => "hash101", "offset" => 0.4}} =
               List.last(doc["locations"])
    end

    test "node positions and edge hashes come from the geography, not the client" do
      req = %{
        "kind" => "node",
        "ref" => "node:2",
        "point" => [10, 10],
        "ref_geometry_hash" => "forged"
      }

      {:ok, doc, _} = Edit.add_location(empty(), req, @geography)
      assert [%{"anchor" => %{"point" => [-89.38, 43.075]}}] = doc["locations"]
    end

    test "unknown references and malformed positions are rejected" do
      assert {:error, "That intersection" <> _} =
               Edit.add_location(empty(), %{"kind" => "node", "ref" => "node:99"}, @geography)

      assert {:error, "That street" <> _} =
               Edit.add_location(
                 empty(),
                 %{"kind" => "edge", "ref" => "edge:0", "offset" => 0.5, "point" => [0, 0]},
                 @geography
               )

      assert {:error, "Could not understand" <> _} =
               Edit.add_location(empty(), %{"kind" => "teleport"}, @geography)

      assert {:error, "Edit rejected" <> _} =
               Edit.add_location(empty(), %{"kind" => "point", "point" => [500, 0]}, @geography)
    end

    test "edge offsets are clamped" do
      req = %{
        "kind" => "edge",
        "ref" => "edge:1-2-101",
        "offset" => 3,
        "point" => [-89.38, 43.07]
      }

      {:ok, doc, _} = Edit.add_location(empty(), req, @geography)
      assert [%{"anchor" => %{"offset" => 1}}] = doc["locations"]
    end

    test "rename and notes" do
      {doc, id} = with_location()

      {:ok, doc} =
        Edit.update_location(doc, id, %{"name" => "Annex", "notes" => "hidden", "ignored" => "x"})

      assert [%{"name" => "Annex", "notes" => "hidden"}] = doc["locations"]

      assert {:error, "No such location."} =
               Edit.update_location(doc, "loc:nope", %{"name" => "x"})
    end

    test "moving re-resolves the anchor, which reconnects a detached location" do
      {doc, id} = with_location()

      {:ok, doc} =
        Edit.move_location(
          doc,
          id,
          %{"kind" => "node", "ref" => "node:1", "point" => [0, 0]},
          @geography
        )

      assert [%{"anchor" => %{"kind" => "node", "ref" => "node:1"}}] = doc["locations"]
    end

    test "detaching keeps the fictional location at its recorded position" do
      {doc, id} = with_location(%{"kind" => "node", "ref" => "node:1", "point" => [0, 0]})
      {:ok, doc} = Edit.detach_location(doc, id)

      assert [%{"anchor" => %{"kind" => "point", "point" => [-89.385, 43.074]}}] =
               doc["locations"]
    end

    test "deleting a location also removes its connections and reports them" do
      {doc, a} = with_location()

      {:ok, doc, b} =
        Edit.add_location(doc, %{"kind" => "point", "point" => [-89.381, 43.071]}, @geography)

      {:ok, doc, conn} = Edit.add_connection(doc, a, b)

      assert {:ok, doc, [^conn]} = Edit.delete_location(doc, a)
      assert [%{"id" => ^b}] = doc["locations"]
      assert doc["connections"] == []
      assert {:error, "No such location."} = Edit.delete_location(doc, a)
    end
  end

  describe "connections" do
    setup do
      {doc, a} = with_location()

      {:ok, doc, b} =
        Edit.add_location(doc, %{"kind" => "point", "point" => [-89.381, 43.071]}, @geography)

      %{doc: doc, a: a, b: b}
    end

    test "connects two different locations once, in either direction", %{doc: doc, a: a, b: b} do
      {:ok, doc, id} = Edit.add_connection(doc, a, b)
      assert [%{"id" => ^id, "kind" => "fictional"}] = doc["connections"]
      assert {:error, "Those locations are already connected."} = Edit.add_connection(doc, b, a)

      assert {:error, "A connection needs two different locations."} =
               Edit.add_connection(doc, a, a)
    end

    test "rejects a connection to a location that does not exist", %{doc: doc, a: a} do
      assert {:error, "Edit rejected" <> _} = Edit.add_connection(doc, a, "loc:ghost")
    end

    test "notes can be edited and the connection deleted", %{doc: doc, a: a, b: b} do
      {:ok, doc, id} = Edit.add_connection(doc, a, b)
      {:ok, doc} = Edit.update_connection(doc, id, %{"notes" => "secret door"})
      assert [%{"notes" => "secret door"}] = doc["connections"]
      {:ok, doc} = Edit.delete(doc, "connections", id)
      assert doc["connections"] == []
      assert {:error, "Nothing to delete."} = Edit.delete(doc, "connections", id)
    end
  end

  describe "playable overrides" do
    test "records, replaces and clears a decision" do
      {:ok, doc} = Edit.set_playable_override(empty(), "pn:5", "retain")
      assert [%{"id" => "pn:5", "action" => "retain"}] = doc["playable_overrides"]

      {:ok, doc} = Edit.set_playable_override(doc, "pn:5", "suppress")
      assert [%{"id" => "pn:5", "action" => "suppress"}] = doc["playable_overrides"]

      {:ok, doc} = Edit.set_playable_override(doc, "pn:5", nil)
      assert doc["playable_overrides"] == []
    end

    test "rejects malformed ids and actions" do
      assert {:error, "Edit rejected" <> _} =
               Edit.set_playable_override(empty(), "node:5", "retain")

      assert {:error, "Edit rejected" <> _} =
               Edit.set_playable_override(empty(), "pn:5", "delete")
    end
  end

  describe "closures" do
    test "closes an imported edge using the geography's shape hash" do
      {:ok, doc, id} = Edit.add_closure(empty(), "edge:3-4-102", @geography)

      assert [
               %{
                 "id" => ^id,
                 "kind" => "restricted",
                 "geometry_hash" => "hash102",
                 "reason" => ""
               }
             ] = doc["closures"]
    end

    test "closing an already closed edge returns the existing closure" do
      {:ok, doc, id} = Edit.add_closure(empty(), "edge:3-4-102", @geography)
      assert {:ok, ^doc, ^id} = Edit.add_closure(doc, "edge:3-4-102", @geography)
    end

    test "unknown edges cannot be closed" do
      assert {:error, "That edge is not in the imported geography."} =
               Edit.add_closure(empty(), "edge:9-9-9", @geography)
    end

    test "reason can be edited and the closure deleted" do
      {:ok, doc, id} = Edit.add_closure(empty(), "edge:3-4-102", @geography)
      {:ok, doc} = Edit.update_closure(doc, id, %{"reason" => "locked gate"})
      assert [%{"reason" => "locked gate"}] = doc["closures"]
      {:ok, doc} = Edit.delete(doc, "closures", id)
      assert doc["closures"] == []
    end
  end
end
