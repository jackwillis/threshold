defmodule ThresholdWeb.EditorReferenceReviewTest do
  use ThresholdWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Threshold.Authored

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    previous = Application.get_env(:threshold, :worlds_dir)
    dir = Path.join(tmp, "tiny")
    File.cp_r!(Path.join(Threshold.World.root(), "tiny"), dir)
    Application.put_env(:threshold, :worlds_dir, tmp)
    on_exit(fn -> Application.put_env(:threshold, :worlds_dir, previous) end)

    doc = %{
      Authored.empty()
      | "locations" => [
          %{
            "id" => "loc:missing",
            "name" => "Annex",
            "notes" => "Preserve this",
            "anchor" => %{"kind" => "node", "ref" => "node:gone", "point" => [-89.38, 43.074]}
          },
          %{
            "id" => "loc:moved",
            "name" => "Moved",
            "notes" => "",
            "anchor" => %{"kind" => "node", "ref" => "node:2", "point" => [-89.38, 43.074]}
          }
        ],
        "closures" => [
          %{
            "id" => "clo:missing",
            "edge" => "edge:gone",
            "kind" => "restricted",
            "reason" => "Locked gate",
            "geometry_hash" => "old"
          }
        ]
    }

    File.write!(Path.join(dir, "authored.json"), Authored.encode(doc))
    %{dir: dir}
  end

  defp state(view) do
    [_, encoded] = Regex.run(~r/data-state="([^"]*)"/, view |> element("#map-hook") |> render())
    encoded |> String.replace("&quot;", "\"") |> String.replace("&amp;", "&") |> Jason.decode!()
  end

  test "review opens missing objects and reconnect preserves location metadata", %{
    conn: conn,
    dir: dir
  } do
    before = File.read!(Path.join(dir, "authored.json"))
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#review", "missing")
    view |> element("#review button[phx-value-id='loc:missing']") |> render_click()
    assert has_element?(view, "#inspector", "node:gone")
    view |> element("#reconnect-location") |> render_click()
    assert state(view)["mode"] == "reconnect"

    render_hook(view, "reconnect_location", %{
      "anchor" => %{"kind" => "node", "ref" => "node:2", "point" => [0, 0]}
    })

    loc = Enum.find(state(view)["authored"]["locations"], &(&1["id"] == "loc:missing"))
    assert loc["name"] == "Annex"
    assert loc["notes"] == "Preserve this"
    assert loc["anchor"]["point"] == [-89.38, 43.075]
    assert loc["anchor"]["ref"] == "node:2"
    assert state(view)["mode"] == "inspect"
    refute has_element?(view, "#review button[phx-value-id='loc:missing']")
    assert File.read!(Path.join(dir, "authored.json")) == before
    view |> element("#save-button") |> render_click()
    assert File.read!(Path.join(dir, "authored.json")) != before
  end

  test "moved references remain unchanged until explicitly reconnected", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    view |> element("#review button[phx-value-id='loc:moved']") |> render_click()
    assert has_element?(view, "#inspector", "has changed")
    assert has_element?(view, "#inspector", "Current intersection position")
    view |> element("#reconnect-location") |> render_click()

    render_hook(view, "reconnect_location", %{
      "anchor" => %{"kind" => "point", "point" => [-89.38, 43.071]}
    })

    assert state(view)["mode"] == "reconnect"
    assert has_element?(view, "#review button[phx-value-id='loc:moved']")
    render_hook(view, "reconnect_location", %{"anchor" => %{"kind" => "node", "ref" => "node:2"}})
    refute has_element?(view, "#review button[phx-value-id='loc:moved']")
  end

  test "missing closure can reconnect to a street while retaining its reason", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    view |> element("#review button[phx-value-id='clo:missing']") |> render_click()
    assert has_element?(view, "#inspector", "edge:gone")
    view |> element("#reconnect-closure") |> render_click()
    render_hook(view, "pick", %{"layer" => "edges", "id" => "edge:3-4-102"})

    assert [
             %{
               "id" => "clo:missing",
               "edge" => "edge:3-4-102",
               "reason" => "Locked gate",
               "geometry_hash" => "deadbeef"
             }
           ] = state(view)["authored"]["closures"]

    refute has_element?(view, "#review button[phx-value-id='clo:missing']")
    assert state(view)["dirty"]
  end

  test "designer can deliberately detach a location or remove a missing closure", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    view |> element("#review button[phx-value-id='loc:missing']") |> render_click()
    view |> element("#inspector button", "Keep as free point") |> render_click()
    loc = Enum.find(state(view)["authored"]["locations"], &(&1["id"] == "loc:missing"))
    assert loc["anchor"] == %{"kind" => "point", "point" => [-89.38, 43.074]}
    view |> element("#review button[phx-value-id='clo:missing']") |> render_click()
    view |> element("#inspector button", "Remove closure") |> render_click()
    assert state(view)["authored"]["closures"] == []
  end
end
