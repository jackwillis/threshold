defmodule Threshold.Game.Player do
  @moduledoc "Pure player progress, independent of persistence and presentation."
  @enforce_keys [:location]
  defstruct [:location, turn: 0, visited: MapSet.new()]
end
