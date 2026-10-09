# Implementation status

Last updated: October 8, 2026. This file separates what exists and has been verified from what is active, planned or deferred. The operational task list is [implementation-plan.md](implementation-plan.md).

## Completed and verified

Verified means exercised by an automated test and/or by driving the app in headless Firefox during development. `make check` (Elixir tests, Python tests, ruff, TypeScript type check, world validation, determinism) passed when this was last updated.

- **Geographic pipeline** (`gis/`, Python/OSMnx): acquire (the only networked step), build and validate. A pinned Overpass snapshot of the Madison rectangle plus a 250 m buffer is committed, with checksum and manifest. Generated nodes, edges, context and provenance are deterministic and covered by a byte-identical rebuild check. Edge IDs are topological (`edge:<from>-<to>-<lowest way id>`) with a separate geometry hash. Closed `area=yes` ways are context (pedestrian areas), not edges; cycleways are in the graph; elevators are kept as `vertical` context.
- **Read-only viewer** (Phoenix LiveView + a TypeScript MapLibre hook): layers, access/type/component colouring, legend with counts, components list, inspector, staleness banner. No basemap.
- **Authored layer:** strict schema and validation, deterministic conflict-checked atomic save, reference status (ok / moved / missing) for node, edge and closure references.
- **Editing tools:** inspect, place (snaps to node, edge with offset, or free point), move, connect, close street, boundary editing (Terra Draw), Save and Discard with an unsaved-changes indicator and leave-page guard. Saving a boundary makes the geography stale and is refused if boundary plus buffer exceeds the pinned snapshot.

- **Playable-location layer (candidate):** `threshold-gis playable` builds a derived network (graph-radius clustering, 25 m) beside the imported files with connectivity-integrity diagnostics and designer retain/suppress overrides; the editor displays it, flags staleness, and saves overrides with the authored layer. Verified by Python and Elixir tests and in headless Firefox. Playable connections now contain continuous source-network routes, ordered edge/node lists and actual route geometry; route integrity was audited on Madison and tested on synthetic data. See [playable-route-review.md](playable-route-review.md) for results and gameplay limits. Playability remains untested.

## Known limitations and untested areas

- Regeneration and reference repair are implemented. Regeneration stages an offline build, playable build and validation before publishing generated files; saved-input changes reject publication. The editor preserves authored working data and save-conflict hashes. Missing/moved references open the inspector for deliberate reconnection, detachment or removal. Browser checks on a scratch Madison world exercised boundary drag/save/regenerate, map refresh, location-to-edge reconnection and missing-closure reconnection/save. Automated tests cover missing/moved references, unsaved guards and failed-build preservation. An end-to-end synthetic source update moved node 2 and removed way 105; in-editor regeneration flagged the location as moved and the closure as missing, and authored.json remained byte-identical. Browser console inspection during hot reload reported one MutationObserver error; the exercised editing, saving and regeneration actions still completed.
- Network review done (see [network-review.md](network-review.md)): undirected edges are correct for walking; open items are retaining sidewalk/crossing tags, an optional derived access basis, and plaza/entrance handling in the playable-node layer.
- The full designer workflow was driven in headless Firefox against a scratch copy of the world, not against a long editing session on the committed Madison files; no browser tests are automated (the LiveView tests do not exercise Terra Draw).
- Map labels are not drawn (they would need a font source); names appear in the inspector.
- Shapely emits a deprecation warning from the importer.
- No CI provider or deployment target is configured. `make check` is the intended single CI entry point.

## Active

Reviewing the editor milestone (plan Phases 5-6): both editing and regeneration/reference-repair workflows are implemented. The next evaluation concerns playable graph route integrity and suitability for gameplay.

## Planned

1. Apply the agreed fixes from the network review (retain sidewalk/crossing tags; decide on a derived access basis).
2. Playable-node approach: an experiment compared candidate networks ([playable-node-experiment.md](playable-node-experiment.md)); graph-radius clustering preserved connectivity, proximity merging did not. Productized as a derived layer; alleys are protected and plaza gaps are not bridged as provisional choices (undecided by the designer). Imported routing topology and playable locations stay distinct.
3. PostgreSQL/PostGIS and Ecto, introduced with the first persistent gameplay increment. World files remain the reproducible source artifacts.
4. Smallest playable movement system in Elixir (destination, route, confirm, stop on interruption).

## Deferred

Radio, encounters, null zones, Backrooms, achievements, cartography/knowledge UI, a dark "field-map" style, multiplayer, hosted deployment, CI provider selection.

## Environment

Elixir 1.19 / OTP 26, Python 3.12 and Bun (see `.tool-versions` and the README). Bun is installed at `~/.bun/bin` and added to PATH by the Makefile.
