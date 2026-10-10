import json
import sys
import types

import pytest
from conftest import osm_xml

from threshold_gis import world as w
from threshold_gis.world import main


def set_config(worlds_dir, **changes):
    path = worlds_dir / "test" / "config.json"
    cfg = json.loads(path.read_text())
    cfg.update(changes)
    path.write_text(json.dumps(cfg))


def test_import_bounds_replace_the_buffered_boundary_as_the_extent(worlds_dir):
    _, polygon, buffered = w.settings(worlds_dir / "test")
    bounds = [-89.40, 43.06, -89.35, 43.09]
    set_config(worlds_dir, import_bounds=bounds)
    _, _, extent = w.settings(worlds_dir / "test")
    assert extent.bounds == pytest.approx(tuple(bounds))
    assert extent.covers(polygon) and extent.area > buffered.area


def test_import_bounds_must_contain_the_boundary(worlds_dir):
    set_config(worlds_dir, import_bounds=[-89.386, 43.0745, -89.384, 43.0755])
    with pytest.raises(ValueError, match="import_bounds"):
        w.settings(worlds_dir / "test")
    set_config(worlds_dir, import_bounds=[-89.35, 43.09, -89.40, 43.06])
    with pytest.raises(ValueError, match="import_bounds"):
        w.settings(worlds_dir / "test")


def test_build_over_a_larger_import_area_records_it_and_validates(worlds_dir):
    base = worlds_dir / "test"
    bounds = [-89.40, 43.06, -89.355, 43.09]
    set_config(worlds_dir, import_bounds=bounds)
    manifest = json.loads((base / "source/manifest.json").read_text())
    manifest["bounds"] = [-89.41, 43.05, -89.35, 43.10]  # the pinned snapshot must cover the import area
    (base / "source/manifest.json").write_text(json.dumps(manifest))
    main(["build", "test", "--worlds-dir", str(worlds_dir)])
    main(["validate", "test", "--worlds-dir", str(worlds_dir)])
    provenance = json.loads((base / "generated/provenance.json").read_text())
    ring = provenance["import_extent"]["coordinates"][0]
    assert [min(p[0] for p in ring), min(p[1] for p in ring), max(p[0] for p in ring), max(p[1] for p in ring)] == pytest.approx(bounds)
    assert provenance["config"]["import_bounds"] == bounds


def test_build_refuses_an_import_area_the_pinned_snapshot_does_not_cover(worlds_dir):
    set_config(worlds_dir, import_bounds=[-89.60, 43.0, -89.20, 43.2])
    with pytest.raises(SystemExit):
        main(["build", "test", "--worlds-dir", str(worlds_dir)])


def fake_overpass(monkeypatch, content):
    calls = []

    def post(url, data, headers, timeout):
        calls.append(data["data"])
        return types.SimpleNamespace(content=content, raise_for_status=lambda: None)

    monkeypatch.setitem(sys.modules, "requests", types.SimpleNamespace(post=post))
    return calls


def test_acquire_refuses_to_overwrite_without_replace_and_never_touches_the_network(worlds_dir, monkeypatch):
    calls = fake_overpass(monkeypatch, osm_xml())
    with pytest.raises(SystemExit):
        main(["acquire", "test", "--worlds-dir", str(worlds_dir)])
    assert calls == []


def test_acquire_replace_pins_the_import_area_and_updates_the_manifest(worlds_dir, monkeypatch):
    base = worlds_dir / "test"
    set_config(worlds_dir, import_bounds=[-89.40, 43.06, -89.35, 43.09])
    fresh = osm_xml().replace(b"</osm>", b"<!-- newer -->\n</osm>")
    calls = fake_overpass(monkeypatch, fresh)
    main(["acquire", "test", "--worlds-dir", str(worlds_dir), "--replace"])
    manifest = json.loads((base / "source/manifest.json").read_text())
    assert (base / "source/snapshot.osm").read_bytes() == fresh
    assert manifest["bounds"] == pytest.approx([-89.40, 43.06, -89.35, 43.09])
    assert manifest["sha256"] == w.digest(fresh)
    assert "(43.0600000,-89.4000000,43.0900000,-89.3500000)" in calls[0]
    assert not list((base / "source").glob("*.tmp"))
