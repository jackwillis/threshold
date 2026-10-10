"""Derived playable-location layer.

Builds a smaller network of candidate player locations from the imported pedestrian graph and writes
`playable.json` next to (never into) the imported files. Clusters follow the network, so disconnected
components can never be joined; every source component is kept (see `diagnostics`).

Design choices that are provisional and recorded in `params` / `diagnostics`:
  * alley edges are protected: clustering does not cross them, so alley connections stay visible;
  * plaza gaps are not bridged (the report counts dead ends near pedestrian areas instead);
  * the core graph excludes restricted access and vehicle-oriented service ways.
"""

import hashlib
import json
import logging
import math
from itertools import pairwise

import networkx as nx
from shapely.geometry import Point, shape
from shapely.strtree import STRtree

log = logging.getLogger("threshold_gis")

FORMAT_VERSION = 1
LAT0 = 43.075  # local metric scale; adequate for a study area a kilometre across
VEHICLE_SERVICE = {"driveway", "parking_aisle", "drive-through", "emergency_access"}
ENTRANCE_M = 3.0
VERTICAL_M = 15.0
DEFAULT_RADIUS_M = 25.0
OVERRIDE_ACTIONS = {"retain", "suppress"}


def _sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _load(path):
    return json.loads(path.read_text())


def load_overrides(world):
    """Designer retain/suppress decisions stored in authored.json (ignored if absent or unreadable)."""
    try:
        raw = _load(world / "authored.json").get("playable_overrides", [])
    except (OSError, ValueError):
        return {}
    return {o["id"]: o["action"] for o in raw if isinstance(o, dict) and o.get("action") in OVERRIDE_ACTIONS}


def build_playable(world, radius_m=DEFAULT_RADIUS_M):
    gen = world / "generated"
    edges = _load(gen / "edges.geojson")["features"]
    nodes = {f["id"]: f for f in _load(gen / "nodes.geojson")["features"]}
    context = _load(gen / "context.geojson")["features"]
    overrides = load_overrides(world)

    mx = 111_320 * math.cos(math.radians(LAT0))
    my = 111_320
    pos = {i: (f["geometry"]["coordinates"][0] * mx, f["geometry"]["coordinates"][1] * my) for i, f in nodes.items()}

    core = [
        e
        for e in sorted(edges, key=lambda e: e["id"])
        if e["properties"]["access_status"] != "restricted" and e["properties"].get("service") not in VEHICLE_SERVICE
    ]
    g = nx.MultiGraph()
    for e in core:
        p = e["properties"]
        g.add_edge(
            p["from"],
            p["to"],
            key=e["id"],
            id=e["id"],
            length=p["length_m"],
            cls=p["classification"],
            level=(p.get("tunnel"), p.get("bridge"), p.get("layer")),
        )

    buildings = [shape(f["geometry"]) for f in context if f["properties"]["classification"] == "building"]
    plazas = [shape(f["geometry"]) for f in context if f["properties"]["classification"] == "pedestrian_area"]
    verticals = [
        (f["geometry"]["coordinates"][0] * mx, f["geometry"]["coordinates"][1] * my)
        for f in context
        if f["properties"]["classification"] == "vertical" and f["geometry"]["type"] == "Point"
    ]
    tree_b, tree_p = STRtree(buildings), STRtree(plazas)
    tol = 3 / mx

    def near(tree, geoms, node):
        pt = Point(nodes[node]["geometry"]["coordinates"])
        return any(geoms[i].distance(pt) <= tol for i in tree.query(pt.buffer(tol)))

    def reasons(node):
        out = set()
        incident = [d for _, _, d in g.edges(node, data=True)]
        if g.degree(node) == 1:
            out.add("dead_end")
            if near(tree_b, buildings, node):
                out.add("entrance")
        if any(d["cls"] == "alley" for d in incident):
            out.add("alley")
        if len({d["level"] for d in incident}) > 1:
            out.add("level_change")
        x, y = pos[node]
        if any(math.hypot(x - vx, y - vy) <= VERTICAL_M for vx, vy in verticals):
            out.add("vertical")
        return out

    node_ids = sorted(g.nodes)
    special = {n: reasons(n) for n in node_ids}
    for n in node_ids:
        action = overrides.get(f"pn:{n.removeprefix('node:')}")
        if action == "retain":
            special[n].add("retained")

    # Source components of the core graph, for integrity checks.
    simple = nx.Graph()
    simple.add_nodes_from(node_ids)
    for a, b, d in g.edges(data=True):
        if a != b and (not simple.has_edge(a, b) or simple[a][b]["length"] > d["length"]):
            simple.add_edge(a, b, length=d["length"])
    source_component = {}
    for i, comp in enumerate(sorted((sorted(c) for c in nx.connected_components(simple)), key=lambda c: c[0])):
        for n in comp:
            source_component[n] = i

    # Graph-radius clustering. Alley edges are not traversed, so alleys are not absorbed into intersections.
    walk = nx.Graph()
    walk.add_nodes_from(node_ids)
    for a, b, d in g.edges(data=True):
        if a != b and d["cls"] != "alley" and (not walk.has_edge(a, b) or walk[a][b]["length"] > d["length"]):
            walk.add_edge(a, b, length=d["length"])
    rep = {}
    cluster_paths = {}
    # Retain promises this exact location, even if a larger neighboring cluster could absorb it.
    for seed in sorted(node_ids, key=lambda n: ("retained" not in special[n], -g.degree(n), n)):
        if seed in rep:
            continue
        paths = nx.single_source_dijkstra_path(walk, seed, cutoff=radius_m, weight="length")
        cluster_paths[seed] = paths
        for m in sorted(paths):
            if m == seed or "retained" not in special[m]:
                rep.setdefault(m, seed)
    members = {}
    for n, r in rep.items():
        members.setdefault(r, []).append(n)
    cluster_special = {r: set().union(*(special[m] for m in ms)) for r, ms in members.items()}
    for r in members:  # an explicit "suppress" means the designer does not want this location kept for its own sake
        if overrides.get(f"pn:{r.removeprefix('node:')}") == "suppress":
            cluster_special[r] = set()

    # A cluster representative may be several routing edges away from the boundary edge.
    # Keep those internal paths as well, so each candidate connection is a continuous walk.
    def internal_edges(path):
        return [
            min((d for d in g[a][b].values() if d["cls"] != "alley"), key=lambda d: (d["length"], d["id"]))["id"] for a, b in pairwise(path)
        ]

    by_edge = {e["id"]: e for e in core}

    def route_data(path, edge_ids):
        return {
            "route_nodes": path,
            "edge_ids": edge_ids,
            "length": sum(by_edge[id_]["properties"]["length_m"] for id_ in edge_ids),
            "classes": {by_edge[id_]["properties"]["classification"] for id_ in edge_ids},
        }

    def oriented(data, start):
        if data["route_nodes"][0] == start:
            return data["route_nodes"], data["edge_ids"]
        return list(reversed(data["route_nodes"])), list(reversed(data["edge_ids"]))

    # Collapse onto cluster representatives, keeping the shortest complete parallel route.
    c = nx.Graph()
    c.add_nodes_from(sorted(members))  # a component that collapses to one location must still exist
    for a, b, d in sorted(g.edges(data=True), key=lambda t: t[2]["id"]):
        ra, rb = rep[a], rep[b]
        if ra == rb:
            continue
        left, right = cluster_paths[ra][a], cluster_paths[rb][b]
        route = route_data(left + list(reversed(right)), internal_edges(left) + [d["id"]] + list(reversed(internal_edges(right))))
        if c.has_edge(ra, rb):
            existing = c[ra][rb]
            existing["parallel"] += 1
            classes = existing["classes"] | route["classes"]
            if (route["length"], route["edge_ids"]) < (existing["length"], existing["edge_ids"]):
                existing.update(route)
            existing["classes"] = classes
        else:
            c.add_edge(ra, rb, **route, parallel=1)

    # Contract non-special pass-through locations. A "suppress" override simply does not make a location special.
    changed = True
    while changed:
        changed = False
        for n in sorted(c.nodes):
            if n not in c or c.degree(n) != 2 or cluster_special.get(n):
                continue
            a, b = sorted(c.neighbors(n))
            if a == b or c.has_edge(a, b):
                continue
            da, db = c[n][a], c[n][b]
            left, left_edges = oriented(da, a)
            right, right_edges = oriented(db, n)
            route = route_data(left + right[1:], left_edges + right_edges)
            route["classes"] = da["classes"] | db["classes"]
            c.add_edge(
                a,
                b,
                **route,
                parallel=da["parallel"] + db["parallel"],
            )
            c.remove_node(n)
            changed = True

    def lid(n):
        return f"pn:{n.removeprefix('node:')}"

    locations = []
    for n in sorted(c.nodes):
        props = nodes[n]["properties"]
        locations.append(
            {
                "id": lid(n),
                "point": nodes[n]["geometry"]["coordinates"],
                "node": n,
                "members": len(members[n]),
                "reasons": sorted(cluster_special.get(n, set())),
                "component": source_component[n],
                "inside_playable": props["inside_playable"],
                "degree": c.degree(n),
                "override": overrides.get(lid(n)),
            }
        )

    def geometry(path, edge_ids):
        coordinates = []
        if len(path) != len(edge_ids) + 1:
            raise ValueError("Playable route node/edge count mismatch")
        for a, b, id_ in zip(path, path[1:], edge_ids):
            edge = by_edge[id_]
            props = edge["properties"]
            if (a, b) == (props["from"], props["to"]):
                segment = edge["geometry"]["coordinates"]
            elif (b, a) == (props["from"], props["to"]):
                segment = list(reversed(edge["geometry"]["coordinates"]))
            else:
                raise ValueError(f"Disconnected playable route at {id_}")
            if coordinates and coordinates[-1] != segment[0]:
                raise ValueError(f"Playable route geometry has a gap at {id_}")
            coordinates.extend(segment if not coordinates else segment[1:])
        return {"type": "LineString", "coordinates": coordinates}

    connections = []
    for a, b, d in sorted(c.edges(data=True), key=lambda t: tuple(sorted((lid(t[0]), lid(t[1]))))):
        a, b = sorted((a, b), key=lid)
        a_id, b_id = lid(a), lid(b)
        path, edge_ids = oriented(d, a)
        if path[0] != a or path[-1] != b:
            raise ValueError("Playable route does not meet its locations")
        connections.append(
            {
                "id": f"pc:{a_id.removeprefix('pn:')}-{b_id.removeprefix('pn:')}",
                "from": a_id,
                "to": b_id,
                "length_m": round(d["length"], 1),
                "classes": sorted(d["classes"]),
                "route_classes": sorted({by_edge[id_]["properties"]["classification"] for id_ in edge_ids}),
                "parallel": d["parallel"],
                "edge_ids": edge_ids,
                "route_nodes": path,
                "geometry": geometry(path, edge_ids),
            }
        )

    comps = list(nx.connected_components(c))
    near_plaza = sum(1 for n in c.nodes if c.degree(n) == 1 and near(tree_p, plazas, n))
    lengths = sorted(x["length_m"] for x in connections if x["length_m"] > 0)
    diagnostics = {
        "core_nodes": len(node_ids),
        "core_edges": g.number_of_edges(),
        "core_components": len(set(source_component.values())),
        "locations": len(locations),
        "connections": len(connections),
        "components": len(comps),
        "components_wrongly_merged": sum(1 for comp in comps if len({source_component[n] for n in comp}) > 1),
        "source_components_lost": len(set(source_component.values())) - len({source_component[n] for n in c.nodes}),
        "median_connection_m": round(lengths[len(lengths) // 2], 1) if lengths else 0,
        "pct_connections_40_100m": round(100 * sum(1 for x in lengths if 40 <= x <= 100) / len(lengths), 1) if lengths else 0,
        "pct_connections_over_100m": round(100 * sum(1 for x in lengths if x > 100) / len(lengths), 1) if lengths else 0,
        "dead_end_locations": sum(1 for n in c.nodes if c.degree(n) == 1),
        "dead_ends_near_plazas": near_plaza,
        "alley_connections": sum(1 for x in connections if "alley" in x["classes"]),
        "reasons": {
            k: sum(1 for loc in locations if k in loc["reasons"]) for k in sorted({r for loc in locations for r in loc["reasons"]})
        },
        # An override matches if its location existed before contraction (a suppressed location may be contracted away).
        "overrides_applied": sum(1 for k in overrides if f"node:{k.removeprefix('pn:')}" in members),
        "overrides_unmatched": sorted(k for k in overrides if f"node:{k.removeprefix('pn:')}" not in members),
    }
    return {
        "format_version": FORMAT_VERSION,
        "params": {
            "radius_m": radius_m,
            "protect_alleys": True,
            "bridge_plazas": False,
            "core": "excludes restricted access and driveway/parking_aisle/drive-through/emergency_access service ways",
        },
        "inputs": {name: _sha(gen / name) for name in ("edges.geojson", "nodes.geojson", "context.geojson")},
        "diagnostics": diagnostics,
        "locations": locations,
        "connections": connections,
    }
