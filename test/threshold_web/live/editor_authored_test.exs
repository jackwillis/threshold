defmodule ThresholdWeb.EditorAuthoredTest do
  use ThresholdWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Threshold.Authored

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    File.cp_r!(Path.join(Threshold.World.root(), "tiny"), Path.join(tmp, "tiny"))
    previous = Application.get_env(:threshold, :worlds_dir)
    Application.put_env(:threshold, :worlds_dir, tmp)
    on_exit(fn -> Application.put_env(:threshold, :worlds_dir, previous) end)
    %{dir: Path.join(tmp, "tiny")}
  end

  defp write_authored(dir, doc),
    do: File.write!(Path.join(dir, "authored.json"), Authored.encode(doc))

  defp sample do
    %{
      "format_version" => 1,
      "locations" => [
        %{
          "id" => "loc:ok",
          "name" => "Fine",
          "anchor" => %{"kind" => "node", "ref" => "node:1", "point" => [-89.385, 43.074]}
        },
        %{
          "id" => "loc:gone",
          "name" => "Gone",
          "anchor" => %{"kind" => "node", "ref" => "node:999", "point" => [-89.38, 43.07]}
        },
        %{
          "id" => "loc:free",
          "name" => "Free",
          "notes" => "",
          "anchor" => %{"kind" => "point", "point" => [-89.381, 43.071]}
        }
      ],
      "connections" => [
        %{"id" => "conn:one", "from" => "loc:ok", "to" => "loc:free", "kind" => "fictional"}
      ],
      "closures" => [
        %{
          "id" => "clo:moved",
          "edge" => "edge:1-2-101",
          "kind" => "restricted",
          "geometry_hash" => "old",
          "reason" => "gate"
        }
      ]
    }
  end

  defp map_state(view) do
    [_, encoded] = Regex.run(~r/data-state="([^"]*)"/, view |> element("#map-hook") |> render())
    encoded |> String.replace("&quot;", "\"") |> String.replace("&amp;", "&") |> Jason.decode!()
  end

  test "authored objects and their reference statuses reach the map", %{conn: conn, dir: dir} do
    write_authored(dir, sample())
    {:ok, view, _} = live(conn, ~p"/")

    state = map_state(view)
    assert length(state["authored"]["locations"]) == 3

    assert state["refStatus"] == %{
             "loc:ok" => "ok",
             "loc:gone" => "missing",
             "clo:moved" => "moved"
           }

    assert has_element?(view, "#authored", "3 locations · 1 connections · 1 closures")
  end

  test "the review list names objects whose references need attention", %{conn: conn, dir: dir} do
    write_authored(dir, sample())
    {:ok, view, _} = live(conn, ~p"/")

    assert has_element?(view, "#review li.review-missing", "loc:gone")
    assert has_element?(view, "#review li.review-moved", "clo:moved")
    refute has_element?(view, "#review", "loc:ok")
  end

  test "an empty authored layer has no review list", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    refute has_element?(view, "#review")
    refute has_element?(view, "#authored-errors")
  end

  test "focusing an object asks the map to zoom to it", %{conn: conn, dir: dir} do
    write_authored(dir, sample())
    {:ok, view, _} = live(conn, ~p"/")

    view |> element("#review button[phx-value-id='loc:gone']") |> render_click()
    assert %{"n" => 1, "object" => "loc:gone"} = map_state(view)["focus"]
  end

  test "an invalid authored.json is reported clearly and not loaded", %{conn: conn, dir: dir} do
    File.write!(
      Path.join(dir, "authored.json"),
      ~s({"format_version": 1, "locations": [{"id": "x"}], "connections": [], "closures": []})
    )

    {:ok, view, _} = live(conn, ~p"/")

    assert has_element?(view, "#authored-errors", "authored.json is invalid")
    assert has_element?(view, "#authored-errors", "locations[0]")
    assert map_state(view)["authored"]["locations"] == []
    # The file is left exactly as it was.
    assert File.read!(Path.join(dir, "authored.json")) =~ ~s("id": "x")
  end

  test "malformed JSON is reported", %{conn: conn, dir: dir} do
    File.write!(Path.join(dir, "authored.json"), "{broken")
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#authored-errors", "invalid JSON")
  end
end
