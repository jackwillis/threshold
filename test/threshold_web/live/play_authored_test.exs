defmodule ThresholdWeb.PlayAuthoredTest do
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

    place = fn id, anchor, extra ->
      Map.merge(%{"id" => id, "name" => "New location", "anchor" => anchor}, extra)
    end

    node = fn ref, point -> %{"kind" => "node", "ref" => ref, "point" => point} end

    authored =
      Map.merge(Authored.empty(), %{
        "spawns" => [%{"id" => "spawn:default", "location" => "pn:1", "default" => true}],
        "locations" => [
          place.("loc:a", node.("node:1", [-89.385, 43.074]), %{
            "name" => "The corner",
            "notes" => "Quiet."
          }),
          place.(
            "loc:b",
            %{
              "kind" => "edge",
              "ref" => "edge:1-2-101",
              "offset" => 0.5,
              "point" => [-89.3825, 43.0745],
              "ref_geometry_hash" => "deadbeef"
            },
            %{}
          ),
          place.("loc:c", node.("node:2", [-89.38, 43.075]), %{})
        ],
        "connections" => [
          %{
            "id" => "conn:ab",
            "from" => "loc:a",
            "to" => "loc:b",
            "kind" => "fictional",
            "geometry" => nil
          },
          %{
            "id" => "conn:bc",
            "from" => "loc:b",
            "to" => "loc:c",
            "kind" => "fictional",
            "geometry" => nil
          }
        ]
      })

    File.write!(Path.join([tmp, "tiny", "authored.json"]), Authored.encode(authored))
    :ok
  end

  test "the authored map is played one hop at a time with its own save", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/play?graph=authored")
    assert html =~ "Authored map"
    assert has_element?(view, "#player-turn", "0")
    assert has_element?(view, "#inspect-0", "The corner")

    state = view |> element("#player-map") |> render() |> state_json()
    assert [%{"destination" => "loc:b", "key" => "1"}] = state["moves"]

    view |> element("#walk-0") |> render_click()
    assert has_element?(view, "#player-turn", "1")
    refute has_element?(view, "#inspect-0")

    state = view |> element("#player-map") |> render() |> state_json()
    assert Enum.map(state["moves"], & &1["destination"]) |> Enum.sort() == ["loc:a", "loc:c"]
    # Moving to something not adjacent is refused and spends no turn.
    render_hook(view, "move", %{"destination" => "loc:zzz", "turn" => 1})
    assert Repo.get_by!(Progress, world: "tiny:authored").turn == 1
    assert Repo.get_by(Progress, world: "tiny") == nil

    assert has_element?(view, "#switch-graph", "Play the generated map")
  end

  test "the generated map is the default and keeps its own save", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/play")
    refute html =~ "Authored map:"
    assert has_element?(view, "#switch-graph", "Play the authored map")
    view |> element("#walk-0") |> render_click()
    assert Repo.get_by!(Progress, world: "tiny").turn == 1
    assert Repo.get_by(Progress, world: "tiny:authored") == nil
  end

  defp state_json(html) do
    [_, encoded] = Regex.run(~r/data-state="([^"]*)"/, html)

    encoded
    |> String.replace("&quot;", "\"")
    |> String.replace("&amp;", "&")
    |> Jason.decode!()
  end
end
