# Implementation plan

Status: **Draft for discussion.** Companion to `design.md`. Phases are ordered so each ends with something runnable and committable.

## Phase 0: Baseline and fixtures

- Run the app, confirm `mix precommit` and the importer help still work after the dependency changes.
- DONE: `gis/tests/` has pytest with a synthetic `.osm` fixture (`gis/tests/conftest.py`); dev deps live in `gis/pyproject.toml`.
- Check `requests` is declared in `requirements.txt`.
- **Done when:** importer tests run and fail or pass meaningfully against the draft.

## Phase 1: Harden the importer on synthetic data

- Cases: parallel edges, loops, access variants, disconnected component, boundary-crossing way, dead end at buffer edge.
- Determinism test (two builds byte-identical).
- Fix what the tests expose (likely the edge ID and context-relation questions).
- Decide and apply the highway whitelist.
- **Done when:** tests pass; `build`/`validate` work offline against the fixture.

## Phase 2: Acquire real data

- Run `acquire` once (network), review the manifest, decide whether to commit the snapshot (check size).
- `build` + `validate` on Madison; inspect counts, components, access distribution, a few spot checks against a real map.
- Set the buffer and access policy after seeing real output.
- **Done when:** real `nodes/edges/context/provenance` files are committed with a recorded snapshot checksum.

## Phase 3: Read-only viewer

- Phoenix `World` module: load and validate world files, expose them as JSON (`GET /worlds/:name/{nodes,edges,context,authored}`), compute staleness from `provenance.json`.
- Replace the landing page with the map page: MapLibre (vendored), basemap choice, boundary and extent overlays, edge styling by access, layer toggles, inspector, component list, attribution.
- Tests: loader, staleness, controller, page renders.
- **Done when:** the real Madison data can be explored and every imported property inspected.

## Phase 4: Authored layer, view and save

- Authored schema, validator, atomic save endpoint with stale-file check, reference-status computation.
- Render authored objects; "detached" styling; review list.
- Tests: schema validation, round trip, stale save rejection, reference statuses (ok, moved, missing).
- **Done when:** a hand-edited `authored.json` displays correctly and invalid files give clear errors.

## Phase 5: Editing tools

- Place/rename/move/delete location; snap to node or edge or free point.
- Fictional connection between two locations.
- Close/restrict an edge.
- Unsaved-changes indicator, Save, Discard, leave-page guard.
- Boundary editing with staleness banner (if included in milestone 1).
- **Done when:** a scripted edit session produces a small, readable Git diff.

## Phase 6: Regeneration and reference review

- UI action to run `build` (never `acquire`) and show success or error output.
- Reference review panel: missing/moved items with reconnect, keep fictional, remove.
- Test by editing the fixture snapshot to move or delete features and checking flagged references.
- **Done when:** a simulated OSM update surfaces affected authored items without altering them.

## Phase 7: Project hygiene

- README with run instructions for Elixir and Python; update `implementation-status.md`.
- `mix precommit` plus `pytest` as one documented check script.
- CI configuration once a host is chosen.
- Remove unused Phoenix boilerplate.

## Product decisions and ambiguities to work through

Recommendations in bold. Please push back on any.

1. **Milestone 1 editor actions.** Which of: place/name locations, move locations, connect locations, close edges, edit boundary, edit import config? **Locations + fictional connections + closures; boundary and config edited by file for now.** It keeps the editor from forcing regeneration flows into the first release.
2. **Closures semantics.** Does a closure override the imported access classification or just annotate it? **Annotate and layer: imported value stays visible, authored value is what the "game view" uses.**
3. **Location anchoring.** Node only, or also edge-with-offset and free point? **All three, with free point allowed so fictional places need not sit on real streets.**
4. **Edge ID stability.** Content-hash IDs break on any geometry tweak. **Switch to way-id plus segment-index based IDs, with a geometry hash stored on authored references for the `moved` check.**
5. **LiveView or thin JS client.** **LiveView page with one JS hook for the map and server-validated save events;** least bespoke API, but drawing state lives in the browser either way.
6. **Draw library.** Terra Draw vs hand-rolled for milestone 1. **Hand-rolled click-to-place and drag for points and two-point lines; adopt Terra Draw only when boundary or polygon editing arrives.**
7. **Asset pipeline.** Vendor MapLibre as static files vs add esbuild. **Vendor; no Node toolchain.**
8. **Basemap.** Do we show raster/vector OSM tiles under our data, or only our own geometry? Tile usage policy and offline/local requirement matter. **Own geometry only at first (consistent with the offline principle); revisit.**
9. **Highway whitelist and access policy.** Include `cycleway`/`bridleway`? Keep `inspect_all` default? **Keep inspect_all; add `cycleway`; leave others out.**
10. **Context relations.** Include multipolygon buildings and water via relation handling, or accept the gap? **Include if it is cheap in Phase 1, else document it.**
11. **Concurrency model on save.** Single-user; reject save if the file changed on disk. **Yes.**
12. **Undo.** None beyond Discard in milestone 1. **Yes.**
13. **Snapshot in Git.** Decide once file size is known (Phase 2).
14. **Game title and world naming.** Not needed now; the world is called "Madison · First Settlement" in config.
15. **Real-world access disclaimer.** Show a visible note that map presence does not imply permission to enter. **Yes, in the inspector and legend.**
