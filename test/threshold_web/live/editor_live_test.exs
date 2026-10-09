defmodule ThresholdWeb.EditorLiveTest do
  use ThresholdWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the map hook with the initial view state", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert has_element?(view, "#map-hook[phx-hook=MapEditor][data-world=tiny]")
    assert html =~ "Tiny"

    state = view |> element("#map-hook") |> render() |> map_state()
    assert state["colorBy"] == "access_status"
    assert state["layers"]["edges"] == true
    assert state["layers"]["nodes"] == false
    assert state["palette"]["access_status"]["restricted"] == "#d64545"
  end

  test "layer toggles and color mode update the state sent to the map", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#view-form",
      view: %{"nodes" => "true", "buildings" => "false", "color_by" => "component"}
    )
    |> render_change()

    state = view |> element("#map-hook") |> render() |> map_state()
    assert state["layers"]["nodes"] == true
    assert state["layers"]["buildings"] == false
    assert state["colorBy"] == "component"
    assert has_element?(view, "#legend", "connected component")
  end

  test "fresh geography shows no stale banner", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#stale-banner")
  end

  test "lists components and focusing one updates the map focus", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#components", "#1: 1 edges")

    view |> element("#components button[phx-value-index='1']") |> render_click()
    state = view |> element("#map-hook") |> render() |> map_state()
    assert state["focus"]["n"] == 1
    assert state["focus"]["bounds"] == [-89.375, 43.076, -89.374, 43.077]
  end

  test "selection from the map shows in the inspector and can be cleared", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert render(view) =~ "Click a street"

    props = %{
      "id" => "edge:3-4-102",
      "classification" => "path",
      "access_status" => "restricted",
      "osm_ids" => [102]
    }

    render_hook(view, "select", %{
      "layer" => "edges",
      "id" => "edge:3-4-102",
      "properties" => props
    })

    assert has_element?(view, "#inspector", "edge:3-4-102")
    assert has_element?(view, "#inspector a[href='https://www.openstreetmap.org/way/102']")
    assert has_element?(view, "#inspector", "restricted")

    view |> element("#inspector button", "Clear selection") |> render_click()
    assert render(view) =~ "Click a street"
  end

  test "map load results are reflected in the UI", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#map-loading")
    render_hook(view, "map_loaded", %{})
    refute has_element?(view, "#map-loading")

    render_hook(view, "map_failed", %{"message" => "boom"})
    assert has_element?(view, "#map-error", "boom")
  end

  defp map_state(html) do
    [_, encoded] = Regex.run(~r/data-state="([^"]*)"/, html)
    encoded |> unescape() |> Jason.decode!()
  end

  defp unescape(text) do
    text
    |> String.replace("&quot;", "\"")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
  end
end
