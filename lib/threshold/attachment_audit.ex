defmodule Threshold.AttachmentAudit do
  @moduledoc """
  A read-only report on how authored places and connections relate to the playable network.

  It never changes authored data and its suggestions are not reachability claims: a suggested
  access point is only the nearest candidate, and `reachable` says whether the playable graph
  (honouring closures and access policy) actually connects it to the default spawn.

  Place statuses: `:attached` (its `movement_location` exists), `:missing_target` (it names a
  playable location that no longer exists), `:unattached`. Flags on unattached places:
  `:ambiguous` (the two best candidates are about equally close) and `:disconnected` (no
  candidate, or the best one cannot be reached from the default spawn).

  Connections are classified by how a walk between their endpoints' suggested access points
  compares with the straight line the editor draws. That is evidence for the designer, not a
  decision: existing connection `kind` values are never reinterpreted.
  """
  alias Threshold.Game.{Player, World}

  @candidate_radius_m 150
  @ambiguous_gap_m 15
  @detour_ratio 3.0
  @detour_slack_m 60
  @m_per_deg 111_320

  @type place :: %{
          id: String.t(),
          name: String.t(),
          status: :attached | :missing_target | :unattached,
          flags: [:ambiguous | :disconnected],
          movement_location: String.t() | nil,
          suggestion: map | nil,
          alternatives: [map],
          reachable: boolean | nil
        }

  @spec audit(map, World.t()) :: %{places: [place], connections: [map], summary: map}
  def audit(authored, %World{} = world) do
    reachable = reachable_from_default_spawn(world)
    adjacency = adjacency(world)
    candidates = candidate_index(world)

    places =
      for loc <- authored["locations"] do
        place(loc, world, candidates, reachable)
      end

    by_id = Map.new(places, &{&1.id, &1})
    locations = Map.new(authored["locations"], &{&1["id"], &1})

    connections =
      for conn <- authored["connections"] do
        connection(conn, locations, by_id, adjacency, reachable)
      end

    %{places: places, connections: connections, summary: summary(places, connections, world)}
  end

  # --- Places -------------------------------------------------------------------------

  defp place(loc, world, candidates, reachable) do
    point = loc["anchor"]["point"]
    target = loc["movement_location"]
    base = %{id: loc["id"], name: loc["name"], movement_location: target, point: point}

    cond do
      target && Map.has_key?(world.locations, target) ->
        Map.merge(base, %{
          status: :attached,
          flags: [],
          suggestion: nil,
          alternatives: [],
          reachable: target in reachable
        })

      target ->
        Map.merge(base, %{
          status: :missing_target,
          flags: [],
          suggestion: nil,
          alternatives: nearest(point, world, candidates, loc),
          reachable: nil
        })

      true ->
        ranked = nearest(point, world, candidates, loc)
        suggestion = List.first(ranked)
        runner_up = Enum.at(ranked, 1)
        reachable? = suggestion != nil and suggestion.id in reachable

        flags =
          Enum.reject(
            [
              if(suggestion && runner_up && close?(suggestion, runner_up), do: :ambiguous),
              if(not reachable?, do: :disconnected)
            ],
            &is_nil/1
          )

        Map.merge(base, %{
          status: :unattached,
          flags: flags,
          suggestion: suggestion,
          alternatives: Enum.drop(ranked, 1),
          reachable: if(suggestion, do: reachable?)
        })
    end
  end

  defp close?(%{distance_m: a}, %{distance_m: b}), do: abs(b - a) <= @ambiguous_gap_m

  # Candidates are the endpoints of playable connections that run along the place's own source
  # edge (best evidence of where it sits in the network), then the nearest playable locations.
  defp nearest(point, world, candidates, loc) do
    anchor = loc["anchor"]

    via_edge =
      if anchor["kind"] == "edge",
        do: Map.get(candidates.by_edge, anchor["ref"], []),
        else: []

    ids =
      (via_edge ++ Enum.map(nearest_ids(point, world), & &1))
      |> Enum.uniq()

    ids
    |> Enum.map(fn id ->
      %{
        id: id,
        distance_m: Float.round(metres(point, world.locations[id]["point"]), 1),
        via: if(id in via_edge, do: :source_edge, else: :proximity)
      }
    end)
    |> Enum.filter(&(&1.distance_m <= @candidate_radius_m or &1.via == :source_edge))
    |> Enum.sort_by(&{&1.distance_m, &1.id})
    |> Enum.take(4)
  end

  defp nearest_ids(point, world) do
    world.locations
    |> Enum.map(fn {id, l} -> {metres(point, l["point"]), id} end)
    |> Enum.sort()
    |> Enum.take(3)
    |> Enum.map(&elem(&1, 1))
  end

  defp candidate_index(world) do
    by_edge =
      Enum.reduce(world.connections, %{}, fn {_id, conn}, acc ->
        Enum.reduce(conn["edge_ids"] || [], acc, fn edge, acc ->
          Map.update(
            acc,
            edge,
            [conn["from"], conn["to"]],
            &Enum.uniq(&1 ++ [conn["from"], conn["to"]])
          )
        end)
      end)

    %{by_edge: by_edge}
  end

  # --- Connections ---------------------------------------------------------------------

  defp connection(conn, locations, places, adjacency, reachable) do
    from = places[conn["from"]]
    to = places[conn["to"]]

    straight =
      metres(locations[conn["from"]]["anchor"]["point"], locations[conn["to"]]["anchor"]["point"])

    a = access_point(from)
    b = access_point(to)

    {walk, result} =
      cond do
        is_nil(a) or is_nil(b) -> {nil, :no_access_point}
        a == b -> {0.0, :same_access_point}
        true -> classify(walk_length(adjacency, a, b), straight)
      end

    %{
      id: conn["id"],
      kind: conn["kind"],
      from: conn["from"],
      to: conn["to"],
      straight_m: Float.round(straight, 1),
      walk_m: walk && Float.round(walk, 1),
      class: result,
      endpoints_reachable: a in reachable and b in reachable
    }
  end

  defp access_point(%{movement_location: target}) when is_binary(target), do: target
  defp access_point(%{suggestion: %{id: id}}), do: id
  defp access_point(_), do: nil

  defp classify(nil, _straight), do: {nil, :no_walking_route}

  defp classify(walk, straight) do
    if walk <= straight * @detour_ratio + @detour_slack_m,
      do: {walk, :plausible_walk},
      else: {walk, :long_detour}
  end

  # --- Graph ---------------------------------------------------------------------------

  defp adjacency(world) do
    Enum.reduce(world.connections, %{}, fn {_id, c}, acc ->
      acc
      |> Map.update(c["from"], [{c["to"], c["length_m"]}], &[{c["to"], c["length_m"]} | &1])
      |> Map.update(c["to"], [{c["from"], c["length_m"]}], &[{c["from"], c["length_m"]} | &1])
    end)
  end

  # Dijkstra over the effective playable graph; the graph is small (about a thousand nodes).
  defp walk_length(adjacency, from, to), do: dijkstra(adjacency, [{0.0, from}], %{}, to)

  defp dijkstra(_adjacency, [], _done, _to), do: nil

  defp dijkstra(adjacency, [{d, node} | rest], done, to) do
    cond do
      node == to ->
        d

      Map.has_key?(done, node) ->
        dijkstra(adjacency, rest, done, to)

      true ->
        next =
          for {n, len} <- Map.get(adjacency, node, []),
              not Map.has_key?(done, n),
              do: {d + len, n}

        dijkstra(adjacency, Enum.sort(next ++ rest), Map.put(done, node, d), to)
    end
  end

  defp reachable_from_default_spawn(world) do
    case Enum.find(world.spawns, & &1["default"]) do
      %{"location" => start} -> flood(world, [start], MapSet.new([start]))
      _ -> MapSet.new()
    end
  end

  defp flood(_world, [], seen), do: seen

  defp flood(world, [node | rest], seen) do
    fresh =
      for move <- Threshold.Game.available_moves(world, %Player{location: node}),
          not MapSet.member?(seen, move.destination),
          do: move.destination

    flood(world, rest ++ fresh, Enum.reduce(fresh, seen, &MapSet.put(&2, &1)))
  end

  # --- Summary -------------------------------------------------------------------------

  defp summary(places, connections, world) do
    %{
      places: length(places),
      by_status: Enum.frequencies_by(places, & &1.status),
      unattached_ambiguous: Enum.count(places, &(:ambiguous in &1.flags)),
      unattached_disconnected: Enum.count(places, &(:disconnected in &1.flags)),
      unattached_with_edge_suggestion:
        Enum.count(
          places,
          &(&1.status == :unattached and match?(%{via: :source_edge}, &1.suggestion))
        ),
      connections: length(connections),
      connections_by_kind: Enum.frequencies_by(connections, & &1.kind),
      connections_by_class: Enum.frequencies_by(connections, & &1.class),
      playable_locations: map_size(world.locations),
      default_spawn: Enum.find_value(world.spawns, &(&1["default"] && &1["location"]))
    }
  end

  @doc false
  def metres([x1, y1], [x2, y2]) do
    scale = :math.cos((y1 + y2) / 2 * :math.pi() / 180)

    :math.sqrt(
      :math.pow((x2 - x1) * scale * @m_per_deg, 2) + :math.pow((y2 - y1) * @m_per_deg, 2)
    )
  end
end
