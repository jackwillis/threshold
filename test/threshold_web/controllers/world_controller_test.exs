defmodule ThresholdWeb.WorldControllerTest do
  use ThresholdWeb.ConnCase

  test "serves each layer as JSON", %{conn: conn} do
    for layer <- ~w(boundary provenance nodes edges context authored) do
      conn = get(conn, ~p"/worlds/tiny/#{layer}")
      assert response_content_type(conn, :json)
      assert json_response(conn, 200)
    end
  end

  test "edges are a FeatureCollection", %{conn: conn} do
    assert %{"type" => "FeatureCollection", "features" => [_, _]} =
             conn |> get(~p"/worlds/tiny/edges") |> json_response(200)
  end

  test "unknown layers and worlds are 404", %{conn: conn} do
    assert conn |> get(~p"/worlds/tiny/config") |> json_response(404)
    assert conn |> get(~p"/worlds/nope/edges") |> json_response(404)
    assert conn |> get("/worlds/..%2F/edges") |> json_response(404)
  end
end
