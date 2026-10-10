defmodule Threshold.Game.World do
  @moduledoc "Loads an immutable movement graph and validates every constituent source edge."
  alias Threshold.{Authored, Playable}
  alias Threshold.Game.Geometry

  defstruct [
    :name,
    :revision,
    :boundary,
    :generation,
    graph: :generated,
    warnings: [],
    locations: %{},
    connections: %{},
    unavailable: %{},
    spawns: [],
    places: []
  ]

  @access ~w(public unknown conditional mixed)
  @vehicle_service ~w(driveway parking_aisle drive-through emergency_access)

  @doc """
  Loads a world for play. `graph: :authored` plays on the designer's authored nodes and walks
  (see `Threshold.EffectiveGraph`); the default plays on the generated playable graph. Built
  worlds are immutable and cached by what they were built from (`Threshold.WorldCache`).
  """
  def load(name, opts \\ []) do
    graph = if Keyword.get(opts, :graph) == :authored, do: :authored, else: :generated

    Threshold.WorldCache.fetch(name, graph, fn ->
      if graph == :authored,
        do: Threshold.EffectiveGraph.load(name),
        else: load_generated(name)
    end)
  end

  defp load_generated(name) do
    with {:ok, world} <- Threshold.World.load(name),
         :fresh <- world.staleness,
         %{state: :fresh} <- Playable.status(world.generated),
         {:ok, authored_text} <- File.read(Path.join(world.dir, "authored.json")),
         {:ok, authored, _} <- Authored.parse(authored_text),
         {:ok, playable_text} <- File.read(Path.join(world.generated, "playable.json")),
         {:ok, playable} <- Threshold.JsonCache.decode(playable_text),
         {:ok, edges_text} <- File.read(Path.join(world.generated, "edges.geojson")),
         {:ok, edges} <- Threshold.JsonCache.decode(edges_text) do
      # The revision identifies exactly the bytes parsed above, all from one generated snapshot.
      revision =
        Authored.hash(
          IO.iodata_to_binary([authored_text, world.boundary_text, playable_text, edges_text])
        )

      with {:ok, loaded} <-
             new(
               name,
               playable,
               edges["features"],
               world.boundary["geometry"],
               authored,
               revision
             ),
           do: {:ok, %{loaded | generation: world.generation}}
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
end
