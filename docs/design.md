# Geographic editor design

Status: **Draft for discussion.** Items marked **[DECIDE]** are product questions; each is listed in `implementation-plan.md` with a recommendation. Nothing here overrides `project-decisions.md` until agreed.

## Goal

A local browser tool for a designer to view real Madison geography, then author a fictional layer on top of it, saving everything as reviewable files. No gameplay.

## Users and scope

One user (the designer), on localhost, no auth, no database. Success means: open the map, understand the imported geography (including its gaps and access caveats), make authored edits, save, and see a clean readable Git diff.

## Architecture

```text
 OSM snapshot ──► Python importer ──► generated geography ──┐
 (pinned, hashed)   gis (threshold-gis)  nodes/edges/context │ read-only
                                                              ▼
                       Phoenix (LiveView shell + JSON endpoints) ◄──► browser: MapLibre + draw lib
                                                              │
                                                              ▼
                                                    authored.json (only file the editor writes)
```

- **Importer** is a standalone CLI (`acquire`, `build`, `validate`). Only `acquire` touches the network. Phoenix may later shell out to `build`, never to `acquire`.
- **Phoenix** loads world files, validates, and writes `authored.json` atomically (temp file + rename). It holds no state beyond the files.
- **Browser** owns the map and interaction. One JS hook on a LiveView page (or plain JS served by Phoenix) mounts MapLibre. The pure-JS side stays small; **[DECIDE]** whether the editor is LiveView-driven (server holds the working copy) or a thin JS app that talks to JSON endpoints.
- **Frontend toolchain:** Bun + TypeScript in `assets/`, bundling MapLibre, Terra Draw and the Phoenix client to `priv/static/assets/js/app.js`. No Node.

## Data layers

Three layers, never merged on disk:

| Layer | Files | Written by | Editable in UI |
|---|---|---|---|
| Source | `source/snapshot.osm`, `source/manifest.json` | importer `acquire` | no |
| Generated geography | `nodes.geojson`, `edges.geojson`, `context.geojson`, `provenance.json` | importer `build` | no (view and inspect only) |
| Authored world | `authored.json` (+ `boundary.geojson`, `config.json`) | editor | yes |

`boundary.geojson` and `config.json` are inputs to the importer. Editing them in the UI means the generated layer is stale; see "Staleness" below.

### Identifiers

- Nodes: `node:<osm_id>`. Stable while OSM keeps that node, but simplification can drop intermediate nodes, so a node can vanish without being deleted in OSM.
- Edges: `edge:<from>-<to>-<lowest way id>` (suffix on collision). Shape edits keep the ID; `geometry_hash` flags them as moved. Topology changes (split or delete) produce missing references. See plan decision 4.
- Authored objects get their own UUID-style IDs (`loc:…`), independent of geography.

### Authored schema (proposed, v1)

```json
{
  "format_version": 1,
  "locations":   [{"id": "loc:…", "name": "", "notes": "", "anchor": {"kind": "node|edge|point", "ref": "node:123", "offset": null, "point": [lon, lat]}, "resolved": true}],
  "connections": [{"id": "conn:…", "from": "loc:…", "to": "loc:…", "kind": "fictional", "geometry": null, "notes": ""}],
  "closures":    [{"id": "clo:…", "edge": "edge:…", "access": "restricted", "reason": ""}]
}
```

Existing empty file already has `locations`, `connections`, `closures`. Open: do closures override imported access, or only annotate? Does a location anchored to an edge store a fractional position along it?

## Reference resolution

Every authored object that points at geography (`anchor.ref`, `closure.edge`) stores the ID **and** a fallback coordinate/snapshot of the target (position or geometry hash). On load the server computes a status per reference:

- `ok`: ID exists and the stored fallback still matches closely.
- `moved`: ID exists, geometry differs beyond a tolerance. Needs review.
- `missing`: ID absent. Object stays, rendered as detached at its fallback coordinate.

The editor shows a review list. It never silently rebinds, moves or deletes. Reconnect, keep as fictional, or remove are explicit actions. Matching suggestions (nearest node/edge) are display-only hints in the first milestone.

## Staleness

`provenance.json` records the config, boundary, source hash and pipeline hash used. The server compares those with the current files. Any mismatch (edited boundary, changed buffer, new importer) puts a persistent banner on the editor: "Geography is out of date; regenerate." Authored edits remain possible but the banner cannot be dismissed until `build` has been rerun. Editing the boundary beyond snapshot coverage is blocked with an explanation (importer already errors in this case).

## Editor UI

- **Map**: base streets/paths (edges coloured by access status, with a legend), nodes (toggle), context (buildings, parks, water, toggles), playable boundary overlay, buffered import extent (toggle), authored layer on top.
- **Layer panel**: toggles for each layer, access classes, components (colour per component, with disconnected components listed and zoom-to).
- **Inspector**: click any feature: source tags, classification, access status and why, component, OSM ids with link-out, length, inside/crosses boundary, and for authored objects the reference status.
- **Edit tools (milestone 1 candidates)**: place and name a location, move it, delete it, link two locations with a fictional connection, mark an edge closed/restricted, edit boundary rectangle/polygon.
- **Save model**: working copy in the browser or LiveView; explicit Save writes `authored.json`; unsaved changes are visible and prompt on leave; Discard reloads from disk. Save is refused if the file changed on disk since load (simple mtime/hash check). No auto-commit. No undo beyond Discard at first. **[DECIDE]**
- **Attribution**: "© OpenStreetMap contributors" always visible on the map.

## Importer notes (from reading the draft)

Things to verify or fix, not yet decided:

- `acquire` imports `requests` which is not in the Mix project and may not be in `requirements.txt`; check.
- Overpass query uses `way[building]` etc. but only ways, not building/water relations that carry multipolygons; context may miss large water bodies and some buildings.
- Context features are `intersects` the extent but not clipped; fine for display.
- `HIGHWAYS` excludes `cycleway`, `bridleway`, `corridor`, `proposed`, `construction`. Likely right for a walkable game but a product choice. **[DECIDE]**
- `access()` treats `destination`/`customers` as restricted and any other value as conditional; `foot:conditional` and `access:conditional` are retained as tags but not interpreted.
- `from`/`to` swap normalises direction, but `oneway` and bidirectional edges are collapsed to a single undirected edge; consistent with a pedestrian game but loses direction info.
- Graph is built in UTM 16N for buffering (EPSG:32616), correct for Madison.

## Testing strategy

- Importer: pytest on a tiny hand-written `.osm` fixture covering parallel edges, loops, access variants, a disconnected piece, and a boundary-crossing way; determinism test (build twice, compare bytes).
- Phoenix: unit tests for the world loader/validator and reference-status function; controller tests for load/save (including stale-file rejection); a LiveView test for the shell.
- No browser E2E initially; manual checklist for the map UI.

## Non-goals (this milestone)

Gameplay, multi-user editing, auth, a database, hosted deployment, automatic reference matching, undo/redo history, interior/Backrooms spaces.
