defmodule ThresholdWeb.EditorLiveTest do
  use ThresholdWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the map container with its hook", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#map[phx-hook=MapEditor]")
  end
end
