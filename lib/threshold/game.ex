defmodule Threshold.Game do
  @moduledoc "Server-authoritative, strictly one-hop walking. Each traversed connection spends one turn."
  alias Threshold.Game.{Geometry, Player, World}

  # Keyboard shortcuts: 1-9 then 0, so at most ten moves have one.
  @shortcuts ~w(1 2 3 4 5 6 7 8 9 0)

  def start(%World{} = world) do
    case Enum.filter(world.spawns, & &1["default"]) do
      [%{"location" => location} = spawn] ->
        player = %Player{location: location, visited: MapSet.new([location])}

        if Map.has_key?(world.locations, location) and available_moves(world, player) != [],
          do: {:ok, player, spawn},
          else: {:error, "The default spawn has no usable movement options."}

      _ ->
        {:error, "Define exactly one default spawn in the world editor before starting a walk."}
    end
  end

  def available_moves(%World{} = world, %Player{location: location}) do
    world.connections
    |> Map.values()
    |> Enum.filter(&(location in [&1["from"], &1["to"]]))
    |> Enum.map(fn connection ->
      destination =
        if connection["from"] == location, do: connection["to"], else: connection["from"]

      geometry =
        if connection["from"] == location,
          do: connection["geometry"],
          else: Map.update!(connection["geometry"], "coordinates", &Enum.reverse/1)

      %{
        destination: destination,
        point: world.locations[destination]["point"],
        connection: connection["id"],
        length_m: connection["length_m"],
        geometry: geometry,
        kind: "walk"
      }
    end)
    |> Enum.sort_by(& &1.destination)
  end

  @doc """
  The available moves in radial order, each with its geographic `bearing` from the player and a
  keyboard shortcut `key` (`"1"`..`"9"`, then `"0"`; `nil` beyond ten, which stay reachable by
  pointer). The order starts at north and runs clockwise, ties broken by destination id. It
  depends only on geography, never on the camera or screen. Presentation only: moving still goes
  through `move/3` with the destination id.
  """
  def numbered_moves(%World{} = world, %Player{location: location} = player) do
    origin = world.locations[location]["point"]

    world
    |> available_moves(player)
    |> Enum.map(&Map.put(&1, :bearing, Geometry.bearing(origin, &1.point)))
    |> Enum.sort_by(&{Float.round(&1.bearing, 4), &1.destination})
    |> Enum.with_index()
    |> Enum.map(fn {move, index} -> Map.put(move, :key, Enum.at(@shortcuts, index)) end)
  end

  @doc """
  Moves the player across exactly one connection to an immediately adjacent, currently
  traversable destination. Each successful move spends one turn.
  """
  def move(%World{} = world, %Player{} = player, destination) do
    case Enum.find(available_moves(world, player), &(&1.destination == destination)) do
      nil ->
        {:error, :unavailable}

      route ->
        {:ok,
         %{
           player
           | location: destination,
             turn: player.turn + 1,
             visited: MapSet.put(player.visited, destination)
         }, route}
    end
  end

  @doc """
  Whether the player is at an authored place right now. On the authored graph a place is a node the
  player stands on, so its id is the player's location; on the generated graph a place is attached
  to a playable location through `movement_location`. Unlike `nearby/2` this does not depend on
  whether the place has a name or notes worth inspecting.
  """
  def at_place?(%World{graph: :authored} = world, %Player{location: location}, place_id),
    do: place_id == location and Map.has_key?(world.locations, place_id)

  def at_place?(%World{} = world, %Player{location: location}, place_id),
    do: Enum.any?(world.places, &(&1["id"] == place_id and &1["movement_location"] == location))

  def nearby(%World{} = world, %Player{} = player),
    do: Enum.filter(world.places, &(&1["movement_location"] == player.location))
end
