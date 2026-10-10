defmodule Threshold.PolylineTest do
  use ExUnit.Case, async: true
  alias Threshold.Polyline

  # Two unit-length legs at the equator (cos 0 = 1): total length 2.
  @bent [[0.0, 0.0], [0.0, 1.0], [1.0, 1.0]]

  test "at returns the end vertices exactly and interpolates by length" do
    assert Polyline.at(@bent, 0) == [0.0, 0.0]
    assert Polyline.at(@bent, 1) == [1.0, 1.0]
    assert Polyline.at(@bent, 0.25) == [0.0, 0.5]
    assert Polyline.at(@bent, 0.5) == [0.0, 1.0]
    assert Polyline.at(@bent, 0.75) == [0.5, 1.0]
  end

  test "slice keeps interior vertices and runs in the requested direction" do
    assert Polyline.slice(@bent, 0, 1) == @bent
    assert Polyline.slice(@bent, 0.25, 0.75) == [[0.0, 0.5], [0.0, 1.0], [0.5, 1.0]]
    assert Polyline.slice(@bent, 0.75, 0.25) == [[0.5, 1.0], [0.0, 1.0], [0.0, 0.5]]
    assert Polyline.slice(@bent, 1, 0) == Enum.reverse(@bent)
  end

  test "a zero-length slice is one point, and slices join their neighbours exactly" do
    assert Polyline.slice(@bent, 0.4, 0.4) == [Polyline.at(@bent, 0.4)]
    [_ | _] = first = Polyline.slice(@bent, 0, 0.3)
    second = Polyline.slice(@bent, 0.3, 1)
    assert List.last(first) == hd(second)
    assert Enum.dedup(first ++ second) |> length() == length(first) + length(second) - 1
  end

  test "a slice that starts exactly on a vertex does not duplicate it" do
    assert Polyline.slice(@bent, 0.5, 1) == [[0.0, 1.0], [1.0, 1.0]]
  end
end
