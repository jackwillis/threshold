defmodule Threshold.Polyline do
  @moduledoc """
  Positions and slices along a `[lon, lat]` polyline by fraction of its length.

  Lengths are planar with longitude scaled by the cosine of the first latitude, which is
  accurate at street scale and is the measure edge-anchor offsets are stored in. Interpolated
  points are rounded to seven decimals like the imported coordinates; fractions at or beyond the
  ends return the end vertices exactly, so slices join their neighbours without gaps.
  """

  @type point :: [number]

  @doc "The point at `fraction` (0..1) of the way along `line`."
  @spec at([point], number) :: point
  def at([first | _], fraction) when fraction <= 0, do: first
  def at(line, fraction) when fraction >= 1, do: List.last(line)

  def at(line, fraction) do
    {cumulative, total} = measure(line)
    locate(line, cumulative, fraction * total)
  end

  @doc """
  The points from `from` to `to` (fractions of the whole length), in that direction. A slice
  with `from == to` is a single point; `from > to` runs against the line's direction.
  """
  @spec slice([point], number, number) :: [point]
  def slice(line, from, to) when from > to, do: line |> slice(to, from) |> Enum.reverse()

  def slice(line, from, to) do
    {cumulative, total} = measure(line)
    {low, high} = {from * total, to * total}

    inner =
      for {vertex, d} <- Enum.zip(line, cumulative), d > low, d < high, do: vertex

    ([at(line, from)] ++ inner ++ [at(line, to)])
    |> Enum.dedup()
  end

  defp measure([[_, lat] | _] = line) do
    scale = :math.cos(lat * :math.pi() / 180)

    distances =
      line
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [[x1, y1], [x2, y2]] ->
        :math.sqrt(:math.pow((x2 - x1) * scale, 2) + :math.pow(y2 - y1, 2))
      end)

    {Enum.scan([0.0 | distances], &(&1 + &2)), Enum.sum(distances)}
  end

  defp locate(line, cumulative, target) do
    line
    |> Enum.zip(cumulative)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(List.last(line), fn [{[x1, y1], d1}, {[x2, y2], d2}] ->
      if target <= d2 do
        t = if d2 == d1, do: 0.0, else: (target - d1) / (d2 - d1)
        [Float.round(x1 + (x2 - x1) * t, 7), Float.round(y1 + (y2 - y1) * t, 7)]
      end
    end)
  end
end
