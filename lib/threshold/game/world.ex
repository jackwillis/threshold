defmodule Threshold.Game.World do
  @moduledoc "Loads an immutable movement graph and validates every constituent source edge."
  alias Threshold.{Authored, Playable}
  alias Threshold.Game.Geometry

  defstruct [
    :name,
    :revision,
    :boundary,
    locations: %{},
    connections: %{},
    unavailable: %{},
    spawns: [],
    places: []
  ]

  @access ~w(public unknown conditional mixed)
  @vehicle_service ~w(driveway parking_aisle drive-through emergency_access)

  def load(name) do
    with {:ok, world} <- Threshold.World.load(name),
         :fresh <- world.staleness,
         %{state: :fresh} <- Playable.status(world.dir),
         {:ok, authored, _} <- Authored.load(world.dir),
         {:ok, playable} <- read(world.dir, "playable.json"),
         {:ok, edges} <- read(world.dir, "edges.geojson") do
      revision =
        Enum.map(
          ~w(authored.json boundary.geojson playable.json edges.geojson),
          &File.read!(Path.join(world.dir, &1))
        )
        |> IO.iodata_to_binary()
        |> Authored.hash()

      new(name, playable, edges["features"], world.boundary["geometry"], authored, revision)
    else
      {:error, :not_found} ->
        {:error, "World not found."}

      {:error, errors} when is_list(errors) ->
        {:error, Enum.join(errors, " ")}

      _ ->
        {:error,
         "World files are missing or out of date. Regenerate geography in the editor first."}
    end
  end

  def new(name, playable, edges, boundary, authored, revision \\ "fixture") do
    locations = Map.new(playable["locations"], &{&1["id"], &1})
    source = Map.new(edges, &{&1["id"], &1})

    closures =
      MapSet.new(Enum.filter(authored["closures"], &(&1["kind"] == "restricted")), & &1["edge"])

    {connections, unavailable} =
      Enum.reduce(playable["connections"], {%{}, %{}}, fn connection, {valid, blocked} ->
        case route(connection, locations, source, closures, boundary) do
          {:ok, geometry} ->
            {Map.put(valid, connection["id"], Map.put(connection, "geometry", geometry)), blocked}

          {:error, reason} ->
            {valid, Map.put(blocked, connection["id"], reason)}
        end
      end)

    spawns = authored["spawns"] || []
    places = Enum.filter(authored["locations"], &is_binary(&1["movement_location"]))

    invalid =
      Enum.find(spawns ++ places, fn item ->
        not Map.has_key?(locations, item["location"] || item["movement_location"])
      end)

    if invalid do
      {:error,
       "Authored movement reference #{invalid["id"]} no longer exists. Repair it in the editor."}
    else
      {:ok,
       %__MODULE__{
         name: name,
         revision: revision,
         boundary: boundary,
         locations: locations,
         connections: connections,
         unavailable: unavailable,
         spawns: spawns,
         places: places
       }}
    end
  end

  defp route(connection, locations, source, closures, boundary) do
    with %{"node" => start, "point" => first} <- locations[connection["from"]],
         %{"node" => finish, "point" => last} <- locations[connection["to"]],
         [_ | _] = ids <- connection["edge_ids"],
         {:ok, ^finish, coordinates, path} <- walk(ids, start, source, closures),
         true <- hd(coordinates) == first and List.last(coordinates) == last,
         true <- is_nil(connection["route_nodes"]) or connection["route_nodes"] == path,
         geometry = %{"type" => "LineString", "coordinates" => coordinates},
         true <- is_nil(connection["geometry"]) or connection["geometry"] == geometry do
      if Geometry.covered?(geometry, boundary), do: {:ok, geometry}, else: {:error, :boundary}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_route}
    end
  end

  defp walk(ids, start, source, closures) do
    Enum.reduce_while(ids, {:ok, start, [], [start]}, fn id, {:ok, node, coordinates, path} ->
      case source[id] do
        %{
          "properties" => props,
          "geometry" => %{"type" => "LineString", "coordinates" => [_, _ | _] = line}
        } ->
          cond do
            id in closures ->
              {:halt, {:error, :closure}}

            props["access_status"] not in @access or props["service"] in @vehicle_service ->
              {:halt, {:error, :access}}

            node not in [props["from"], props["to"]] ->
              {:halt, {:error, :invalid_route}}

            true ->
              {next, segment} =
                if node == props["from"],
                  do: {props["to"], line},
                  else: {props["from"], Enum.reverse(line)}

              if coordinates == [] or List.last(coordinates) == hd(segment) do
                {:cont,
                 {:ok, next, coordinates ++ if(coordinates == [], do: segment, else: tl(segment)),
                  path ++ [next]}}
              else
                {:halt, {:error, :invalid_route}}
              end
          end

        _ ->
          {:halt, {:error, :invalid_route}}
      end
    end)
  end

  defp read(dir, name) do
    with {:ok, text} <- File.read(Path.join(dir, name)), do: Jason.decode(text)
  end
end
