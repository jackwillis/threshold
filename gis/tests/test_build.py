import json

import pytest

from threshold_gis.world import main


def run(worlds_dir, command):
    main([command, "test", "--worlds-dir", str(worlds_dir)])


def load(worlds_dir, name):
    return json.loads((worlds_dir / "test" / "generated" / name).read_text())


@pytest.fixture
def built(worlds_dir):
    run(worlds_dir, "build")
    return worlds_dir


def test_build_and_validate(built):
    run(built, "validate")
    assert load(built, "provenance.json")["edges"] > 0


def test_build_is_deterministic(worlds_dir):
    names = ["nodes.geojson", "edges.geojson", "context.geojson"]
    run(worlds_dir, "build")
    first = {n: (worlds_dir / "test" / "generated" / n).read_bytes() for n in names}
    run(worlds_dir, "build")
    assert first == {n: (worlds_dir / "test" / "generated" / n).read_bytes() for n in names}


def test_disconnected_component_retained(built):
    edges = load(built, "edges.geojson")["features"]
    assert len({e["properties"]["component"] for e in edges}) == 4  # main network, loop, private footway, sidewalk+crossing pair
    # Building corners must not be counted as network components.
    assert load(built, "provenance.json")["components"] == 4


def test_access_classification(built):
    edges = load(built, "edges.geojson")["features"]
    private = [e for e in edges if 105 in e["properties"]["osm_ids"]]
    assert private and all(e["properties"]["access_status"] == "restricted" for e in private)


def test_parallel_edges_both_kept(built):
    edges = load(built, "edges.geojson")["features"]
    between = [e for e in edges if {e["properties"]["from"], e["properties"]["to"]} == {"node:2", "node:3"}]
    assert len(between) == 2 and len({e["id"] for e in between}) == 2


def test_alley_classification(built):
    edges = load(built, "edges.geojson")["features"]
    assert any(e["properties"]["classification"] == "alley" for e in edges)


def test_boundary_crossing_flagged(built):
    edges = load(built, "edges.geojson")["features"]
    assert any(e["properties"]["crosses_boundary"] for e in edges)


def test_context_building(built):
    context = load(built, "context.geojson")["features"]
    assert any(f["properties"]["classification"] == "building" for f in context)


def test_checksum_mismatch_rejected(worlds_dir):
    (worlds_dir / "test/source/snapshot.osm").write_bytes(b"<osm/>")
    with pytest.raises(SystemExit):
        run(worlds_dir, "build")


def test_json_summary(worlds_dir, capsys):
    main(["build", "test", "--worlds-dir", str(worlds_dir), "--json"])
    assert json.loads(capsys.readouterr().out)["command"] == "build"


def edge_map(worlds_dir):
    return {e["id"]: e for e in load(worlds_dir, "edges.geojson")["features"]}


def test_edge_ids_are_topological(built):
    for id_, edge in edge_map(built).items():
        p = edge["properties"]
        assert id_.startswith(f"edge:{p['from'].removeprefix('node:')}-{p['to'].removeprefix('node:')}-{p['osm_ids'][0]}")


def test_vertex_tweak_keeps_edge_id_but_changes_geometry_hash(worlds_dir):
    import hashlib

    run(worlds_dir, "build")
    before = edge_map(worlds_dir)
    snapshot = worlds_dir / "test/source/snapshot.osm"
    # Insert a mid-edge vertex into way 106 (3 -> 15); it is simplified away, so only the shape changes.
    raw = snapshot.read_text()
    raw = raw.replace('<node id="15"', '<node id="16" lat="43.0752" lon="-89.3670"/>\n<node id="15"')
    raw = raw.replace('<way id="106">\n<nd ref="3"/>', '<way id="106">\n<nd ref="3"/>\n<nd ref="16"/>')
    assert 'ref="16"' in raw
    snapshot.write_text(raw)
    manifest = worlds_dir / "test/source/manifest.json"
    meta = json.loads(manifest.read_text())
    meta["sha256"] = hashlib.sha256(raw.encode()).hexdigest()
    manifest.write_text(json.dumps(meta))
    run(worlds_dir, "build")
    after = edge_map(worlds_dir)
    changed = [i for i in before if after[i]["properties"]["geometry_hash"] != before[i]["properties"]["geometry_hash"]]
    assert set(before) == set(after)
    assert changed and all(106 in before[i]["properties"]["osm_ids"] for i in changed)


def test_area_ways_are_context_not_edges(built):
    edges = load(built, "edges.geojson")["features"]
    assert not any(202 in e["properties"]["osm_ids"] for e in edges)
    context = load(built, "context.geojson")["features"]
    assert any(f["properties"]["classification"] == "pedestrian_area" for f in context)


def test_cycleway_in_graph(built):
    edges = load(built, "edges.geojson")["features"]
    assert any(e["properties"].get("highway") == "cycleway" for e in edges)


def test_elevator_node_kept_as_vertical_context(built):
    context = load(built, "context.geojson")["features"]
    assert any(f["properties"]["classification"] == "vertical" and f["properties"].get("name") == "Test Elevator" for f in context)


def test_sidewalk_and_crossing_are_not_merged_and_keep_their_tags(built):
    edges = load(built, "edges.geojson")["features"]
    sidewalk = [e for e in edges if 301 in e["properties"]["osm_ids"]]
    crossing = [e for e in edges if 302 in e["properties"]["osm_ids"]]
    assert len(sidewalk) == 1 and len(crossing) == 1
    assert sidewalk[0]["id"] != crossing[0]["id"]
    assert sidewalk[0]["properties"]["footway"] == "sidewalk"
    assert crossing[0]["properties"]["footway"] == "crossing"
    assert crossing[0]["properties"]["crossing"] == "marked"
    assert all(301 not in e["properties"]["osm_ids"] or 302 not in e["properties"]["osm_ids"] for e in edges)


def test_access_basis(built):
    edges = {e["properties"]["osm_ids"][0]: e["properties"] for e in load(built, "edges.geojson")["features"]}
    assert edges[105]["access_basis"] == "explicit"  # access=private
    assert edges[101]["access_basis"] == "default_allowed"  # residential, no tag
    assert edges[103]["access_basis"] == "uncertain"  # service alley, no tag
    assert edges[301]["access_basis"] == "default_allowed"  # footway
    assert edges[107]["access_basis"] == "uncertain"  # cycleway


def test_access_basis_in_summary(built):
    summary = load(built, "provenance.json")["summary"]["edges_by_access_basis"]
    assert set(summary) <= {"explicit", "default_allowed", "uncertain"} and sum(summary.values()) == load(built, "provenance.json")["edges"]
