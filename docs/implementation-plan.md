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
- **Status: implemented** (viewer, layer toggles, color modes, legend, components list, inspector, staleness banner). Verified in headless Firefox on the real data. Terra Draw is installed but not started until Phase 5.

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

1. **Milestone 1 editor actions. DECIDED.** Place/name locations, move/delete locations, fictional connections, close/restrict edges, **and boundary editing**. Import config (buffer, access policy) stays a file edit. Consequence: the staleness banner and the in-UI `build` action (Phase 6) are needed for milestone 1, not deferred. Boundary editing needs a polygon/rectangle draw tool, so the draw-library choice (#6) should be revisited.
2. **Closures semantics. DECIDED.** Layered, not overriding: the imported access value stays untouched and visible; a closure is a separate authored record applying to a whole edge. One kind (`restricted`) plus a free-text reason. The editor stores and displays closures but enforces nothing; game meaning (e.g. a distinct `blocked` kind) is deferred and can be added as a new `kind` value without a schema change.
3. **Location anchoring. DECIDED.** Three anchor kinds: node, edge with fractional offset, and free point. Free points let fictional places exist off the street network.
4. **Edge ID stability. DECIDED and implemented.** Edge ID = `edge:<from node>-<to node>-<lowest OSM way id>`, with a deterministic `-1`, `-2` suffix only when distinct geometries share the same ends and way. Shape tweaks keep the ID; a separate `geometry_hash` property lets authored references detect a "moved" edge. Splitting an edge (new intersection) or deleting it changes or removes the ID and is flagged as missing. Refine later if real OSM updates show too much churn.
5. **Editor architecture. DECIDED: LiveView** with one JS hook that owns MapLibre and Terra Draw. The server holds the authoritative working copy (validation, reference status, staleness, save-conflict check). Geography is sent once as static JSON, not over the socket; only authored edits travel over the socket.
6. **Draw library. DECIDED: Terra Draw**, used for locations, connections and boundary editing from the start. Check its MapLibre adapter and how it is vendored without a Node pipeline (decision 7).
7. **Asset pipeline. DECIDED (revised): Bun + TypeScript.** `assets/` holds a TypeScript project (MapLibre, Terra Draw and its MapLibre adapter from npm; Phoenix JS from `deps/`). `bun build.ts` bundles to `priv/static/assets/js/app.js` (gitignored, built by `make setup`/`make assets`); `tsc --noEmit` type-checks in `make check`. The Terra Draw MapLibre adapter exists on npm (`terra-draw-maplibre-gl-adapter`), which resolved the earlier open question. No Node, no esbuild.
8. **Basemap. DECIDED: none.** Only imported geography on a plain background, which keeps the app offline and makes the game world's extent obvious. An optional toggled basemap can be added later.
9. **Path types and access policy. DECIDED in principle; details settled after inspecting real data.** Keep `inspect_all`. Import everything and classify rather than drop. Walkable network (graph): current whitelist plus `cycleway`. `road_context`: motorway/trunk and their links are drawn as map context but are not in the graph, so they cannot join components or anchor locations. Also context only: construction, proposed, platforms, indoor corridors. `vertical`: `highway=elevator` features are kept; the Monona Terrace bike elevator should be **traversable** (a vertical graph connection), and retain `level`/`layer` tags. How it is actually mapped in OSM is unknown until the first import. Acquire fetches standalone elevator nodes and multipolygon relations so options stay open. Stairs (`steps`) stay in the graph.
10. **Context relations. RESOLVED.** The first import includes building, park and water relations; both lakes render, so no further work is needed.
11. **Concurrency model on save.** **DECIDED.** Single-user; reject a save if the file changed on disk since it was loaded.
12. **Undo.** **DECIDED.** None beyond Discard in milestone 1.
13. **Snapshot in Git. DECIDED.** Commit the snapshot and the generated files as-is (no LFS, no gzip, indented key-sorted JSON for readable diffs). Measured: about 1.8 MB compressed in `.git`. `make check` verifies the committed output is byte-identical to a rebuild.

16. **Sidewalk-level graph. DECIDED.** Keep the graph as imported, including parallel sidewalk and crossing edges. Any simplified movement layer is deferred.
14. **Game title and world naming.** Not needed now; the world is called "Madison · First Settlement" in config.
15. **Real-world access disclaimer.** **DECIDED.** Show a visible note, in the inspector and legend, that map presence does not imply permission to enter.
