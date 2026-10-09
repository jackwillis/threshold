import json

import pytest

from threshold_gis.world import main


def run(worlds_dir, command, *extra):
    main([command, "test", "--worlds-dir", str(worlds_dir), *extra])


def load(worlds_dir, name="playable.json"):
    return json.loads((worlds_dir / "test" / name).read_text())


@pytest.fixture
def playable(worlds_dir):
    run(worlds_dir, "build")
    run(worlds_dir, "playable")
    return worlds_dir


def locations(worlds_dir):
    return {loc["id"]: loc for loc in load(worlds_dir)["locations"]}


def test_playable_layer_is_written_and_deterministic(worlds_dir):
    run(worlds_dir, "build")
    run(worlds_dir, "playable")
    first = (worlds_dir / "test/playable.json").read_bytes()
    run(worlds_dir, "playable")
    assert first == (worlds_dir / "test/playable.json").read_bytes()


def test_connectivity_is_preserved(playable):
    d = load(playable)["diagnostics"]
    assert d["components_wrongly_merged"] == 0
    assert d["source_components_lost"] == 0
    assert d["components"] == d["core_components"]


def test_inputs_are_recorded_for_staleness_checks(playable):
    inputs = load(playable)["inputs"]
    assert set(inputs) == {"edges.geojson", "nodes.geojson", "context.geojson"}
    assert all(len(v) == 64 for v in inputs.values())


def test_alley_connections_are_kept(playable):
    assert any("alley" in c["classes"] for c in load(playable)["connections"])


def test_dead_ends_and_special_locations_survive(playable):
    reasons = {r for loc in load(playable)["locations"] for r in loc["reasons"]}
    assert "dead_end" in reasons


def test_connections_reference_real_locations_and_edges(playable):
    d = load(playable)
    ids = {loc["id"] for loc in d["locations"]}
    edge_ids = {e["id"] for e in load(playable, "edges.geojson")["features"]}
    for c in d["connections"]:
        assert c["from"] in ids and c["to"] in ids and c["from"] != c["to"]
        assert set(c["edge_ids"]) <= edge_ids


def test_pass_through_location_is_contracted_unless_retained(playable):
    # Node 19 joins a sidewalk and a crossing (degree 2, nothing special about it).
    assert "pn:19" not in locations(playable)

    (playable / "test/authored.json").write_text(
        json.dumps(
            {
                "format_version": 1,
                "locations": [],
                "connections": [],
                "closures": [],
                "playable_overrides": [{"id": "pn:19", "action": "retain"}],
            }
        )
    )
    run(playable, "playable")
    kept = locations(playable)["pn:19"]
    assert "retained" in kept["reasons"] and kept["override"] == "retain"
    assert load(playable)["diagnostics"]["overrides_applied"] == 1


def test_unmatched_overrides_are_reported(playable):
    (playable / "test/authored.json").write_text(
        json.dumps(
            {
                "format_version": 1,
                "locations": [],
                "connections": [],
                "closures": [],
                "playable_overrides": [{"id": "pn:999999", "action": "suppress"}],
            }
        )
    )
    run(playable, "playable")
    assert load(playable)["diagnostics"]["overrides_unmatched"] == ["pn:999999"]


def test_radius_changes_granularity(playable):
    fine = len(load(playable)["locations"])
    run(playable, "playable", "--radius", "200")
    assert len(load(playable)["locations"]) <= fine
    assert load(playable)["params"]["radius_m"] == 200.0
