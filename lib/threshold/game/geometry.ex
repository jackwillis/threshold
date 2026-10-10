defmodule Threshold.Game.Geometry do
  @moduledoc "Geometry for walking routes: boundary coverage (including concave polygon excursions) and bearings."
  @epsilon 1.0e-12

  @doc """
  Initial geographic bearing in degrees clockwise from north, in `[0, 360)`, from one
  `[lon, lat]` point to another. Longitude is scaled by the cosine of the starting latitude.
  """
  @spec bearing([number], [number]) :: float
  def bearing([x, y], [dx, dy]) do
    angle = :math.atan2((dx - x) * :math.cos(y * :math.pi() / 180), dy - y) * 180 / :math.pi()
    normalized = angle - 360 * Float.floor(angle / 360)
    if normalized >= 360, do: 0.0, else: normalized
  end

  def covered?(
        %{"type" => "LineString", "coordinates" => [_ | _] = points},
        %{"type" => "Polygon", "coordinates" => [ring]}
      ) do
    Enum.all?(points, &inside?(&1, ring)) and
      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.all?(fn [a, b] -> segment_inside?(a, b, ring) end)
  end

  def covered?(_, _), do: false

  def inside?([x, y] = point, ring) do
    segments = Enum.chunk_every(ring, 2, 1, :discard)

    Enum.any?(segments, fn [a, b] -> on_segment?(a, b, point) end) or
      rem(
        Enum.count(segments, fn [[ax, ay], [bx, by]] ->
          ay > y != by > y and x < (bx - ax) * (y - ay) / (by - ay) + ax
        end),
        2
      ) == 1
  end

  defp segment_inside?(a, b, ring) do
    cuts =
      [0.0, 1.0] ++
        Enum.flat_map(Enum.chunk_every(ring, 2, 1, :discard), fn [c, d] ->
          intersections(a, b, c, d)
        end)

    cuts
    |> Enum.sort()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [left, right] -> inside?(interpolate(a, b, (left + right) / 2), ring) end)
  end

  defp intersections([ax, ay] = a, [bx, by], [cx, cy] = c, [dx, dy]) do
    r = [bx - ax, by - ay]
    s = [dx - cx, dy - cy]
    q = [cx - ax, cy - ay]
    denominator = cross(r, s)

    cond do
      abs(denominator) > @epsilon ->
        t = cross(q, s) / denominator
        u = cross(q, r) / denominator
        if t >= 0 and t <= 1 and u >= 0 and u <= 1, do: [t], else: []

      on_segment?(a, [bx, by], c) or on_segment?(c, [dx, dy], a) ->
        length2 = Enum.sum(Enum.map(r, &(&1 * &1)))

        if length2 == 0,
          do: [],
          else:
            Enum.filter(
              [dot(q, r) / length2, dot([dx - ax, dy - ay], r) / length2],
              &(&1 >= 0 and &1 <= 1)
            )

      true ->
        []
    end
  end

  defp on_segment?([ax, ay], [bx, by], [x, y]),
    do:
      abs(cross([bx - ax, by - ay], [x - ax, y - ay])) <= @epsilon and
        x >= min(ax, bx) - @epsilon and x <= max(ax, bx) + @epsilon and
        y >= min(ay, by) - @epsilon and y <= max(ay, by) + @epsilon

  defp cross([a, b], [c, d]), do: a * d - b * c
  defp dot([a, b], [c, d]), do: a * c + b * d
  defp interpolate([ax, ay], [bx, by], t), do: [ax + (bx - ax) * t, ay + (by - ay) * t]
end
