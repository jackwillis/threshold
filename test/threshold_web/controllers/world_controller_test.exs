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

  describe "bbox clipping" do
    # Edge 1-2 spans lon -89.385..-89.380; edge 3-4 spans lon -89.375..-89.374.
    defp ids(conn, query) do
      conn
      |> get("/worlds/tiny/edges?" <> query)
      |> json_response(200)
      |> Map.fetch!("features")
      |> Enum.map(& &1["id"])
    end

    test "returns only features that touch the box", %{conn: conn} do
      assert ids(conn, "bbox=-89.3752,43.0755,-89.373,43.078") == ["edge:3-4-102"]
      assert ids(conn, "bbox=-89.386,43.073,-89.379,43.0755") == ["edge:1-2-101"]

      assert ids(conn, "bbox=-89.386,43.073,-89.373,43.078") |> Enum.sort() == [
               "edge:1-2-101",
               "edge:3-4-102"
             ]

      assert ids(conn, "bbox=-89.5,43.0,-89.4,43.01") == []
    end

    test "a clipped response keeps the collection shape, and bad boxes fall back to the full layer",
         %{conn: conn} do
      assert %{"type" => "FeatureCollection"} =
               conn |> get("/worlds/tiny/edges?bbox=-89.5,43.0,-89.4,43.01") |> json_response(200)

      for bad <- ["bbox=nope", "bbox=1,2,3", "bbox=2,2,1,1", "bbox=a,b,c,d"] do
        assert length(ids(conn, bad)) == 2
      end
    end

    test "layers that are not geometry collections ignore the box", %{conn: conn} do
      assert %{"locations" => _} =
               conn |> get("/worlds/tiny/authored?bbox=0,0,1,1") |> json_response(200)
    end
  end

  test "unknown layers and worlds are 404", %{conn: conn} do
    assert conn |> get(~p"/worlds/tiny/config") |> json_response(404)
    assert conn |> get(~p"/worlds/nope/edges") |> json_response(404)
    assert conn |> get("/worlds/..%2F/edges") |> json_response(404)
  end
end
