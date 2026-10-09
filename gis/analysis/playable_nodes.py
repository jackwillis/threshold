# Playable-node experiment: build candidate "playable location" networks from the imported pedestrian
# graph and compare them. Exploratory; reads committed files and changes nothing.
# Run from the repo root:  .venv/bin/python gis/analysis/playable_nodes.py [--svg out.svg]
import json, math, statistics, sys, collections as C
import networkx as nx
from shapely.geometry import shape, Point
from shapely.strtree import STRtree

W = "priv/worlds/madison/"
LAT0 = 43.075
MX = 111_320 * math.cos(math.radians(LAT0))
MY = 111_320
CLUSTER_M = 12.0   # corner/crossing nodes within this distance become one location
ENTRANCE_M = 3.0
VERTICAL_M = 15.0
LOW, HIGH = 40.0, 100.0

E = json.load(open(W + "edges.geojson"))["features"]
N = {f["id"]: f for f in json.load(open(W + "nodes.geojson"))["features"]}
X = json.load(open(W + "context.geojson"))["features"]
xy = lambda c: (c[0] * MX, c[1] * MY)
pos = {i: xy(f["geometry"]["coordinates"]) for i, f in N.items()}

VEHICLE_SERVICE = {"driveway", "parking_aisle", "drive-through", "emergency_access"}


def walkable_core(e):
    p = e["properties"]
    return p["access_status"] != "restricted" and p.get("service") not in VEHICLE_SERVICE


core = [e for e in E if walkable_core(e)]
G = nx.MultiGraph()
for e in core:
    p = e["properties"]
    G.add_edge(p["from"], p["to"], id=e["id"], length=p["length_m"], cls=p["classification"], hw=p.get("highway"),
               footway=p.get("footway"), tunnel=p.get("tunnel"), bridge=p.get("bridge"), layer=p.get("layer"), inside=p["inside_playable"])

buildings = [shape(f["geometry"]) for f in X if f["properties"]["classification"] == "building"]
plazas = [shape(f["geometry"]) for f in X if f["properties"]["classification"] == "pedestrian_area"]
verticals = [xy(f["geometry"]["coordinates"]) for f in X if f["properties"]["classification"] == "vertical" and f["geometry"]["type"] == "Point"]
tb, tp = STRtree(buildings), STRtree(plazas)
TOL = 3 / MX


def near(tree, geoms, node):
    pt = Point(N[node]["geometry"]["coordinates"])
    return any(geoms[i].distance(pt) <= TOL for i in tree.query(pt.buffer(TOL)))


def special_reasons(g, node):
    """Why a location must survive simplification."""
    r = set()
    inc = [d for _, _, d in g.edges(node, data=True)]
    if g.degree(node) == 1:
        r.add("dead_end")
        if near(tb, buildings, node):
            r.add("entrance")
    if any(d["cls"] == "alley" for d in inc):
        r.add("alley")
    if len({(d["tunnel"], d["bridge"], d["layer"]) for d in inc}) > 1:
        r.add("level_change")
    x, y = pos[node]
    if any(math.hypot(x - vx, y - vy) <= VERTICAL_M for vx, vy in verticals):
        r.add("vertical")
    return r


# Source component of every core node (for the integrity checks in summarize).
SRC = {}
for i, comp in enumerate(nx.connected_components(nx.Graph(G))):
    for n in comp:
        SRC[n] = i


def summarize(name, nodes, conns, source_len, special, note=""):
    """nodes: set; conns: list of dicts(length, classes, parallel)."""
    g = nx.Graph()
    g.add_nodes_from(nodes)
    for c in conns:
        g.add_edge(c["a"], c["b"])
    # Connectivity integrity against the source core graph: components may vanish (collapse to one
    # location, so no node remains) or be wrongly joined (a candidate component spanning several).
    comps = list(nx.connected_components(g))
    merged = sum(1 for comp in comps if len({SRC[n] for n in comp}) > 1)
    represented = {SRC[n] for n in nodes}
    lens = [c["length"] for c in conns if c["length"] > 0]
    n = len(lens)
    deg = [d for _, d in g.degree()]
    return {
        "name": name, "note": note, "locations": len(nodes), "connections": len(conns),
        "components": len(comps),
        "components_wrongly_merged": merged,
        "source_components_lost": len(set(SRC.values())) - len(represented),
        "mean_degree": round(sum(deg) / len(deg), 2) if deg else 0,
        "dead_ends": sum(1 for d in deg if d == 1),
        "len_median_m": round(statistics.median(lens), 1) if lens else 0,
        "len_p10_m": round(statistics.quantiles(lens, n=10)[0], 1) if n > 10 else 0,
        "len_p90_m": round(statistics.quantiles(lens, n=10)[-1], 1) if n > 10 else 0,
        "pct_below_40": round(100 * sum(1 for l in lens if l < LOW) / n, 1),
        "pct_40_100": round(100 * sum(1 for l in lens if LOW <= l <= HIGH) / n, 1),
        "pct_above_100": round(100 * sum(1 for l in lens if l > HIGH) / n, 1),
        "alley_connections": sum(1 for c in conns if "alley" in c["classes"]),
        "extra_nodes_if_split_over_100m": sum(max(0, math.ceil(c["length"] / HIGH) - 1) for c in conns),
        "special_locations": {k: v for k, v in sorted(C.Counter(r for n_ in nodes for r in special.get(n_, ())).items())},
        "source_core_length_m": round(source_len),
    }


# ---------- Candidate A: topological junctions (contract only degree-2 pass-through nodes) ----------
def contract(g, special_fn):
    """Contract non-special degree-2 nodes of a simple weighted graph (attr: length, classes)."""
    g = g.copy()
    changed = True
    while changed:
        changed = False
        for n in list(g.nodes):
            if n not in g or g.degree(n) != 2 or special_fn(n):
                continue
            (a, b) = list(g.neighbors(n))
            if a == b or g.has_edge(a, b):
                continue
            da, db = g[n][a], g[n][b]
            g.add_edge(a, b, length=da["length"] + db["length"], classes=da["classes"] | db["classes"], parallel=da["parallel"] + db["parallel"], inside=da["inside"] or db["inside"])
            g.remove_node(n)
            changed = True
    return g


def simple_from_multi(mg, rep):
    """Collapse parallel edges between representatives; keep the shortest, count the rest."""
    g = nx.Graph()
    for a, b, d in mg.edges(data=True):
        ra, rb = rep[a], rep[b]
        if ra == rb:
            continue
        if g.has_edge(ra, rb):
            e = g[ra][rb]
            e["parallel"] += 1
            e["classes"].add(d["cls"])
            e["length"] = min(e["length"], d["length"])
            e["inside"] = e["inside"] or d["inside"]
        else:
            g.add_edge(ra, rb, length=d["length"], classes={d["cls"]}, parallel=1, inside=d["inside"])
    return g


def conns_of(g):
    return [{"a": a, "b": b, "length": d["length"], "classes": d["classes"], "parallel": d["parallel"]} for a, b, d in g.edges(data=True)]


identity = {n: n for n in G.nodes}
core_len = sum(d["length"] for _, _, d in G.edges(data=True))
spec_full = {n: special_reasons(G, n) for n in G.nodes}

A0 = simple_from_multi(G, identity)
A = contract(A0, lambda n: bool(spec_full.get(n)))
resA = summarize("A junctions", set(A.nodes), conns_of(A), core_len, spec_full, "contract degree-2 only; sidewalks stay parallel to streets")

# ---------- Clustering helpers ----------
def build_from_rep(rep, label, note, contract_after=False):
    """Collapse the core graph onto cluster representatives and summarize."""
    g0 = simple_from_multi(G, rep)
    g0.add_nodes_from(set(rep.values()))  # a component that collapses to one location must still exist
    members_of = C.defaultdict(list)
    for n, r in rep.items():
        members_of[r].append(n)
    spec = {r: set().union(*(spec_full.get(m, set()) for m in ms)) for r, ms in members_of.items()}
    g = contract(g0, lambda n: bool(spec.get(n))) if contract_after else g0
    res = summarize(label, set(g.nodes), conns_of(g), core_len, spec, note)
    res["collapsed_length_m"] = round(sum(d["length"] for a, b, d in G.edges(data=True) if rep[a] == rep[b]))
    sizes = [len(ms) for ms in members_of.values()]
    res["largest_cluster_nodes"] = max(sizes)
    diam = 0.0
    for ms in members_of.values():
        if len(ms) > 1:
            xs = [pos[m] for m in ms]
            diam = max(diam, max(math.hypot(p[0] - q[0], p[1] - q[1]) for p in xs for q in xs[:40]))
    res["largest_cluster_extent_m"] = round(diam)
    return res, g, rep


# B: spatial single linkage (shown to be flawed: it can chain and join unrelated pieces)
grid = C.defaultdict(list)
for n, (x, y) in pos.items():
    if n in G:
        grid[(int(x // CLUSTER_M), int(y // CLUSTER_M))].append(n)
uf = {n: n for n in G.nodes}
def find(a):
    while uf[a] != a:
        uf[a] = uf[uf[a]]
        a = uf[a]
    return a
for (cx, cy), items in grid.items():
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for a_ in items:
                for b_ in grid.get((cx + dx, cy + dy), ()):
                    if a_ < b_ and math.hypot(pos[a_][0] - pos[b_][0], pos[a_][1] - pos[b_][1]) <= CLUSTER_M:
                        uf[find(a_)] = find(b_)
groups = C.defaultdict(list)
for n in G.nodes:
    groups[find(n)].append(n)
rep_spatial = {m: max(ms, key=lambda m_: (G.degree(m_), m_)) for ms in groups.values() for m in ms}
resB, B0, _ = build_from_rep(rep_spatial, "B spatial-12m", "nodes within 12 m merged by straight-line distance (chains; can join unrelated pieces)")

# G(R): graph-radius clustering. Merge only nodes reachable along edges within R metres of a seed,
# so clusters follow the network and can never join disconnected components.
SG = nx.Graph()
for a_, b_, d in G.edges(data=True):
    if a_ != b_ and (not SG.has_edge(a_, b_) or SG[a_][b_]["length"] > d["length"]):
        SG.add_edge(a_, b_, length=d["length"])
SG.add_nodes_from(G.nodes)


def graph_radius(R):
    rep_ = {}
    for seed in sorted(G.nodes, key=lambda n: (-G.degree(n), n)):
        if seed in rep_:
            continue
        for m in nx.single_source_dijkstra_path_length(SG, seed, cutoff=R, weight="length"):
            rep_.setdefault(m, seed)
    return rep_


cands = {}
for R in (15, 25, 40):
    cands[R] = build_from_rep(graph_radius(R), f"G{R} graph-radius {R}m", f"nodes within {R} m along the network merged into one location")
rep25 = graph_radius(25)
resC, Cg, _ = build_from_rep(rep25, "C graph-radius 25m + contract", "G25 plus removal of non-special degree-2 locations", contract_after=True)
resA = resA
Cg = Cg
Gg = cands[25][1]
sens = {R: {"locations": cands[R][0]["locations"], "components": cands[R][0]["components"], "median_m": cands[R][0]["len_median_m"],
            "pct_40_100": cands[R][0]["pct_40_100"], "largest_cluster_nodes": cands[R][0]["largest_cluster_nodes"],
            "largest_cluster_extent_m": cands[R][0]["largest_cluster_extent_m"]} for R in cands}

core_comp = nx.number_connected_components(nx.Graph(G))
results = [resA, resB, cands[25][0], resC]
print(json.dumps({"core": {"nodes": G.number_of_nodes(), "edges": G.number_of_edges(), "components": core_comp, "length_m": round(core_len),
                           "excluded_edges": len(E) - len(core), "excluded_for": "restricted access or driveway/parking/drive-through/emergency service"},
                  "candidates": results, "radius_sensitivity": sens}, indent=2))

# Optional SVG of a crop for visual comparison.
if "--svg" in sys.argv:
    out = sys.argv[sys.argv.index("--svg") + 1]
    cx0, cy0 = xy([-89.3840, 43.0745]); half = 220
    def P(x, y): return (x - cx0 + half, half - (y - cy0))
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{3*2*half}" height="{2*half+40}" font-family="sans-serif" font-size="14">']
    for k, (label, g_) in enumerate([("A junctions", A), ("G25 graph-radius", Gg), ("C G25+contract", Cg)]):
        ox = k * 2 * half
        parts.append(f'<g transform="translate({ox},30)"><rect width="{2*half}" height="{2*half}" fill="#f4f1ea" stroke="#999"/>')
        for e in core:
            for (x1, y1), (x2, y2) in zip(*(lambda cs: (cs[:-1], cs[1:]))([xy(c) for c in e["geometry"]["coordinates"]])):
                a, b = P(x1, y1), P(x2, y2)
                parts.append(f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" stroke="#b5b0a5" stroke-width="1"/>')
        for a, b in g_.edges:
            pa, pb = P(*pos[a]), P(*pos[b])
            parts.append(f'<line x1="{pa[0]:.1f}" y1="{pa[1]:.1f}" x2="{pb[0]:.1f}" y2="{pb[1]:.1f}" stroke="#1f6feb" stroke-width="1.2"/>')
        for n in g_.nodes:
            px, py = P(*pos[n])
            if 0 <= px <= 2 * half and 0 <= py <= 2 * half:
                parts.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="3" fill="#d64545"/>')
        parts.append(f'<text x="6" y="-8" fill="#000">{label}: {g_.number_of_nodes()} locations</text></g>')
    parts.append("</svg>")
    open(out, "w").write("\n".join(parts))
