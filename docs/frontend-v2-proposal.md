# Frontend V2: architecture and design proposal (Milestone 1)

Date: 2026-10-09. A review for the project owner to approve; no V2 code exists. It answers the ten questions in section 17 of [frontend-v2-memo-2026-10-09.md](frontend-v2-memo-2026-10-09.md) with one recommendation, using what the current code taught us.

## What V1 actually looks like (facts that drive the recommendation)

- Two LiveViews and two TypeScript hooks. **Atlas** (`play_live.ex` 288 lines, `player_map.ts` 177) is a thin client: the server computes everything the player may do and sends it as `data-state`; the browser renders markers and animates. **Studio** (`editor_live.ex` 1,045 lines with 34 event handlers, `editor_components.ex` 512, `map_editor.ts` 463) is the heavy one: the server owns the working copy and validates every edit, while the hook holds tool modes, Terra Draw, snapping and drag state.
- The bundle is already ~2 MB, almost all MapLibre and Terra Draw. A UI framework would add a few kilobytes; bundle size is not a deciding factor.
- Domain rules already live on the server and are tested there: save conflicts and locking, edge-anchor derivation, route resolution, movement validation. The reliability work made these dependable.
- What hurts today is concentrated in Studio: the inspector, spawn section, route check and regeneration panel are large server-rendered templates driven by many round trips, and the hook and LiveView must agree on modes and selection. Atlas has no comparable pain.

## 1. LiveView, Preact or SolidJS?

**Keep LiveView for Field Atlas. Move Studio's interactive surface to Preact, and keep Phoenix as the only backend.** Do not adopt Solid.

- Atlas is "server decides, client draws". LiveView plus a plain hook is the simplest correct design, and V1 already has numbered shortcuts, camera limits and one-hop movement on it. A rewrite would add a client/server contract with no benefit. V2 for Atlas is therefore a visual and interaction redesign, not an architecture change.
- Studio is where client-owned interaction state (tool, selection, drag, snapping previews, unsaved draft, undo) is the product. Preact gives a small component model and local state for exactly that, shares TypeScript with the map code, and avoids each field edit being a server round trip. Preact over Solid: same capability for this job, familiar React-style model, no extra novelty.
- Rejected: a single stack for both (forces Atlas into an API it does not need), and "LiveView only" for Studio (the hook/LiveView coupling is the existing pain and would worsen with undo, previews and curved label editing).

## 2. Separating map state from UI state

Three owners, no overlap:

- **MapLibre controller (framework-free TypeScript):** sources, layers, camera, hit testing, Terra Draw. Created once per page; never re-created by a render. Reads data through setters (`setLocations`, `setSelection`, ...), never from component props.
- **Studio store (Preact signals or a plain store, no state framework):** tool mode, selection, hover, draft working copy, undo stack, panel layout. Panels subscribe; the controller subscribes to the few things it draws (selection, draft features).
- **Server:** canonical authored layer, revisions, validation. Large geography (edges, nodes, context) never enters the store: the controller loads the pinned snapshot (`?generation=`) straight into MapLibre sources.

Atlas keeps `data-state` from the server and the existing controller; only styling and layout change.

## 3. API boundaries needed

Studio needs explicit JSON endpoints, all calling existing domain functions (no second validation path):

- `GET /api/worlds/:w/authored` returns the document and its revision hash.
- `PUT /api/worlds/:w/authored` with the base hash, calling `Authored.save/3` (so locking and conflicts are unchanged); returns the new hash or a conflict with the current document.
- `POST /api/worlds/:w/resolve-anchor` and `POST .../route-check` for server-derived anchors and route results (`Edit.resolve_anchor/2`, `RouteResolver`), so the client never computes authority.
- Boundary save and regeneration keep their present functions behind equivalent endpoints; regeneration reports through the same flash/outcome.
- Geography and generated layers keep `WorldController`.

Atlas needs no new API: movement stays a LiveView event validated by `Sessions.move/3`. If a non-LiveView client is ever wanted, the same function sits behind one `POST /api/play/move`.

## 4. Studio editor interactions

- Layout per the memo: map dominant, compact left panel (layers, search, object list), contextual right inspector, top bar with world name, **Saved / Unsaved / Conflict** state, Undo/Redo, and a diagnostics drawer that merges today's route check, references and regeneration output.
- Tools by intent: Select, Place node, Link, Close street, Boundary. Snapping is always an explicit preview (intersection, mid-block edge position, free point) showing the street it would use.
- With authored places as traversable nodes, **Place node** has two outcomes: on an intersection, or on a street at an offset. A free point is allowed only as a deliberate, flagged choice ("not walkable"). This removes the free-point class of problem the audit found.
- Connections draw their resolved street route when one exists and a dashed straight line when not, so walks and anything else are visibly different.
- Saving is explicit; a conflict shows both versions and the editor never overwrites silently. The draft survives refresh in `localStorage` as a recovery copy offered, never applied, on reload.

## 5. Field Atlas one-hop exploration

Already implemented in V1 and carried over unchanged: server-computed adjacent moves with radial numbers, markers and panel numbered identically, keyboard and click through one request path, camera tether and zoom limits, animation along the validated route. V2 work is the visual treatment and the mobile bottom sheet.

## 6. Shared visual system

One token file (colour, type, spacing) used by both apps through CSS variables, and one MapLibre style module producing the cartographic style: warm ivory ground, sage parks, slate paths, restrained buildings, teal movement, amber for authored/anomaly. Studio adds diagnostic colours; Atlas adds none. Typography is a functional sans for UI with small, restrained monospace for metadata; labels need a glyph source (see Risks). Topography stays a research track; no elevation pipeline without a separate decision.

## 7. Smallest convincing vertical slice

**Studio, one workflow end to end:** select an authored place, change what it is (intersection / mid-block / free point) with a snapping preview, inspect its resolved routes, save through `PUT .../authored` with conflict handling, reload and see it persisted. It exercises the store, the controller, the API, locking and the resolver together. Atlas needs no slice because its architecture is unchanged.

## 8. Preserving V1 and designer data

V2 runs beside V1 at `/studio-v2`; V1 routes and `authored.json` are untouched. V2 saves go through the same `Authored.save/3`, so V1 and V2 sessions conflict-check against each other. Nothing in V2 is allowed to write generated files or the boundary until those workflows are migrated and tested. Develop against a scratch worlds directory (`THRESHOLD_WORLDS_DIR`).

## 9. New tests

- Bun unit tests for the store, undo/redo and snapping logic (pure), alongside the existing `camera` and `shortcuts` tests.
- Controller tests with a fake MapLibre surface for layer/selection wiring.
- API tests in ExUnit for the endpoints: conflict, locking, forged coordinates, revision mismatch.
- Browser workflow tests: the verification already done by hand with headless Firefox over Marionette is scriptable and should become a small automated suite (open Studio, select, edit, save, reload; Atlas: spawn, key move, reload), run separately from `make check` until it is stable.

## 10. What depends on current work

- The effective-graph decision (authored as default graph, how it meets generated scaffolding) decides what Place node means and what Atlas draws.
- The `travel` field and spawns on authored places (schema decisions) shape the inspector.
- The two free points and the "unreviewed connection" meaning shape the diagnostics drawer.
- Curved cartographic labels need a glyph/font source decision (offline vs bundled glyphs) first.

## Sequence

1. Settle the open designer decisions above (no code).
2. Shared tokens and map style module, adopted by V1 Atlas first (low risk, visible).
3. Studio API endpoints over existing domain functions, with tests.
4. Studio vertical slice at `/studio-v2` (Preact + controller + store).
5. Migrate remaining Studio tools one workflow at a time; retire V1 Studio only after each is equivalent.
6. Cartographic labels after the core Studio workflow, once the glyph decision is made.

## Risks and open questions

- **Glyphs:** MapLibre symbol text needs glyph PBFs, and the style is intentionally offline. Options: bundle a few font glyph sets locally, or render curved labels outside MapLibre's text pipeline. Decide before label work.
- **Two UI technologies:** LiveView and Preact coexist. Keep Preact confined to `/studio-v2` and the shared map code framework-free, so Atlas never depends on it.
- **Duplicated rules:** the client must not re-implement validation; every edit result comes from the server. Any rule found on the client during review is a bug to move.
