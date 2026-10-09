# Implementation status

Last updated: October 8, 2026. This file separates what exists and has been verified from what is active, planned or deferred. The operational task list is [implementation-plan.md](implementation-plan.md).

## Completed and verified

Verified means exercised by an automated test and/or by driving the app in headless Firefox during development. `make check` (Elixir tests, Python tests, ruff, TypeScript type check, world validation, determinism) passed when this was last updated.

- **Geographic pipeline** (`gis/`, Python/OSMnx): acquire (the only networked step), build and validate. A pinned Overpass snapshot of the Madison rectangle plus a 250 m buffer is committed, with checksum and manifest. Generated nodes, edges, context and provenance are deterministic and covered by a byte-identical rebuild check. Edge IDs are topological (`edge:<from>-<to>-<lowest way id>`) with a separate geometry hash. Closed `area=yes` ways are context (pedestrian areas), not edges; cycleways are in the graph; elevators are kept as `vertical` context.
- **Read-only viewer** (Phoenix LiveView + a TypeScript MapLibre hook): layers, access/type/component colouring, legend with counts, components list, inspector, staleness banner. No basemap.
- **Authored layer:** strict schema and validation, deterministic conflict-checked atomic save, reference status (ok / moved / missing) for node, edge and closure references.
- **Editing tools:** inspect, place (snaps to node, edge with offset, or free point), move, connect, close street, boundary editing (Terra Draw), Save and Discard with an unsaved-changes indicator and leave-page guard. Saving a boundary makes the geography stale and is refused if boundary plus buffer exceeds the pinned snapshot.

## Known limitations and untested areas

- The in-UI regeneration action and reference "reconnect" workflow are not built; regeneration is `make build-world`.
- Network review done (see [network-review.md](network-review.md)): undirected edges are correct for walking; open items are retaining sidewalk/crossing tags, an optional derived access basis, and plaza/entrance handling in the playable-node layer.
- The full designer workflow was driven in headless Firefox against a scratch copy of the world, not against a long editing session on the committed Madison files; no browser tests are automated (the LiveView tests do not exercise Terra Draw).
- Map labels are not drawn (they would need a font source); names appear in the inspector.
- Shapely emits a deprecation warning from the importer.
- No CI provider or deployment target is configured. `make check` is the intended single CI entry point.

## Active

Finishing and reviewing the editor milestone (plan Phases 5-6): the Phase 5 tools are implemented; Phase 6 covers in-UI regeneration and reference review.

## Planned

1. Apply the agreed fixes from the network review (retain sidewalk/crossing tags; decide on a derived access basis).
2. Playable-node experiment: generate two or three candidate location networks from the same data and compare density and connectivity (hypothesis: roughly 40-100 m between ordinary locations) before choosing an approach. Imported routing topology and playable locations stay distinct.
3. PostgreSQL/PostGIS and Ecto, introduced with the first persistent gameplay increment. World files remain the reproducible source artifacts.
4. Smallest playable movement system in Elixir (destination, route, confirm, stop on interruption).

## Deferred

Radio, encounters, null zones, Backrooms, achievements, cartography/knowledge UI, a dark "field-map" style, multiplayer, hosted deployment, CI provider selection.

## Environment

Elixir 1.19 / OTP 26, Python 3.12 and Bun (see `.tool-versions` and the README). Bun is installed at `~/.bun/bin` and added to PATH by the Makefile.
