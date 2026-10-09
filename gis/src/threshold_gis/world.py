"""Offline geographic build. Only `acquire` contacts OpenStreetMap."""

import argparse
import hashlib
import importlib.metadata
import json
import logging
import math
import sys
import tempfile
import xml.etree.ElementTree as ET
from datetime import UTC, datetime
from pathlib import Path

import networkx as nx
import osmnx as ox
from pyproj import Transformer
from shapely.geometry import LineString, Point, mapping, shape
from shapely.ops import transform

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_WORLDS = ROOT / "priv/worlds"
log = logging.getLogger("threshold_gis")
TAGS = [
    "highway",
    "name",
    "access",
    "foot",
    "service",
    "surface",
    "oneway",
    "bridge",
    "tunnel",
    "layer",
    "foot:conditional",
    "access:conditional",
]
HIGHWAYS = {
    "residential",
    "living_street",
    "service",
    "pedestrian",
    "footway",
    "path",
    "cycleway",
    "steps",
    "track",
    "unclassified",
    "tertiary",
    "tertiary_link",
    "secondary",
    "secondary_link",
    "primary",
    "primary_link",
    "road",
}


def load(path):
    return json.loads(path.read_text())


def write(path, data):
    text = json.dumps(data, indent=2, sort_keys=True, allow_nan=False) + "\n"
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(text)
    temp.replace(path)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def feature(id_, geom, props):
    return {"type": "Feature", "id": id_, "geometry": mapping(geom), "properties": {"id": id_, **props}}


def collection(features):
    return {"type": "FeatureCollection", "features": sorted(features, key=lambda f: str(f["id"]))}


def clean(value):
    if isinstance(value, (list, tuple, set)):
        return sorted({str(v) for v in value})
    if isinstance(value, float) and math.isnan(value):
        return None
    if hasattr(value, "item"):
        return value.item()
    return value


def settings(world):
    cfg, boundary = load(world / "config.json"), load(world / "boundary.geojson")
    polygon = shape(boundary["geometry"])
    if polygon.geom_type != "Polygon" or not polygon.is_valid or polygon.is_empty:
        raise ValueError("Boundary must be a valid nonempty GeoJSON Polygon")
    if not 0 <= cfg["buffer_m"] <= 2000:
        raise ValueError("buffer_m must be between 0 and 2000")
    if cfg["access_policy"] not in {"inspect_all", "public_only"}:
        raise ValueError("Unknown access_policy")
    forward = Transformer.from_crs(4326, 32616, always_xy=True).transform
    inverse = Transformer.from_crs(32616, 4326, always_xy=True).transform
    extent = transform(inverse, transform(forward, polygon).buffer(cfg["buffer_m"]))
    return cfg, polygon, extent


def acquire(world):
    import requests

    cfg, _, extent = settings(world)
    west, south, east, north = extent.bounds
    bbox = f"{south:.7f},{west:.7f},{north:.7f},{east:.7f}"
    # Fetch generously: the snapshot is pinned once, so keep everything later decisions may need
    # (standalone elevator nodes, building/park/water multipolygon relations).
    query = (
        f"[out:xml][timeout:120];("
        f'way["highway"]({bbox});node["highway"="elevator"]({bbox});way["building"]({bbox});way["leisure"="park"]({bbox});'
        f'way["natural"="water"]({bbox});relation["building"]({bbox});relation["leisure"="park"]({bbox});'
        f'relation["natural"="water"]({bbox}););(._;>>;);out meta;'
    )
    target = world / cfg["source"]
    if target.exists():
        raise ValueError("Source already exists. Archive it explicitly before acquiring an update.")
    endpoint = "https://overpass-api.de/api/interpreter"
    response = requests.post(
        endpoint,
        data={"data": query},
        headers={"User-Agent": f"threshold-gis/{importlib.metadata.version('threshold-gis')} (local game map editor)", "Accept": "*/*"},
        timeout=180,
    )
    response.raise_for_status()
    root = ET.fromstring(response.content)
    if root.tag != "osm" or root.find("remark") is not None or not root.findall("way"):
        raise ValueError("Overpass returned an error or empty source")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(response.content)
    write(
        world / "source/manifest.json",
        {
            "source": "OpenStreetMap",
            "endpoint": endpoint,
            "retrieved_at": datetime.now(UTC).isoformat(),
            "sha256": digest(response.content),
            "query": query,
            "bounds": list(extent.bounds),
            "license": "ODbL-1.0",
            "attribution": "© OpenStreetMap contributors",
        },
    )
    log.info("Pinned %s: %s bytes", target, f"{len(response.content):,}")
    return {"command": "acquire", "path": str(target), "bytes": len(response.content), "sha256": digest(response.content)}


def access(tags):
    # Explicit foot permission takes precedence over generic access.
    foot, generic = tags.get("foot"), tags.get("access")
    values = foot if foot is not None else generic
    if isinstance(values, list):
        classes = {access({"foot": v}) for v in values}
        return next(iter(classes)) if len(classes) == 1 else "mixed"
    if values in {"yes", "designated", "permissive"}:
        return "public"
    if values in {"no", "private", "customers", "destination", "permit"}:
        return "restricted"
    if values is not None:
        return "conditional"
    return "unknown"


def filtered_xml(raw, cfg):
    root = ET.fromstring(raw)
    for way in list(root.findall("way")):
        tags = {t.attrib["k"]: t.attrib["v"] for t in way.findall("tag")}
        # Closed area=yes ways (plazas, indoor elevator areas) are areas, not network edges.
        keep = tags.get("highway") in HIGHWAYS and tags.get("area") != "yes"
        if cfg["access_policy"] == "public_only":
            keep = keep and access(tags) == "public"
        if not keep:
            root.remove(way)
    # Graph reader needs nodes and highway ways, not context relations.
    for relation in list(root.findall("relation")):
        root.remove(relation)
    return ET.tostring(root)


def make_edge(id_, geom_hash, u, v, coords, osmids, data, boundary, component_map):
    geometry = LineString(coords)
    props = {tag: clean(data[tag]) for tag in TAGS if tag in data}
    highway = data.get("highway")
    classification = (
        "alley"
        if data.get("service") == "alley"
        else "path"
        if highway in {"pedestrian", "footway", "path", "steps", "track", "cycleway"}
        else "street"
    )
    props.update(
        {
            "from": f"node:{u}",
            "to": f"node:{v}",
            "osm_ids": osmids,
            "classification": classification,
            "access_status": access(props),
            "component": component_map[u],
            "length_m": round(float(data.get("length", 0)), 3),
            "inside_playable": boundary.covers(geometry),
            "crosses_boundary": geometry.intersects(boundary.boundary),
            "geometry_hash": geom_hash,
        }
    )
    return feature(id_, geometry, props)


def context_class(props):
    if props.get("highway") == "elevator":
        return "vertical"
    if props.get("highway") in {"pedestrian", "footway"}:
        return "pedestrian_area" if props.get("area") == "yes" else None
    if props.get("building"):
        return "building"
    if props.get("natural") == "water":
        return "water"
    return "park"


def export_graph(graph, boundary):
    nodes, edges = [], []
    component_map = {}
    groups = sorted(nx.weakly_connected_components(graph), key=lambda g: (-len(g), min(g)))
    for index, group in enumerate(groups):
        component_map.update({n: index for n in group})
    candidates = {}  # base id -> {geometry hash: (u, v, coords, osmids, data)}
    for u, v, _, data in sorted(graph.edges(keys=True, data=True), key=lambda row: (row[0], row[1], row[2])):
        geom = data.get("geometry", LineString([(graph.nodes[u]["x"], graph.nodes[u]["y"]), (graph.nodes[v]["x"], graph.nodes[v]["y"])]))
        coords = [[round(x, 7), round(y, 7)] for x, y in geom.coords]
        if tuple(coords[0]) != (round(graph.nodes[u]["x"], 7), round(graph.nodes[u]["y"], 7)):
            coords.reverse()
        if u > v or (u == v and coords[::-1] < coords):
            u, v = v, u
            coords.reverse()
        osmids = data["osmid"] if isinstance(data["osmid"], list) else [data["osmid"]]
        osmids = sorted(map(int, osmids))
        # Both directions of a bidirectional edge normalise to the same geometry and collapse here.
        geom_hash = digest(json.dumps(coords, separators=(",", ":")).encode())[:16]
        base = f"edge:{u}-{v}-{osmids[0]}"
        candidates.setdefault(base, {})[geom_hash] = (u, v, coords, osmids, data)
    for base, group in sorted(candidates.items()):
        # IDs depend on topology (end nodes, lowest way id), not shape, so vertex tweaks keep references valid.
        # Distinct geometries sharing the same ends and way get a deterministic numeric suffix.
        ordered = sorted(group.items(), key=lambda item: item[1][2])
        for index, (geom_hash, (u, v, coords, osmids, data)) in enumerate(ordered, 1):
            id_ = base if len(ordered) == 1 else f"{base}-{index}"
            edges.append(make_edge(id_, geom_hash, u, v, coords, osmids, data, boundary, component_map))
    incident = {f"node:{n}": [] for n in graph.nodes}
    for edge in edges:
        for n in {edge["properties"]["from"], edge["properties"]["to"]}:
            incident[n].append(edge["id"])
    for n, data in sorted(graph.nodes(data=True)):
        if not incident[f"node:{n}"]:
            continue
        pt = Point(round(data["x"], 7), round(data["y"], 7))
        nodes.append(
            feature(
                f"node:{n}",
                pt,
                {
                    "osm_id": n,
                    "component": component_map[n],
                    "inside_playable": boundary.covers(pt),
                    "edges": sorted(incident[f"node:{n}"]),
                    "degree": len(incident[f"node:{n}"]),
                },
            )
        )
    return collection(nodes), collection(edges), len(groups)


def build(world):
    cfg, boundary, extent = settings(world)
    source = world / cfg["source"]
    raw = source.read_bytes()
    manifest = load(world / "source/manifest.json")
    if digest(raw) != manifest["sha256"]:
        raise ValueError("Source checksum does not match manifest")
    a, b, c, d = manifest["bounds"]
    if not shape({"type": "Polygon", "coordinates": [[[a, b], [c, b], [c, d], [a, d], [a, b]]]}).buffer(1e-7).covers(extent):
        raise ValueError("New boundary and buffer exceed pinned source coverage; acquire a larger snapshot explicitly")
    ox.settings.useful_tags_way = TAGS
    ox.settings.useful_tags_node = ["highway", "access", "foot", "barrier"]
    with tempfile.TemporaryDirectory() as tmp:
        filtered = Path(tmp) / "filtered.osm"
        filtered.write_bytes(filtered_xml(raw, cfg))
        graph = ox.graph_from_xml(filtered, bidirectional=True, simplify=False, retain_all=True)
    graph = ox.truncate.truncate_graph_polygon(graph, extent, truncate_by_edge=True)
    graph = ox.simplification.simplify_graph(graph, edge_attrs_differ=["access", "foot", "highway", "service"], remove_rings=False)
    # Nodes left over from filtered-out ways (building corners etc.) are not network components.
    graph.remove_nodes_from(list(nx.isolates(graph)))
    if not cfg["retain_all_components"]:
        graph = ox.truncate.largest_component(graph)
    nodes, edges, count = export_graph(graph, boundary)
    context = ox.features_from_xml(
        source,
        tags={"building": True, "leisure": "park", "natural": "water", "highway": ["pedestrian", "footway", "elevator"]},
    )
    context_features = []
    for (kind, osm_id), row in context.iterrows():
        geometry = row.geometry
        if not geometry.is_empty and geometry.is_valid and geometry.intersects(extent):
            props = {
                k: clean(row[k])
                for k in ["name", "building", "leisure", "natural", "highway", "area", "level", "indoor", "access", "bicycle"]
                if k in row and clean(row[k]) is not None
            }
            classification = context_class(props)
            if classification is None:
                continue  # e.g. ordinary pedestrian/footway lines, which are graph edges
            props.update({"osm_id": int(osm_id), "osm_type": kind, "classification": classification})
            context_features.append(feature(f"{kind}:{osm_id}", geometry, props))
    provenance = {
        "format_version": 1,
        "source": manifest,
        "config": cfg,
        "boundary": mapping(boundary),
        "import_extent": mapping(extent),
        "crs": "EPSG:4326",
        "software": {p: importlib.metadata.version(p) for p in ["osmnx", "networkx", "shapely", "geopandas", "pyproj"]},
        "python": sys.version.split()[0],
        "pipeline_sha256": digest(Path(__file__).read_bytes()),
        "simplification": {"edge_attrs_differ": ["access", "foot", "highway", "service"], "remove_rings": False, "bidirectional": True},
        "components": count,
        "nodes": len(nodes["features"]),
        "edges": len(edges["features"]),
    }
    validate_graph(nodes, edges)
    for filename, data in [
        ("nodes.geojson", nodes),
        ("edges.geojson", edges),
        ("context.geojson", collection(context_features)),
        ("provenance.json", provenance),
    ]:
        write(world / filename, data)
    log.info("Built %d nodes, %d edges, %d components", len(nodes["features"]), len(edges["features"]), count)
    return {"command": "build", "nodes": len(nodes["features"]), "edges": len(edges["features"]), "components": count}


def validate_graph(nodes, edges):
    node_map = {f["id"]: f for f in nodes["features"]}
    if len(node_map) != len(nodes["features"]):
        raise ValueError("Duplicate node IDs")
    ids = set()
    expected = {id_: set() for id_ in node_map}
    for f in nodes["features"] + edges["features"]:
        geom = shape(f["geometry"])
        if geom.is_empty or not geom.is_valid:
            raise ValueError(f"Invalid geometry: {f['id']}")
        if f["properties"]["id"] != f["id"]:
            raise ValueError("Feature ID mismatch")
        minx, miny, maxx, maxy = geom.bounds
        if not (-180 <= minx <= maxx <= 180 and -90 <= miny <= maxy <= 90):
            raise ValueError("Coordinates outside EPSG:4326 range")
    for edge in edges["features"]:
        if edge["id"] in ids:
            raise ValueError("Duplicate edge ID")
        ids.add(edge["id"])
        p = edge["properties"]
        for endpoint, coord in [("from", edge["geometry"]["coordinates"][0]), ("to", edge["geometry"]["coordinates"][-1])]:
            if p[endpoint] not in node_map:
                raise ValueError("Missing endpoint reference")
            if list(node_map[p[endpoint]]["geometry"]["coordinates"]) != list(coord):
                raise ValueError("Edge geometry does not meet endpoint")
            expected[p[endpoint]].add(edge["id"])
    for id_, node in node_map.items():
        if set(node["properties"]["edges"]) != expected[id_]:
            raise ValueError("Incorrect incident edge references")
    return True


def validate(world):
    settings(world)
    validate_graph(load(world / "nodes.geojson"), load(world / "edges.geojson"))
    cfg = load(world / "config.json")
    if digest((world / cfg["source"]).read_bytes()) != load(world / "source/manifest.json")["sha256"]:
        raise ValueError("Source checksum mismatch")
    log.info("Valid geometry, topology, references, boundary, and source checksum")
    return {"command": "validate", "ok": True}


def main(argv=None):
    parser = argparse.ArgumentParser(prog="threshold-gis", description=__doc__)
    parser.add_argument("command", choices=["acquire", "build", "validate"])
    parser.add_argument("world", nargs="?", default="madison")
    parser.add_argument("--worlds-dir", type=Path, default=DEFAULT_WORLDS, help="directory containing world folders")
    parser.add_argument("--json", action="store_true", help="print a machine-readable summary to stdout")
    args = parser.parse_args(argv)
    if not args.world.replace("-", "").isalnum():
        parser.error("World name must be alphanumeric")
    logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="%(levelname)s %(message)s")
    world = args.worlds_dir / args.world
    try:
        summary = {"acquire": acquire, "build": build, "validate": validate}[args.command](world)
    except (ValueError, OSError, ET.ParseError) as exc:
        parser.exit(1, f"World {args.command} failed: {exc}\n")
    if args.json:
        print(json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()
