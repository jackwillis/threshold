defmodule Threshold.EffectiveGraph do
  @moduledoc """
  The movement graph assembled from the designer's authored layer: authored places are the
  positions a player can stand on, and each authored connection that resolves to a real walk
  over the pedestrian network (`Threshold.RouteResolver`) is a one-hop move along that walk's
  actual street geometry. Nothing is written into the generated graph or the authored file.

  * A place stands on its intersection, or on the street at its stored offset when it is
    halfway down a block; free points and places on missing streets have no standing position
    and are left out, with their connections unavailable.
  * A connection is available only if its walk obeys the game's traversal rules and lies inside
    the playable boundary; otherwise it is recorded in `unavailable` with the reason.
  * Authored spawns name generated playable locations, so each is mapped to the nearest
    authored place within 25 m of it; spawns with no such place are skipped (and reported in
    `warnings`), and a default spawn that cannot be mapped is an error.
  * Every authored connection is treated as a walk regardless of its `kind`, which the designer
    has not yet given a movement meaning; `kind` is never rewritten.

  The result is a `Threshold.Game.World`, so movement, numbering and server validation are the
  same code as for the generated graph. Its name is `<world>:authored`, keeping player progress
  separate, and its revision identifies the exact files read.
  """
  alias Threshold.{Authored, Geography, RouteResolver}
  alias Threshold.Game.{Geometry, World}

  @spawn_snap_m 25
  @default_name "New location"

  @spec load(String.t()) :: {:ok, %World{}} | {:error, String.t()}
  def load(name) do
    with {:ok, world} <- Threshold.World.load(name),
         :fresh <- world.staleness,
         generated when is_binary(generated) <- world.generated,
         {:ok, authored_text} <- File.read(Path.join(world.dir, "authored.json")),
         {:ok, authored, _} <- Authored.parse(authored_text),
         {:ok, edges_text} <- File.read(Path.join(generated, "edges.geojson")),
         {:ok, edges} <- Threshold.JsonCache.decode(edges_text),
         {:ok, playable_text} <- File.read(Path.join(generated, "playable.json")),
         {:ok, playable} <- Threshold.JsonCache.decode(playable_text),
         {:ok, geography} <- Geography.index(generated) do
      revision =
        Authored.hash(
          IO.iodata_to_binary([
            "authored-graph\n",
            authored_text,
            world.boundary_text,
            edges_text
          ])
        )

      build(name, world, authored, edges["features"], playable, geography.nodes, revision)
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

  @doc false
  def build(name, world, authored, edge_features, playable, nodes, revision) do
    resolution = RouteResolver.resolve(authored, edge_features, nodes: nodes)
    boundary = world.boundary["geometry"]
    details = Map.new(authored["locations"], &{&1["id"], &1})

    locations =
      for %{stand: stand} = place <- resolution.places, into: %{} do
        {place.id,
         %{"id" => place.id, "point" => stand, "name" => place.name, "node" => place[:node]}}
      end

    {connections, unavailable} = connections(resolution.connections, locations, boundary)

    case map_spawns(authored["spawns"], playable, locations) do
      {:ok, spawns, skipped} ->
        {:ok,
         %World{
           name: name <> ":authored",
           revision: revision,
           boundary: boundary,
           generation: world.generation,
           graph: :authored,
           locations: locations,
           connections: connections,
           unavailable: unavailable,
           spawns: spawns,
           places: places(authored["locations"], locations, details),
           warnings: skipped ++ shared_positions(locations)
         }}

      {:error, message} ->
        {:error, message}
    end
  end

  # --- Connections ---------------------------------------------------------------------

  defp connections(resolved, locations, boundary) do
    Enum.reduce(resolved, {%{}, %{}}, fn c, {valid, blocked} ->
      case validate(c, locations, boundary) do
        :ok ->
          connection = %{
            "id" => c.id,
            "from" => c.from,
            "to" => c.to,
            "length_m" => c.path_m,
            "geometry" => c.geometry,
            "edge_ids" => c.edges
          }

          {Map.put(valid, c.id, connection), blocked}

        {:error, reason} ->
          {valid, Map.put(blocked, c.id, reason)}
      end
    end)
  end

  defp validate(
         %{status: :ok, geometry: %{"coordinates" => coordinates} = geometry} = c,
         locations,
         boundary
       ) do
    cond do
      not (Map.has_key?(locations, c.from) and Map.has_key?(locations, c.to)) ->
        {:error, :unanchored}

      hd(coordinates) != locations[c.from]["point"] or
          List.last(coordinates) != locations[c.to]["point"] ->
        {:error, :invalid_route}

      not Geometry.covered?(geometry, boundary) ->
        {:error, :boundary}

      true ->
        :ok
    end
  end

  defp validate(%{status: :blocked, blockers: [%{reason: reason} | _]}, _, _),
    do: {:error, reason}

  defp validate(%{status: status}, _, _), do: {:error, status}

  # --- Spawns and places ---------------------------------------------------------------

  defp map_spawns(spawns, playable, locations) do
    generated = Map.new(playable["locations"], &{&1["id"], &1["point"]})

    mapped =
      for spawn <- spawns || [] do
        {spawn, nearest(generated[spawn["location"]], locations)}
      end

    ok = for {spawn, {id, _m}} when not is_nil(id) <- mapped, do: Map.put(spawn, "location", id)

    skipped =
      for {spawn, {nil, m}} <- mapped,
          do:
            "Spawn #{spawn["id"]} is not within #{@spawn_snap_m} m of an authored place" <>
              if(m,
                do: " (nearest is #{round(m)} m away) and was skipped.",
                else: " and was skipped."
              )

    default_skipped? =
      Enum.any?(mapped, fn {spawn, {id, _}} -> spawn["default"] && is_nil(id) end)

    if default_skipped? do
      {:error,
       "The default spawn is not within #{@spawn_snap_m} m of any authored place, so a walk cannot start on the authored graph. Move the spawn or add an authored place there."}
    else
      {:ok, ok, skipped}
    end
  end

  defp nearest(nil, _), do: {nil, nil}

  defp nearest(point, locations) do
    case locations
         |> Enum.map(fn {id, l} -> {RouteResolver.metres(point, l["point"]), id} end)
         |> Enum.min(fn -> nil end) do
      {m, id} when m <= @spawn_snap_m -> {id, m}
      {m, _id} -> {nil, m}
      nil -> {nil, nil}
    end
  end

  # Only places with a name or notes of their own are worth inspecting.
  defp places(authored_locations, locations, details) do
    for %{"id" => id} <- authored_locations,
        Map.has_key?(locations, id),
        loc = details[id],
        loc["name"] != @default_name or (loc["notes"] || "") != "" do
      %{
        "id" => id,
        "name" => loc["name"],
        "notes" => loc["notes"] || "",
        "movement_location" => id
      }
    end
  end

  defp shared_positions(locations) do
    for {_point, ids} <- Enum.group_by(Map.values(locations), & &1["point"], & &1["id"]),
        length(ids) > 1 do
      "Places #{Enum.join(Enum.sort(ids), ", ")} stand on the same point."
    end
  end
end
