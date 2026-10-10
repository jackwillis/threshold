defmodule ThresholdWeb.EditorEditingTest do
  use ThresholdWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Threshold.Authored

  @moduletag :tmp_dir

  @square [
    [-89.389, 43.072],
    [-89.372, 43.072],
    [-89.372, 43.078],
    [-89.389, 43.078],
    [-89.389, 43.072]
  ]

  setup %{tmp_dir: tmp} do
    File.cp_r!(Path.join(Threshold.World.root(), "tiny"), Path.join(tmp, "tiny"))
    previous = Application.get_env(:threshold, :worlds_dir)
    Application.put_env(:threshold, :worlds_dir, tmp)
    on_exit(fn -> Application.put_env(:threshold, :worlds_dir, previous) end)
    %{dir: Path.join(tmp, "tiny")}
  end

  defp state(view) do
    [_, encoded] = Regex.run(~r/data-state="([^"]*)"/, view |> element("#map-hook") |> render())
    encoded |> String.replace("&quot;", "\"") |> String.replace("&amp;", "&") |> Jason.decode!()
  end

  defp dom_id(id), do: String.replace(id, ":", "-")

  defp saved(dir), do: dir |> Path.join("authored.json") |> File.read!() |> Jason.decode!()

  defp place(view, anchor \\ %{"kind" => "point", "point" => [-89.38, 43.071]}) do
    render_hook(view, "add_location", %{"anchor" => anchor})
    [%{"id" => id} | _] = Enum.reverse(state(view)["authored"]["locations"])
    id
  end

  test "default spawn and explicit nearby attachment are authored changes", %{
    conn: conn,
    dir: dir
  } do
    {:ok, view, _} = live(conn, ~p"/")
    render_hook(view, "set_default_spawn", %{"id" => "pn:1"})
    assert [%{"location" => "pn:1", "default" => true}] = state(view)["authored"]["spawns"]
    render_hook(view, "set_default_spawn", %{"id" => "pn:999"})
    assert [%{"location" => "pn:1"}] = state(view)["authored"]["spawns"]
    id = place(view)

    view
    |> form("#location-form-#{dom_id(id)}", location: %{id: id, movement_location: "pn:2"})
    |> render_change()

    assert [%{"movement_location" => "pn:2"}] = state(view)["authored"]["locations"]

    render_hook(view, "update_location", %{
      "location" => %{"id" => id, "movement_location" => "pn:999"}
    })

    assert [%{"movement_location" => "pn:2"}] = state(view)["authored"]["locations"]
    view |> element("#save-button") |> render_click()
    assert [%{"location" => "pn:1"}] = saved(dir)["spawns"]
    assert [%{"movement_location" => "pn:2"}] = saved(dir)["locations"]
  end

  test "spawn UI marks several points, switches default, removes marks and saves", %{
    conn: conn,
    dir: dir
  } do
    {:ok, view, _} = live(conn, ~p"/")
    view |> element("#choose-spawn") |> render_click()
    assert state(view)["layers"]["playable"]

    pick = fn id ->
      render_hook(view, "pick", %{
        "layer" => "playable-location",
        "id" => id,
        "properties" => %{"degree" => 1, "members" => 1, "component" => 0, "reasons" => []}
      })
    end

    pick.("pn:1")
    view |> element("#mark-spawn") |> render_click()
    assert [%{"location" => "pn:1", "default" => true}] = state(view)["authored"]["spawns"]
    refute has_element?(view, "#mark-spawn")
    assert has_element?(view, "#remove-spawn")
    pick.("pn:2")
    view |> element("#mark-spawn") |> render_click()
    view |> element("#set-default-spawn") |> render_click()

    assert [
             %{"location" => "pn:1", "default" => false},
             %{"location" => "pn:2", "default" => true}
           ] = state(view)["authored"]["spawns"]

    view |> element("#remove-spawn") |> render_click()
    assert has_element?(view, "#spawn-default-warning")
    pick.("pn:1")
    view |> element("#set-default-spawn") |> render_click()
    render_hook(view, "add_spawn", %{"id" => "pn:999"})
    assert length(state(view)["authored"]["spawns"]) == 1
    view |> element("#save-button") |> render_click()
    assert [%{"location" => "pn:1", "default" => true}] = saved(dir)["spawns"]
    {:ok, restored, _} = live(build_conn(), ~p"/")
    assert has_element?(restored, "#spawn-points", "pn:1")
  end

  test "tools are listed and the inspect tool is active at first", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#tool-inspect.tool-active")
    assert has_element?(view, "#tool-hint", "Click a feature")
    assert has_element?(view, "#dirty-indicator", "All changes saved")
  end

  test "switching tools updates the mode sent to the map and the hint", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    view |> element("#tool-place") |> render_click()
    assert state(view)["mode"] == "place"
    assert has_element?(view, "#tool-hint", "place a location")
  end

  test "placing a location creates an unsaved change and selects it", %{conn: conn, dir: dir} do
    {:ok, view, _} = live(conn, ~p"/")
    id = place(view)

    assert state(view)["selected"] == id
    assert state(view)["dirty"] == true
    assert has_element?(view, "#dirty-indicator", "Unsaved changes")
    assert has_element?(view, "#inspector input[name='location[name]'][value='New location']")
    # Nothing is written until Save.
    assert saved(dir)["locations"] == []
  end

  test "a node anchor takes its position from the geography, not the client", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    place(view, %{"kind" => "node", "ref" => "node:2", "point" => [0, 0]})

    assert [%{"anchor" => %{"point" => [-89.38, 43.075], "ref" => "node:2"}}] =
             state(view)["authored"]["locations"]
  end

  test "renaming through the inspector updates the working copy", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    id = place(view)

    view
    |> form("#location-form-#{dom_id(id)}",
      location: %{id: id, name: "Annex", notes: "behind the bar"}
    )
    |> render_change()

    assert [%{"name" => "Annex", "notes" => "behind the bar"}] =
             state(view)["authored"]["locations"]
  end

  test "save writes the file and clears the unsaved state", %{conn: conn, dir: dir} do
    {:ok, view, _} = live(conn, ~p"/")
    id = place(view)

    view
    |> form("#location-form-#{dom_id(id)}", location: %{id: id, name: "Annex"})
    |> render_change()

    view |> element("#save-button") |> render_click()

    assert [%{"name" => "Annex"}] = saved(dir)["locations"]
    assert state(view)["dirty"] == false
    assert has_element?(view, "#dirty-indicator", "All changes saved")
    assert render(view) =~ "Authored layer saved."
  end

  test "discard throws away unsaved edits", %{conn: conn, dir: dir} do
    {:ok, view, _} = live(conn, ~p"/")
    place(view)
    view |> element("#discard-button") |> render_click()

    assert state(view)["authored"]["locations"] == []
    assert state(view)["dirty"] == false
    assert saved(dir)["locations"] == []
  end

  test "saving is refused if the file changed on disk, and nothing is overwritten", %{
    conn: conn,
    dir: dir
  } do
    {:ok, view, _} = live(conn, ~p"/")
    place(view)

    {:ok, other} =
      Authored.validate(%{
        Authored.empty()
        | "closures" => [
            %{
              "id" => "clo:other",
              "edge" => "edge:1-2-101",
              "kind" => "restricted",
              "geometry_hash" => "h"
            }
          ]
      })

    File.write!(Path.join(dir, "authored.json"), Authored.encode(other))

    view |> element("#save-button") |> render_click()
    assert render(view) =~ "changed on disk"
    assert [%{"id" => "clo:other"}] = saved(dir)["closures"]
    assert saved(dir)["locations"] == []
    assert state(view)["dirty"] == true
  end

  test "connect tool joins two locations", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    a = place(view)
    b = place(view, %{"kind" => "point", "point" => [-89.381, 43.072]})

    view |> element("#tool-connect") |> render_click()
    render_hook(view, "pick", %{"layer" => "authored-location", "id" => a})
    assert state(view)["pendingFrom"] == a
    assert has_element?(view, "#tool-hint", "second location")

    render_hook(view, "pick", %{"layer" => "authored-location", "id" => b})
    assert [%{"from" => ^a, "to" => ^b}] = state(view)["authored"]["connections"]
    assert state(view)["pendingFrom"] == nil
    assert has_element?(view, "#inspector", "authored connection")
  end

  test "connecting a location to itself or twice is refused", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    a = place(view)
    b = place(view, %{"kind" => "point", "point" => [-89.381, 43.072]})
    view |> element("#tool-connect") |> render_click()

    render_hook(view, "pick", %{"layer" => "authored-location", "id" => a})
    render_hook(view, "pick", %{"layer" => "authored-location", "id" => a})
    assert state(view)["authored"]["connections"] == []

    for id <- [a, b, a, b],
        do: render_hook(view, "pick", %{"layer" => "authored-location", "id" => id})

    assert length(state(view)["authored"]["connections"]) == 1
    assert render(view) =~ "already connected"
  end

  test "close tool restricts a street using the geography's shape hash", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    view |> element("#tool-close") |> render_click()
    render_hook(view, "pick", %{"layer" => "edges", "id" => "edge:3-4-102"})

    assert [%{"edge" => "edge:3-4-102", "geometry_hash" => "deadbeef", "kind" => "restricted"}] =
             state(view)["authored"]["closures"]

    assert has_element?(view, "#inspector input[name='closure[reason]']")

    closure_id = hd(state(view)["authored"]["closures"])["id"]

    view
    |> form("#closure-form-#{dom_id(closure_id)}",
      closure: %{id: closure_id, reason: "locked gate"}
    )
    |> render_change()

    assert [%{"reason" => "locked gate"}] = state(view)["authored"]["closures"]
  end

  test "an imported edge's inspector offers to close it, and shows an existing closure", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/")

    render_hook(view, "pick", %{
      "layer" => "edges",
      "id" => "edge:3-4-102",
      "properties" => %{"id" => "edge:3-4-102"}
    })

    view |> element("#inspector button", "Close this street") |> render_click()
    assert length(state(view)["authored"]["closures"]) == 1

    render_hook(view, "pick", %{
      "layer" => "edges",
      "id" => "edge:3-4-102",
      "properties" => %{"id" => "edge:3-4-102"}
    })

    assert has_element?(view, "#inspector button", "Closed:")
  end

  test "deleting a location removes its connections and says so", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    a = place(view)
    b = place(view, %{"kind" => "point", "point" => [-89.381, 43.072]})
    view |> element("#tool-connect") |> render_click()
    for id <- [a, b], do: render_hook(view, "pick", %{"layer" => "authored-location", "id" => id})
    render_hook(view, "pick", %{"layer" => "authored-location", "id" => a})
    # Back to inspect, select a, delete it.
    view |> element("#tool-inspect") |> render_click()
    render_hook(view, "pick", %{"layer" => "authored-location", "id" => a})
    view |> element("#inspector button", "Delete location") |> render_click()

    assert [%{"id" => ^b}] = state(view)["authored"]["locations"]
    assert state(view)["authored"]["connections"] == []
    assert render(view) =~ "along with 1 connection"
  end

  test "keeping a detached location as a free point", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    id = place(view, %{"kind" => "node", "ref" => "node:1", "point" => [0, 0]})
    view |> element("#inspector button", "Keep as free point") |> render_click()

    assert [%{"id" => ^id, "anchor" => %{"kind" => "point"}}] =
             state(view)["authored"]["locations"]
  end

  test "moving a location re-snaps it", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    id = place(view)

    render_hook(view, "move_location", %{
      "id" => id,
      "anchor" => %{"kind" => "node", "ref" => "node:3", "point" => [0, 0]}
    })

    assert [%{"anchor" => %{"kind" => "node", "ref" => "node:3"}}] =
             state(view)["authored"]["locations"]
  end

  describe "boundary" do
    test "editing the boundary is an unsaved change; saving makes the geography stale", %{
      conn: conn,
      dir: dir
    } do
      {:ok, view, _} = live(conn, ~p"/")
      refute has_element?(view, "#stale-banner")

      view |> element("#tool-boundary") |> render_click()
      render_hook(view, "update_boundary", %{"coordinates" => @square})
      assert state(view)["dirty"] == true
      assert state(view)["boundary"]["coordinates"] == [@square]

      view |> element("#save-button") |> render_click()
      assert has_element?(view, "#stale-banner", "Boundary changed")
      assert render(view) =~ "Regenerate geography"

      saved = dir |> Path.join("boundary.geojson") |> File.read!() |> Jason.decode!()
      assert saved["geometry"]["coordinates"] == [@square]
    end

    test "invalid shapes are rejected without changing the working boundary", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      before = state(view)["boundary"]

      render_hook(view, "update_boundary", %{
        "coordinates" => [[0, 0], [2, 2], [2, 0], [0, 2], [0, 0]]
      })

      assert render(view) =~ "cross each other"
      assert state(view)["boundary"] == before
      assert state(view)["dirty"] == false
    end

    test "a boundary beyond snapshot coverage cannot be saved", %{conn: conn, dir: dir} do
      File.write!(
        Path.join(dir, "source/manifest.json"),
        ~s({"sha256": "abc123", "bounds": [-89.3935, 43.0677, -89.3665, 43.0823]})
      )

      {:ok, view, _} = live(conn, ~p"/")

      render_hook(view, "update_boundary", %{
        "coordinates" => [[-89.41, 43.07], [-89.37, 43.07], [-89.37, 43.08], [-89.41, 43.08]]
      })

      view |> element("#save-button") |> render_click()

      assert render(view) =~ "reaches beyond the pinned source snapshot"
      assert state(view)["dirty"] == true
    end
  end

  test "editing is disabled while authored.json is invalid", %{conn: conn, dir: dir} do
    File.write!(Path.join(dir, "authored.json"), "{broken")
    {:ok, view, _} = live(conn, ~p"/")

    assert has_element?(view, "#tool-place[disabled]")
    assert has_element?(view, "#authored-errors", "Editing is disabled")
    render_hook(view, "add_location", %{"anchor" => %{"kind" => "point", "point" => [0, 0]}})
    assert state(view)["authored"]["locations"] == []
    assert File.read!(Path.join(dir, "authored.json")) == "{broken"
  end

  describe "playable layer" do
    test "the panel shows what was built and its integrity", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      assert has_element?(view, "#playable", "4 locations")
      assert has_element?(view, "#playable-integrity", "Components kept: 2/2")
      refute has_element?(view, "#playable-stale")
      assert state(view)["playable"] == "fresh"
      assert state(view)["layers"]["playable"] == false
    end

    test "a stale layer is flagged", %{conn: conn, dir: dir} do
      File.write!(
        Path.join([dir, "generated", "edges.geojson"]),
        ~s({"type":"FeatureCollection","features":[]})
      )

      {:ok, view, _} = live(conn, ~p"/")
      assert has_element?(view, "#playable-stale", "Out of date")
    end

    test "a missing layer says how to build it", %{conn: conn, dir: dir} do
      File.rm!(Path.join([dir, "generated", "playable.json"]))
      {:ok, view, _} = live(conn, ~p"/")
      assert has_element?(view, "#playable", "make build-playable")
      assert state(view)["playable"] == "missing"
    end

    test "retain and suppress decisions are unsaved edits that save with the authored layer", %{
      conn: conn,
      dir: dir
    } do
      {:ok, view, _} = live(conn, ~p"/")

      props = %{
        "id" => "pn:2",
        "reasons" => ["dead_end"],
        "members" => 1,
        "degree" => 1,
        "component" => 0
      }

      render_hook(view, "pick", %{
        "layer" => "playable-location",
        "id" => "pn:2",
        "properties" => props
      })

      assert has_element?(view, "#inspector", "candidate playable location")
      assert has_element?(view, "#inspector", "dead_end")

      view |> element("#inspector button", "Retain") |> render_click()

      assert [%{"id" => "pn:2", "action" => "retain"}] =
               state(view)["authored"]["playable_overrides"]

      assert state(view)["dirty"] == true
      assert has_element?(view, "#playable", "1 designer override")

      view |> element("#inspector button", "Suppress") |> render_click()
      assert [%{"action" => "suppress"}] = state(view)["authored"]["playable_overrides"]

      view |> element("#save-button") |> render_click()
      assert [%{"id" => "pn:2", "action" => "suppress"}] = saved(dir)["playable_overrides"]

      view |> element("#inspector button[phx-value-action=clear]") |> render_click()
      assert state(view)["authored"]["playable_overrides"] == []
    end

    test "overrides that match no current location are listed", %{conn: conn, dir: dir} do
      doc =
        put_in(Authored.empty(), ["playable_overrides"], [
          %{"id" => "pn:999", "action" => "retain"}
        ])

      File.write!(Path.join(dir, "authored.json"), Authored.encode(doc))

      File.write!(
        Path.join([dir, "generated", "playable.json"]),
        [dir, "generated", "playable.json"]
        |> Path.join()
        |> File.read!()
        |> String.replace(~s("overrides_unmatched": []), ~s("overrides_unmatched": ["pn:999"]))
      )

      {:ok, view, _} = live(conn, ~p"/")
      assert has_element?(view, "#playable-unmatched", "pn:999")
    end

    test "a candidate connection shows its details", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      props = %{
        "id" => "pc:1-2",
        "length_m" => 100.0,
        "classes" => ["street"],
        "parallel" => 1,
        "edge_ids" => ["edge:1-2-101"]
      }

      render_hook(view, "pick", %{
        "layer" => "playable-connection",
        "id" => "pc:1-2",
        "properties" => props
      })

      assert has_element?(view, "#inspector", "candidate playable connection")
      assert has_element?(view, "#inspector", "100.0 m")
    end
  end
end
