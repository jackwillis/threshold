defmodule ThresholdWeb.EditorBoundaryResetTest do
  use ThresholdWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Threshold.Boundary

  @moduletag :tmp_dir
  @small [
    [-89.388, 43.072],
    [-89.372, 43.072],
    [-89.372, 43.078],
    [-89.388, 43.078],
    [-89.388, 43.072]
  ]
  @default [
    [-89.390, 43.071],
    [-89.371, 43.071],
    [-89.371, 43.079],
    [-89.390, 43.079],
    [-89.390, 43.071]
  ]

  setup %{tmp_dir: tmp} do
    File.cp_r!(Path.join(Threshold.World.root(), "tiny"), Path.join(tmp, "tiny"))
    previous = Application.get_env(:threshold, :worlds_dir)
    Application.put_env(:threshold, :worlds_dir, tmp)
    on_exit(fn -> Application.put_env(:threshold, :worlds_dir, previous) end)
    dir = Path.join(tmp, "tiny")

    File.write!(
      Path.join(dir, "source/manifest.json"),
      ~s({"sha256": "abc123", "bounds": [-89.3935, 43.0677, -89.3665, 43.0823]})
    )

    %{dir: dir}
  end

  defp state(view),
    do:
      view
      |> element("#map-hook")
      |> render()
      |> then(&Regex.run(~r/data-state="([^"]*)"/, &1))
      |> List.last()
      |> String.replace("&quot;", "\"")
      |> String.replace("&amp;", "&")
      |> Jason.decode!()

  defp ring(view), do: state(view)["boundary"]["coordinates"] |> hd()

  test "reset to saved discards the boundary edit and nothing is written", %{conn: conn, dir: dir} do
    on_disk = File.read!(Path.join(dir, "boundary.geojson"))
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#reset-boundary-saved[disabled]")

    render_hook(view, "update_boundary", %{"coordinates" => @small})
    assert state(view)["dirty"] == true
    refute has_element?(view, "#reset-boundary-saved[disabled]")

    view |> element("#reset-boundary-saved") |> render_click()
    assert state(view)["dirty"] == false
    assert File.read!(Path.join(dir, "boundary.geojson")) == on_disk
  end

  test "reset to default is an unsaved change until Save", %{conn: conn, dir: dir} do
    {:ok, geometry} = Boundary.polygon(@default)
    File.write!(Path.join(dir, "default_boundary.geojson"), Boundary.encode(geometry))
    on_disk = File.read!(Path.join(dir, "boundary.geojson"))

    {:ok, view, _} = live(conn, ~p"/")
    refute has_element?(view, "#reset-boundary-default[disabled]")
    view |> element("#reset-boundary-default") |> render_click()

    assert ring(view) == @default
    assert state(view)["dirty"] == true
    assert File.read!(Path.join(dir, "boundary.geojson")) == on_disk

    view |> element("#save-button") |> render_click()
    saved = dir |> Path.join("boundary.geojson") |> File.read!() |> Jason.decode!()
    assert saved["geometry"]["coordinates"] == [@default]
  end

  test "reset to default without a defined default says so and leaves the boundary", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#reset-boundary-default[disabled]")
    before = ring(view)
    render_hook(view, "reset_boundary", %{"to" => "default"})
    assert render(view) =~ "no default boundary defined"
    assert ring(view) == before
  end

  test "expand to the import area fills the supported area, can be saved, and is unsaved until then",
       %{conn: conn, dir: dir} do
    on_disk = File.read!(Path.join(dir, "boundary.geojson"))
    {:ok, view, _} = live(conn, ~p"/")
    view |> element("#expand-boundary") |> render_click()

    [[w, s] | _] = ring(view)
    assert w < -89.39 and s < 43.07
    assert state(view)["dirty"] == true
    assert File.read!(Path.join(dir, "boundary.geojson")) == on_disk

    view |> element("#save-button") |> render_click()
    refute render(view) =~ "reaches beyond"
    assert File.read!(Path.join(dir, "boundary.geojson")) != on_disk
  end

  test "reset to saved after expanding returns to the saved boundary", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    saved = ring(view)
    view |> element("#expand-boundary") |> render_click()
    refute ring(view) == saved
    view |> element("#reset-boundary-saved") |> render_click()
    assert ring(view) == saved
    assert state(view)["dirty"] == false
  end

  test "fit to boundary asks the map to frame the working boundary", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    before = state(view)["focus"]["n"]
    render_hook(view, "update_boundary", %{"coordinates" => @small})
    view |> element("#fit-boundary") |> render_click()
    focus = state(view)["focus"]
    assert focus["n"] == before + 1
    assert focus["bounds"] == [-89.388, 43.072, -89.372, 43.078]
  end

  test "resets are refused while regenerating", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    render_hook(view, "update_boundary", %{"coordinates" => @small})
    saved = ring(view)
    :sys.replace_state(view.pid, fn s -> put_in(s.socket.assigns.regenerating, true) end)
    render_hook(view, "reset_boundary", %{"to" => "import"})
    assert ring(view) == saved
  end
end
