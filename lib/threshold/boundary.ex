defmodule Threshold.Boundary do
  @moduledoc """
  The playable boundary (`boundary.geojson`), an importer input. Editing it makes the generated
  geography stale until it is regenerated; saving is refused if the boundary plus its buffer would
  reach beyond the pinned source snapshot.
  """

  alias Threshold.WorldFile

  # Metres per degree of latitude; longitude is scaled by cos(latitude).
  @m_per_deg 111_320
  # The importer buffers in projected metres, so a degrees-based estimate can differ by a few metres.
  # Be lenient here; the importer remains the authority and fails loudly if coverage is really short.
  @tolerance_m 20

  @doc "A polygon geometry from a single ring of `[lon, lat]` positions. The ring is closed if it is not already."
  @spec polygon(term) :: {:ok, map} | {:error, String.t()}
  def polygon([_ | _] = ring) do
    ring = close(ring)

    cond do
      not Enum.all?(ring, &valid_position?/1) ->
        {:error, "Boundary positions must be [longitude, latitude]."}

      length(Enum.uniq(ring)) < 3 ->
        {:error, "A boundary needs at least three distinct corners."}

      self_intersecting?(ring) ->
        {:error, "The boundary edges cross each other."}

      area(ring) == 0.0 ->
        {:error, "A boundary cannot be flat."}

      true ->
        {:ok, %{"type" => "Polygon", "coordinates" => [ring]}}
    end
  end

  def polygon(_), do: {:error, "Boundary must be a list of positions."}

  @doc "Deterministic file contents for a boundary geometry."
  def encode(%{"type" => "Polygon"} = geometry, properties \\ %{}) do
    feature = [
      {"geometry", geometry_ordered(geometry)},
      {"properties", Jason.OrderedObject.new(Enum.sort(properties))},
      {"type", "Feature"}
    ]

    Jason.encode!(Jason.OrderedObject.new(feature), pretty: true) <> "\n"
  end

  defp geometry_ordered(%{"coordinates" => c, "type" => t}),
    do: Jason.OrderedObject.new([{"coordinates", c}, {"type", t}])

  @doc """
  Writes the boundary if the file is unchanged since `base_hash`. Refuses boundaries that exceed
  snapshot coverage (see `coverage_error/3`).
  """
  @spec save(Path.t(), map, String.t(), map) ::
          {:ok, String.t()} | {:error, :conflict | String.t()}
  def save(dir, geometry, base_hash, config) do
    path = Path.join(dir, "boundary.geojson")

    WorldFile.locked(dir, fn ->
      with {:ok, current} <- File.read(path),
           :ok <- if(hash(current) == base_hash, do: :ok, else: {:error, :conflict}),
           :ok <- coverage_error(geometry, config, manifest(dir)) |> to_result() do
        text = encode(geometry, existing_properties(current))

        with :ok <- WorldFile.write_atomic(path, text), do: {:ok, hash(text)}
      else
        {:error, :enoent} -> {:error, "boundary.geojson is missing."}
        other -> other
      end
    end)
  end

  defp existing_properties(text) do
    case Jason.decode(text) do
      {:ok, %{"properties" => %{} = props}} -> props
      _ -> %{}
    end
  end

  def hash(text), do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)

  defp to_result(nil), do: :ok
  defp to_result(message), do: {:error, message}

  defp manifest(dir) do
    with {:ok, text} <- File.read(Path.join(dir, "source/manifest.json")),
         {:ok, manifest} <- Jason.decode(text) do
      manifest
    else
      _ -> nil
    end
  end

  @doc """
  Returns a message if the boundary plus its buffer would reach beyond the source snapshot, else `nil`.
  This is a bounding-box approximation; the importer's own check remains authoritative.
  """
  @spec coverage_error(map, map, map | nil) :: String.t() | nil
  def coverage_error(_geometry, _config, nil), do: nil

  # With an explicit import area the boundary only has to lie inside it; no buffer is added.
  def coverage_error(%{"coordinates" => [ring]}, %{"import_bounds" => _}, %{
        "bounds" => [west, south, east, north]
      }) do
    lons = Enum.map(ring, &Enum.at(&1, 0))
    lats = Enum.map(ring, &Enum.at(&1, 1))

    if Enum.min(lons) < west or Enum.max(lons) > east or Enum.min(lats) < south or
         Enum.max(lats) > north do
      "That boundary reaches beyond the import area. Keep it inside the import area, or acquire a larger one first (make acquire-world)."
    end
  end

  def coverage_error(%{"coordinates" => [ring]}, config, %{"bounds" => [west, south, east, north]}) do
    lons = Enum.map(ring, &Enum.at(&1, 0))
    lats = Enum.map(ring, &Enum.at(&1, 1))
    mid_lat = (Enum.min(lats) + Enum.max(lats)) / 2
    buffer = config["buffer_m"] || 0
    reach = buffer - @tolerance_m
    dlat = reach / @m_per_deg
    dlon = reach / (@m_per_deg * :math.cos(mid_lat * :math.pi() / 180))

    if Enum.min(lons) - dlon < west or Enum.max(lons) + dlon > east or
         Enum.min(lats) - dlat < south or Enum.max(lats) + dlat > north do
      "That boundary plus its #{buffer} m buffer reaches beyond the pinned source snapshot. Keep the boundary inside the snapshot, or acquire a larger snapshot first (make acquire-world)."
    end
  end

  def coverage_error(_, _, _), do: nil

  # --- geometry helpers ---------------------------------------------------------------

  defp close([first | _] = ring),
    do: if(List.last(ring) == first, do: ring, else: ring ++ [first])

  defp valid_position?([lon, lat]),
    do:
      is_number(lon) and is_number(lat) and lon >= -180 and lon <= 180 and lat >= -90 and
        lat <= 90

  defp valid_position?(_), do: false

  defp area(ring) do
    ring
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0.0, fn [[x1, y1], [x2, y2]], acc -> acc + (x1 * y2 - x2 * y1) end)
    |> Kernel./(2)
    |> abs()
  end

  # Segments of a simple ring only touch their neighbours at shared endpoints.
  defp self_intersecting?(ring) do
    segments = ring |> Enum.chunk_every(2, 1, :discard) |> Enum.with_index()
    last = length(segments) - 1

    for {a, i} <- segments,
        {b, j} <- segments,
        j > i + 1,
        not (i == 0 and j == last),
        reduce: false do
      acc -> acc or segments_cross?(a, b)
    end
  end

  defp segments_cross?([p1, p2], [p3, p4]) do
    d1 = orient(p3, p4, p1)
    d2 = orient(p3, p4, p2)
    d3 = orient(p1, p2, p3)
    d4 = orient(p1, p2, p4)

    (d1 * d2 < 0 and d3 * d4 < 0) or
      (d1 == 0 and on_segment?(p3, p4, p1)) or (d2 == 0 and on_segment?(p3, p4, p2)) or
      (d3 == 0 and on_segment?(p1, p2, p3)) or (d4 == 0 and on_segment?(p1, p2, p4))
  end

  defp orient([ax, ay], [bx, by], [cx, cy]), do: (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)

  defp on_segment?([ax, ay], [bx, by], [px, py]),
    do: px >= min(ax, bx) and px <= max(ax, bx) and py >= min(ay, by) and py <= max(ay, by)
end
