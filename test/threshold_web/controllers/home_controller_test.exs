defmodule ThresholdWeb.HomeControllerTest do
  use ThresholdWeb.ConnCase

  test "root renders the landing page with ordinary play and editor links", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(id="landing-page")
    page = LazyHTML.from_document(html)
    assert page |> LazyHTML.query("#landing-play") |> LazyHTML.attribute("href") == ["/play"]
    assert page |> LazyHTML.query("#landing-editor") |> LazyHTML.attribute("href") == ["/editor"]
    assert page |> LazyHTML.query(".landing-link") |> LazyHTML.attribute("phx-click") == []
    refute html =~ ~s(id="map-hook")
  end

  test "old editor query URLs show the landing page without redirecting", %{conn: conn} do
    conn = get(conn, "/?world=tiny&season=winter")
    assert html_response(conn, 200) =~ ~s(id="landing-page")
    assert get_resp_header(conn, "location") == []
  end

  test "landing page does not depend on a configured world", %{conn: conn} do
    assert conn |> get("/?world=missing-world") |> html_response(200) =~
             ~s(id="landing-page")
  end

  test "editor retains its world query parameter and LiveView route", %{conn: conn} do
    html = conn |> get(~p"/editor?world=tiny") |> html_response(200)
    assert html =~ ~s(data-world="tiny")
    refute html =~ ~s(id="landing-page")
  end
end
