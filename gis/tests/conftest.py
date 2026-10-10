import hashlib
import json
from pathlib import Path

import pytest

from threshold_gis import world as w

REPO = Path(__file__).resolve().parents[2]

TEST_BOUNDARY = [[-89.391777, 43.06993], [-89.369448, 43.06993], [-89.369448, 43.080139], [-89.391777, 43.080139], [-89.391777, 43.06993]]

# (id, lon, lat)
NODES = [
    (1, -89.3860, 43.0750),
    (2, -89.3800, 43.0750),
    (3, -89.3740, 43.0750),
    (4, -89.3800, 43.0790),
    (5, -89.3800, 43.0710),
    (6, -89.3790, 43.0775),
    (7, -89.3780, 43.0775),
    (8, -89.3780, 43.0785),
    (9, -89.3790, 43.0785),
    (10, -89.3770, 43.0720),
    (11, -89.3765, 43.0720),
    (12, -89.3815, 43.0752),
    (13, -89.3815, 43.0756),
    (14, -89.3810, 43.0756),
    (15, -89.3600, 43.0750),
    (18, -89.3830, 43.0732),
    (19, -89.3826, 43.0732),
    (20, -89.3822, 43.0732),
]
# (id, node refs, tags)
WAYS = [
    (101, [1, 2, 3], {"highway": "residential", "name": "Main St"}),
    (102, [4, 2, 5], {"highway": "residential", "name": "Cross St"}),
    (103, [2, 3], {"highway": "service", "service": "alley"}),  # parallel to Main St segment
    (104, [6, 7, 8, 9, 6], {"highway": "footway"}),  # loop
    (105, [10, 11], {"highway": "footway", "access": "private"}),  # disconnected, restricted
    (106, [3, 15], {"highway": "residential"}),  # leaves the playable boundary and the import extent
    (201, [12, 13, 14, 12], {"building": "yes"}),
    (107, [1, 5], {"highway": "cycleway"}),
    (301, [18, 19], {"highway": "footway", "footway": "sidewalk"}),
    (302, [19, 20], {"highway": "footway", "footway": "crossing", "crossing": "marked"}),  # must not merge with 301
    (202, [6, 7, 8, 9, 6], {"highway": "pedestrian", "area": "yes"}),  # plaza polygon: context, not edges
]


def osm_xml():
    out = ['<?xml version="1.0"?>', '<osm version="0.6">']
    for id_, lon, lat in NODES:
        out.append(f'<node id="{id_}" lat="{lat}" lon="{lon}"/>')
    out.append('<node id="17" lat="43.0730" lon="-89.3770"><tag k="highway" v="elevator"/><tag k="name" v="Test Elevator"/></node>')
    for id_, refs, tags in WAYS:
        out.append(f'<way id="{id_}">')
        out += [f'<nd ref="{r}"/>' for r in refs]
        out += [f'<tag k="{k}" v="{v}"/>' for k, v in tags.items()]
        out.append("</way>")
    out.append("</osm>")
    return "\n".join(out).encode()


@pytest.fixture
def worlds_dir(tmp_path):
    """A complete synthetic world with a pinned source, laid out like priv/worlds/<name>."""
    world = tmp_path / "worlds" / "test"
    (world / "source").mkdir(parents=True)
    # A fixed boundary (not the live Madison file, which the designer edits) keeps these tests deterministic.
    (world / "boundary.geojson").write_text(
        json.dumps({"type": "Feature", "properties": {}, "geometry": {"type": "Polygon", "coordinates": [TEST_BOUNDARY]}})
    )
    (world / "config.json").write_text(
        json.dumps(
            {
                "format_version": 1,
                "name": "Test",
                "buffer_m": 250,
                "access_policy": "inspect_all",
                "retain_all_components": True,
                "source": "source/snapshot.osm",
            }
        )
    )
    raw = osm_xml()
    (world / "source/snapshot.osm").write_bytes(raw)
    _, _, extent = w.settings(world)
    pad = 0.01  # the pinned snapshot must cover the import extent
    west, south, east, north = extent.bounds
    (world / "source/manifest.json").write_text(
        json.dumps(
            {"source": "synthetic", "sha256": hashlib.sha256(raw).hexdigest(), "bounds": [west - pad, south - pad, east + pad, north + pad]}
        )
    )
    return tmp_path / "worlds"
