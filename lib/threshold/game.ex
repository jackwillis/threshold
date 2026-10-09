defmodule Threshold.Game do
  @moduledoc "Server-authoritative walking. Each traversed connection spends one turn."
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

  @doc "Clickable destinations up to two stops away, with a third-stop preview."
  def walk_options(%World{} = world, %Player{} = player) do
    first = %{
      destination: player.location,
      path: [],
      length_m: 0,
      geometry: %{
        "type" => "LineString",
        "coordinates" => [world.locations[player.location]["point"]]
      }
    }

    {levels, _, _} =
      Enum.reduce(1..3, {%{}, [first], MapSet.new([player.location])}, fn depth,
                                                                          {levels, frontier, seen} ->
        next =
          frontier
          |> Enum.flat_map(fn route ->
            available_moves(world, %{player | location: route.destination})
            |> Enum.map(fn move ->
              %{
                move
                | length_m: route.length_m + move.length_m,
                  geometry:
                    Map.put(
                      move.geometry,
                      "coordinates",
                      route.geometry["coordinates"] ++ tl(move.geometry["coordinates"])
                    )
              }
              |> Map.merge(%{stops: depth, path: route.path ++ [move.destination]})
            end)
          end)
          |> Enum.reject(&MapSet.member?(seen, &1.destination))
          |> Enum.sort_by(&{&1.length_m, &1.path})
          |> Enum.uniq_by(& &1.destination)

        {Map.put(levels, depth, next), next,
         Enum.reduce(next, seen, &MapSet.put(&2, &1.destination))}
      end)

    %{
      moves: (levels[1] ++ levels[2]) |> Enum.sort_by(&{&1.stops, &1.destination}),
      preview: Enum.map(levels[3], &Map.take(&1, [:destination, :point]))
    }
  end

  def move(%World{} = world, %Player{} = player, destination) do
    case Enum.find(walk_options(world, player).moves, &(&1.destination == destination)) do
      nil ->
        {:error, :unavailable}

      route ->
        {:ok,
         %{
           player
           | location: destination,
             turn: player.turn + route.stops,
             visited: Enum.reduce(route.path, player.visited, &MapSet.put(&2, &1))
         }, route}
    end
  end

  def nearby(%World{} = world, %Player{} = player),
    do: Enum.filter(world.places, &(&1["movement_location"] == player.location))
end
