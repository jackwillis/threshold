defmodule Threshold.RouteResolver do
  @moduledoc """
  Read-only: resolves each authored connection to a real walk over the imported pedestrian
  network (`edges.geojson`), the way a "walk" connection between traversable nodes would have to.

  An authored place is a position on the network. A node anchor is that intersection. An edge
  anchor is a virtual node splitting its street edge at `offset` (a fraction of the edge length),
  so a place halfway down a block is routable. A free point has no network position and is
  reported with the nearest street instead of being guessed.

  Routing uses the same traversal rules as the game: an edge is walkable if its access status is
  public, unknown, conditional or mixed, it is not a vehicle-service way, it is not closed by an
  authored `restricted` closure, and it lies inside the playable boundary. When no walk exists
  under those rules, an unrestricted search tells apart "blocked by a rule" (with the blocking
  edges) from "no path at all" (disconnected network).

  Nothing here changes authored data or the game.
  """

  @access ~w(public unknown conditional mixed)
  @vehicle_service ~w(driveway parking_aisle drive-through emergency_access)
  @detour_ratio 3.0
  @near_node_m 8
  @free_point_search_m 60
  @m_per_deg 111_320

  @type resolution :: %{
          id: String.t(),
          kind: String.t(),
          from: String.t(),
          to: String.t(),
          status: :ok | :blocked | :no_path | :unanchored | :same_position,
          path_m: float | nil,
          straight_m: float,
          detour: boolean,
          edges: [String.t()],
          blockers: [%{edge: String.t(), reason: atom}],
          note: String.t() | nil
        }

  @doc """
  Options: `:playable` (a map of network node id to generated playable location id, to report
  which places coincide with one) and `:nodes` (network node id to `[lon, lat]`; when given,
  every place gets the `stand` point where a player would stand and every resolved connection
  gets its `geometry`, a continuous LineString along the real streets).
  """
  @spec resolve(map, [map], keyword) :: %{
          places: [map],
          connections: [resolution],
          summary: map
        }
  def resolve(authored, edge_features, opts \\ []) do
    nodes_to_playable = Keyword.get(opts, :playable, %{})
    nodes = Keyword.get(opts, :nodes)
    edges = Map.new(edge_features, &{&1["id"], &1})

    closed =
      for %{"kind" => "restricted", "edge" => e} <- authored["closures"],
          into: MapSet.new(),
          do: e

    placed =
      authored["locations"]
      |> Enum.map(&position(&1, edges, nodes_to_playable, edge_features))
      |> Enum.map(&stand(&1, edges, nodes))

    graph = build_graph(placed, edges, closed)
    by_id = Map.new(placed, &{&1.id, &1})
    locations = Map.new(authored["locations"], &{&1["id"], &1})

    connections =
      for conn <- authored["connections"] do
        route(conn, by_id, locations, graph, edges, nodes)
      end

    %{
      places: Enum.map(placed, &Map.drop(&1, [:virtual, :length, :from, :to])),
      connections: connections,
      summary: summary(placed, connections)
    }
  end

  # --- Positions -----------------------------------------------------------------------

  defp position(loc, edges, to_playable, edge_features) do
    anchor = loc["anchor"]
    base = %{id: loc["id"], name: loc["name"], point: anchor["point"]}
    # Where the place is reached on foot: its `access` when set, otherwise the anchor itself.
    access = loc["access"] || anchor
    base = if loc["access"], do: Map.put(base, :access, true), else: base

    case access do
      %{"kind" => "node", "ref" => node} ->
        Map.merge(base, %{class: :intersection, node: node, playable: to_playable[node]})

      %{"kind" => "edge", "ref" => ref, "offset" => offset} ->
        edge_position(base, edges[ref], ref, offset, to_playable)

      _ ->
        Map.merge(base, %{
          class: :free_point,
          node: nil,
          nearest_edge: nearest_edge(anchor["point"], edge_features)
        })
    end
  end

  defp edge_position(base, nil, ref, _offset, _),
    do: Map.merge(base, %{class: :missing_edge, node: nil, edge: ref})

  defp edge_position(base, edge, ref, offset, to_playable) do
    p = edge["properties"]
    length = p["length_m"] * 1.0
    from_m = offset * length
    to_m = (1 - offset) * length

    cond do
      from_m <= @near_node_m ->
        Map.merge(base, %{
          class: :near_intersection,
          node: p["from"],
          playable: to_playable[p["from"]],
          edge: ref,
          offset: offset,
          snap_m: Float.round(from_m, 1)
        })

      to_m <= @near_node_m ->
        Map.merge(base, %{
          class: :near_intersection,
          node: p["to"],
          playable: to_playable[p["to"]],
          edge: ref,
          offset: offset,
          snap_m: Float.round(to_m, 1)
        })

      true ->
        Map.merge(base, %{
          class: :mid_block,
          node: "virtual:" <> base.id,
          edge: ref,
          offset: offset,
          virtual: true,
          from: p["from"],
          to: p["to"],
          length: length
        })
    end
  end

  # Where a player stands for a place: the intersection itself, or the point on the street.
  defp stand(place, _edges, nil), do: place

  defp stand(%{class: class, node: node} = place, _edges, nodes)
       when class in [:intersection, :near_intersection],
       do: Map.put(place, :stand, nodes[node])

  defp stand(%{class: :mid_block, edge: ref, offset: offset} = place, edges, _nodes),
    do:
      Map.put(place, :stand, Threshold.Polyline.at(edges[ref]["geometry"]["coordinates"], offset))

  defp stand(place, _edges, _nodes), do: place

  # --- Graph ---------------------------------------------------------------------------

  # Mid-block places split their edge into chained segments; everything else is an edge as is.
  defp build_graph(placed, edges, closed) do
    splits = placed |> Enum.filter(& &1[:virtual]) |> Enum.group_by(& &1.edge)

    Enum.reduce(edges, %{}, fn {id, feature}, adjacency ->
      p = feature["properties"]
      block = block_reason(p, id, closed)

      chain =
        case Map.get(splits, id) do
          nil -> [{p["from"], p["to"], p["length_m"] * 1.0, {0.0, 1.0}}]
          virtuals -> chain(p, Enum.sort_by(virtuals, & &1.offset))
        end

      Enum.reduce(chain, adjacency, fn {a, b, len, {fa, fb}}, acc ->
        acc
        |> Map.update(a, [{b, len, id, block, {fa, fb}}], &[{b, len, id, block, {fa, fb}} | &1])
        |> Map.update(b, [{a, len, id, block, {fb, fa}}], &[{a, len, id, block, {fb, fa}} | &1])
      end)
    end)
  end

  defp chain(p, virtuals) do
    length = p["length_m"] * 1.0
    stops = [{p["from"], 0.0}] ++ Enum.map(virtuals, &{&1.node, &1.offset}) ++ [{p["to"], 1.0}]

    stops
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [{a, fa}, {b, fb}] -> {a, b, max((fb - fa) * length, 0.0), {fa, fb}} end)
  end

  defp block_reason(p, id, closed) do
    cond do
      MapSet.member?(closed, id) -> :closure
      p["access_status"] not in @access -> :access
      p["service"] in @vehicle_service -> :access
      p["inside_playable"] == false or p["crosses_boundary"] == true -> :outside_boundary
      true -> nil
    end
  end

  # --- Routing -------------------------------------------------------------------------

  defp route(conn, places, locations, graph, edges, nodes) do
    a = places[conn["from"]]
    b = places[conn["to"]]

    straight =
      metres(locations[conn["from"]]["anchor"]["point"], locations[conn["to"]]["anchor"]["point"])

    base = %{
      id: conn["id"],
      kind: conn["kind"],
      from: conn["from"],
      to: conn["to"],
      straight_m: Float.round(straight, 1),
      path_m: nil,
      detour: false,
      edges: [],
      blockers: [],
      note: nil
    }

    cond do
      a.class in [:free_point, :missing_edge] or b.class in [:free_point, :missing_edge] ->
        base |> Map.put(:note, unanchored_note(a, b)) |> Map.put(:status, :unanchored)

      a.node == b.node ->
        base |> Map.put(:status, :same_position) |> Map.put(:path_m, 0.0)

      true ->
        case shortest(graph, a.node, b.node, true) do
          {:ok, length, arcs} ->
            base
            |> Map.merge(%{
              status: :ok,
              path_m: Float.round(length, 1),
              edges: arcs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
            })
            |> Map.put(:detour, length > straight * @detour_ratio + 60)
            |> put_geometry(arcs, edges, nodes)

          :none ->
            unrestricted(base, graph, a.node, b.node)
        end
    end
  end

  defp put_geometry(resolution, _arcs, _edges, nil), do: resolution

  defp put_geometry(resolution, arcs, edges, _nodes) do
    coordinates =
      Enum.reduce(arcs, [], fn {id, from, to}, acc ->
        slice = Threshold.Polyline.slice(edges[id]["geometry"]["coordinates"], from, to)
        if acc != [] and List.last(acc) == hd(slice), do: acc ++ tl(slice), else: acc ++ slice
      end)

    Map.put(resolution, :geometry, %{"type" => "LineString", "coordinates" => coordinates})
  end

  defp unanchored_note(a, b) do
    [a, b]
    |> Enum.reject(&(&1.class in [:intersection, :near_intersection, :mid_block]))
    |> Enum.map_join("; ", fn
      %{class: :free_point, id: id} ->
        "#{id} is a free point with no street position"

      %{class: :missing_edge, id: id, edge: e} ->
        "#{id} references #{e}, which is not in the geography"
    end)
  end

  defp unrestricted(base, graph, a, b) do
    case shortest(graph, a, b, false) do
      {:ok, length, arcs} ->
        edge_ids = arcs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

        blockers =
          for {edge, reason} <- blockers(graph, edge_ids), do: %{edge: edge, reason: reason}

        base
        |> Map.merge(%{
          status: :blocked,
          path_m: Float.round(length, 1),
          edges: edge_ids,
          blockers: blockers
        })

      :none ->
        Map.put(base, :status, :no_path)
    end
  end

  defp blockers(graph, edge_ids) do
    reasons =
      for {_node, arcs} <- graph,
          {_, _, id, reason, _} <- arcs,
          reason != nil,
          id in edge_ids,
          into: %{},
          do: {id, reason}

    for id <- edge_ids, reason = reasons[id], do: {id, reason}
  end

  # Dijkstra with a priority set. `restricted?` honours the traversal rules. A path is the
  # list of `{edge id, from fraction, to fraction}` arcs walked, in order.
  defp shortest(graph, from, to, restricted?),
    do: dijkstra(graph, :gb_sets.singleton({0.0, from, []}), MapSet.new(), to, restricted?)

  defp dijkstra(graph, queue, done, to, restricted?) do
    if :gb_sets.is_empty(queue) do
      :none
    else
      {{dist, node, path}, queue} = :gb_sets.take_smallest(queue)

      cond do
        node == to ->
          {:ok, dist, Enum.reverse(path)}

        MapSet.member?(done, node) ->
          dijkstra(graph, queue, done, to, restricted?)

        true ->
          queue =
            graph
            |> Map.get(node, [])
            |> Enum.reduce(queue, fn {next, len, id, reason, {f0, f1}}, q ->
              if (restricted? and reason != nil) or MapSet.member?(done, next),
                do: q,
                else: :gb_sets.add({dist + len, next, [{id, f0, f1} | path]}, q)
            end)

          dijkstra(graph, queue, MapSet.put(done, node), to, restricted?)
      end
    end
  end

  # --- Geometry and summary ------------------------------------------------------------

  defp nearest_edge(point, features) do
    features
    |> Enum.map(fn f -> {distance_to_line(point, f["geometry"]["coordinates"]), f["id"]} end)
    |> Enum.min(fn -> {nil, nil} end)
    |> case do
      {d, id} when is_number(d) and d <= @free_point_search_m ->
        %{edge: id, distance_m: Float.round(d, 1)}

      _ ->
        nil
    end
  end

  defp distance_to_line(point, coords) do
    coords
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> distance_to_segment(point, a, b) end)
    |> Enum.min()
  end

  defp distance_to_segment([px, py], [ax, ay], [bx, by]) do
    scale = :math.cos(py * :math.pi() / 180)
    {x, y, x1, y1, x2, y2} = {px * scale, py, ax * scale, ay, bx * scale, by}
    {dx, dy} = {x2 - x1, y2 - y1}
    len2 = dx * dx + dy * dy
    t = if len2 == 0, do: 0.0, else: max(0.0, min(1.0, ((x - x1) * dx + (y - y1) * dy) / len2))
    :math.sqrt(:math.pow(x - (x1 + t * dx), 2) + :math.pow(y - (y1 + t * dy), 2)) * @m_per_deg
  end

  @doc false
  def metres([x1, y1], [x2, y2]) do
    scale = :math.cos((y1 + y2) / 2 * :math.pi() / 180)

    :math.sqrt(
      :math.pow((x2 - x1) * scale * @m_per_deg, 2) + :math.pow((y2 - y1) * @m_per_deg, 2)
    )
  end

  defp summary(places, connections) do
    %{
      places: length(places),
      places_by_class: Enum.frequencies_by(places, & &1.class),
      places_on_playable_location: Enum.count(places, &(&1[:playable] != nil)),
      connections: length(connections),
      connections_by_status: Enum.frequencies_by(connections, & &1.status),
      detours: Enum.count(connections, & &1.detour),
      blocker_reasons:
        connections |> Enum.flat_map(& &1.blockers) |> Enum.frequencies_by(& &1.reason)
    }
  end
end
