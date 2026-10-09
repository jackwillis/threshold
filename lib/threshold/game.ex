defmodule Threshold.Game do
  @moduledoc "Server-authoritative, one-hop movement. Only successful moves advance a turn."
  alias Threshold.Game.{Player, World}

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

  def nearby(%World{} = world, %Player{} = player),
    do: Enum.filter(world.places, &(&1["movement_location"] == player.location))
end
