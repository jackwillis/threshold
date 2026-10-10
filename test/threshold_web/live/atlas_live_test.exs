defmodule ThresholdWeb.AtlasLiveTest do
  use ThresholdWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the atlas hook and one button per season", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/atlas")
    assert has_element?(view, "#atlas[phx-hook=AtlasPrototype][data-world=tiny]")

    for season <- ~w(spring summer autumn winter),
        do: assert(has_element?(view, "button[data-season=#{season}]"))
  end

  test "ignores an unusable world name", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/atlas?world=../etc")
    assert has_element?(view, "#atlas[data-world=tiny]")
  end
end
