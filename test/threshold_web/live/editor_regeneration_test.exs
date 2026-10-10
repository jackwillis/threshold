defmodule ThresholdWeb.EditorRegenerationTest do
  use ThresholdWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    previous_root = Application.get_env(:threshold, :worlds_dir)
    previous_importer = Application.get_env(:threshold, Threshold.Importer)
    File.cp_r!(Path.join(Threshold.World.root(), "tiny"), Path.join(tmp, "tiny"))
    Application.put_env(:threshold, :worlds_dir, tmp)
    Application.put_env(:threshold, Threshold.Importer, command: Threshold.ImporterStub.command())

    on_exit(fn ->
      Application.put_env(:threshold, :worlds_dir, previous_root)

      if previous_importer,
        do: Application.put_env(:threshold, Threshold.Importer, previous_importer),
        else: Application.delete_env(:threshold, Threshold.Importer)
    end)

    %{dir: Path.join(tmp, "tiny")}
  end

  test "regeneration reloads geography without writing authored content", %{conn: conn, dir: dir} do
    authored = File.read!(Path.join(dir, "authored.json"))
    {:ok, view, _} = live(conn, ~p"/")
    view |> element("#regenerate-button") |> render_click()
    html = render_async(view)
    assert html =~ "Geography regenerated"
    assert html =~ "playable:"
    assert html =~ "validate:"
    assert File.read!(Path.join(dir, "authored.json")) == authored
    refute has_element?(view, "#regeneration-progress")
    assert has_element?(view, "#map-hook[data-state*=generation]")
  end

  test "unsaved changes prevent regeneration even for direct events", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")

    render_hook(view, "add_location", %{
      "anchor" => %{"kind" => "point", "point" => [-89.38, 43.071]}
    })

    assert has_element?(view, "#regenerate-button[disabled]")
    assert render_hook(view, "regenerate", %{}) =~ "Save or discard"
    refute has_element?(view, "#regeneration-output")
    assert has_element?(view, "#dirty-indicator", "Unsaved changes")
  end

  test "failed builds report output and preserve existing generated files", %{
    conn: conn,
    dir: dir
  } do
    before = File.read!(Path.join([dir, "generated", "edges.geojson"]))

    Application.put_env(:threshold, Threshold.Importer,
      command: {"sh", ["-c", "echo broken; exit 3"]}
    )

    {:ok, view, _} = live(conn, ~p"/")
    view |> element("#regenerate-button") |> render_click()
    assert render_async(view) =~ "Regeneration failed"
    assert has_element?(view, "#regeneration-output", "broken")
    assert File.read!(Path.join([dir, "generated", "edges.geojson"])) == before
    refute has_element?(view, "#regenerate-button[disabled]")
  end
end
