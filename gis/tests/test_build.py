import json

import pytest

from threshold_gis.world import main


def run(worlds_dir, command):
    main([command, "test", "--worlds-dir", str(worlds_dir)])


def load(worlds_dir, name):
    return json.loads((worlds_dir / "test" / name).read_text())


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
    first = {n: (worlds_dir / "test" / n).read_bytes() for n in names}
    run(worlds_dir, "build")
    assert first == {n: (worlds_dir / "test" / n).read_bytes() for n in names}


def test_disconnected_component_retained(built):
    edges = load(built, "edges.geojson")["features"]
    assert len({e["properties"]["component"] for e in edges}) >= 3  # main network, loop, private footway


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
