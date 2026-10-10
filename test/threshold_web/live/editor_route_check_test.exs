defmodule ThresholdWeb.EditorRouteCheckTest do
  use ThresholdWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Threshold.Authored

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    File.cp_r!(Path.join(Threshold.World.root(), "tiny"), Path.join(tmp, "tiny"))
    previous = Application.get_env(:threshold, :worlds_dir)
    Application.put_env(:threshold, :worlds_dir, tmp)
    on_exit(fn -> Application.put_env(:threshold, :worlds_dir, previous) end)

    place = fn id, anchor -> %{"id" => id, "name" => id, "anchor" => anchor} end
    node = fn ref, point -> %{"kind" => "node", "ref" => ref, "point" => point} end

    link = fn id, from, to ->
      %{"id" => id, "from" => from, "to" => to, "kind" => "fictional", "geometry" => nil}
    end

    authored =
      Map.merge(Authored.empty(), %{
        "locations" => [
          place.("loc:a", node.("node:1", [-89.385, 43.074])),
          place.("loc:b", node.("node:2", [-89.38, 43.075])),
          place.("loc:free", %{"kind" => "point", "point" => [-89.3805, 43.0751]}),
          place.("loc:far", node.("node:3", [-89.375, 43.076]))
        ],
        "connections" => [
          link.("conn:ab", "loc:a", "loc:b"),
          link.("conn:bfree", "loc:b", "loc:free"),
          link.("conn:bfar", "loc:b", "loc:far")
        ]
      })

    path = Path.join([tmp, "tiny", "authored.json"])
    File.write!(path, Authored.encode(authored))
    %{path: path}
  end

  test "lists what does not resolve to a walk and changes nothing", %{conn: conn, path: path} do
    before = File.read!(path)
    {:ok, view, _} = live(conn, ~p"/")
    refute has_element?(view, "#route-check-result")

    view |> element("#check-routes") |> render_click()
    assert has_element?(view, "#route-check-result", "3 connections: 1 walkable")
    assert has_element?(view, "#route-check-result", "loc:free")
    assert has_element?(view, "#route-check-result", "free point")
    assert has_element?(view, "#route-check-result", "conn:bfree")
    assert has_element?(view, "#route-check-result", "conn:bfar")
    assert has_element?(view, "#route-check-result", "no walking route")
    refute has_element?(view, "#route-check-result", "conn:ab")
    assert File.read!(path) == before
  end

  test "the result is cleared when the authored layer is edited", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    view |> element("#check-routes") |> render_click()
    assert has_element?(view, "#route-check-result")

    render_hook(view, "add_location", %{
      "anchor" => %{"kind" => "point", "point" => [-89.38, 43.071]}
    })

    refute has_element?(view, "#route-check-result")
  end
end
