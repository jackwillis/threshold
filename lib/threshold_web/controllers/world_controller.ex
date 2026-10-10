defmodule ThresholdWeb.WorldController do
  @moduledoc "Serves world files (read-only) to the map. Unknown worlds and layers return 404."
  use ThresholdWeb, :controller

  alias Threshold.{JsonCache, World}

  @clippable ~w(edges nodes context)

  def show(conn, %{"world" => world, "layer" => layer} = params) do
    case World.layer_path(world, layer, params["generation"]) do
      {:ok, path} ->
        case clip(path, layer, params["bbox"]) do
          nil ->
            conn
            |> put_resp_content_type("application/json")
            |> send_file(200, path)

          json ->
            conn |> put_resp_content_type("application/json") |> send_resp(200, json)
        end

      :error ->
        conn |> put_status(:not_found) |> json(%{error: "not found"})
    end
  end

  # `?bbox=west,south,east,north` returns only the features whose extent touches the box, so the
  # player map does not download a whole large import area. Anything unparseable gets the full file.
  defp clip(path, layer, bbox) when layer in @clippable and is_binary(bbox) do
    with [_, _, _, _] = parts <- String.split(bbox, ","),
         [w, s, e, n] when w < e and s < n <- Enum.map(parts, &parse_float/1),
         {:ok, text} <- File.read(path),
         {:ok, %{"features" => features} = collection} <- JsonCache.decode(text) do
      JsonCache.memo({:clip, :crypto.hash(:sha256, text), {w, s, e, n}}, fn ->
        kept = Enum.filter(features, &touches?(&1, {w, s, e, n}))
        Jason.encode!(%{collection | "features" => kept})
      end)
    else
      _ -> nil
    end
  end

  defp clip(_path, _layer, _bbox), do: nil

  defp parse_float(text) do
    case Float.parse(text) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp touches?(%{"geometry" => %{"coordinates" => coordinates}}, {w, s, e, n}) do
    {min_x, min_y, max_x, max_y} = extent(coordinates, {nil, nil, nil, nil})
    min_x <= e and max_x >= w and min_y <= n and max_y >= s
  end

  defp touches?(_feature, _box), do: true

  defp extent([x, y | _], {min_x, min_y, max_x, max_y}) when is_number(x) and is_number(y),
    do: {min(min_x || x, x), min(min_y || y, y), max(max_x || x, x), max(max_y || y, y)}

  defp extent(list, acc) when is_list(list), do: Enum.reduce(list, acc, &extent/2)
  defp extent(_other, acc), do: acc
end
