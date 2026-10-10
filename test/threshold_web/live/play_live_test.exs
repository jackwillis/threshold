defmodule ThresholdWeb.PlayLiveTest do
  use ThresholdWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Threshold.{Authored, Repo}
  alias Threshold.Game.Progress
  @moduletag :database
  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    File.cp_r!(Path.join(Threshold.World.root(), "tiny"), Path.join(tmp, "tiny"))
    previous = Application.get_env(:threshold, :worlds_dir)
    Application.put_env(:threshold, :worlds_dir, tmp)
    on_exit(fn -> Application.put_env(:threshold, :worlds_dir, previous) end)
    dir = Path.join(tmp, "tiny")

    authored =
      Map.merge(Authored.empty(), %{
        "spawns" => [%{"id" => "spawn:default", "location" => "pn:1", "default" => true}],
        "locations" => [
          %{
            "id" => "loc:door",
            "name" => "Unmarked door",
            "notes" => "A faint tapping.",
            "anchor" => %{"kind" => "point", "point" => [-89.38, 43.075]},
            "movement_location" => "pn:2"
          }
        ]
      })

    File.write!(Path.join(dir, "authored.json"), Authored.encode(authored))
    %{dir: dir}
  end

  test "one-hop moves persist, invalid clicks do not spend turns, nearby inspection is free", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/play")
    assert has_element?(view, "#player-turn", "0")
    assert has_element?(view, "#walk-0")
    refute has_element?(view, "#inspect-0")
    state = view |> element("#player-map") |> render() |> state_json()
    refute Map.has_key?(state, "preview")
    assert Enum.map(state["moves"], & &1["destination"]) == ["pn:2"]
    assert [%{"key" => "1", "bearing" => bearing}] = state["moves"]
    assert is_number(bearing)
    assert [west, south, east, north] = state["bounds"]
    assert west < east and south < north
    assert state["limits"] == %{}
    assert has_element?(view, "#walk-0 kbd.play-key", "1")
    assert has_element?(view, "#walk-0[aria-keyshortcuts=\"1\"]")
    render_hook(view, "move", %{"destination" => "pn:3", "turn" => 0})
    assert Repo.get_by!(Progress, world: "tiny").turn == 0
    view |> element("#walk-0") |> render_click()
    assert has_element?(view, "#player-turn", "1")
    assert has_element?(view, "#player-visited", "2")
    view |> element("#inspect-0") |> render_click()
    assert has_element?(view, "#place-inspection", "A faint tapping.")
    assert Repo.get_by!(Progress, world: "tiny").turn == 1
    render_hook(view, "inspect", %{"id" => "loc:forged"})
    refute has_element?(view, "#place-inspection")
    render_hook(view, "move", %{"destination" => "pn:1", "turn" => 0})
    assert has_element?(view, "#player-turn", "1")
    {:ok, restored, _} = live(build_conn(), ~p"/play")
    assert has_element?(restored, "#player-turn", "1")
    assert has_element?(restored, "#inspect-0")
  end

  test "world changes reject movement and require an explicit new walk", %{conn: conn, dir: dir} do
    {:ok, view, _} = live(conn, ~p"/play")
    path = Path.join(dir, "authored.json")
    doc = Jason.decode!(File.read!(path))

    closure = %{
      "id" => "clo:gate",
      "edge" => "edge:1-2-101",
      "kind" => "restricted",
      "geometry_hash" => "deadbeef"
    }

    File.write!(path, Authored.encode(Map.put(doc, "closures", [closure])))
    view |> element("#walk-0") |> render_click()
    assert has_element?(view, "#play-error", "world has changed")
    assert Repo.get_by!(Progress, world: "tiny").turn == 0
    render_hook(view, "new_walk", %{})
    assert has_element?(view, "#play-error", "no usable movement")
  end

  defp state_json(html) do
    [_, encoded] = Regex.run(~r/data-state="([^"]*)"/, html)
    encoded |> unescape() |> Jason.decode!()
  end

  defp unescape(text),
    do:
      text
      |> String.replace("&quot;", "\"")
      |> String.replace("&amp;", "&")
      |> String.replace("&lt;", "<")
      |> String.replace("&gt;", ">")
end
