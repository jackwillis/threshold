defmodule ThresholdWeb.WorldController do
  @moduledoc "Serves world files (read-only) to the map. Unknown worlds and layers return 404."
  use ThresholdWeb, :controller

  alias Threshold.World

  def show(conn, %{"world" => world, "layer" => layer} = params) do
    case World.layer_path(world, layer, params["generation"]) do
      {:ok, path} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_file(200, path)

      :error ->
        conn |> put_status(:not_found) |> json(%{error: "not found"})
    end
  end
end
