# Expanded world: verification report

Date: 2026-10-09, at commit `dae24a1` plus the changes listed at the end. Everything here was measured or exercised on **scratch copies** of the committed world (`git archive` of HEAD, in the session scratchpad, served on a separate port with a disposable test database) or read-only against a copy of the designer's working tree. The real `priv/worlds/madison/boundary.geojson` and `authored.json` were not modified, no OSM data was acquired, and nothing was pushed. Browser behaviour is headless Firefox driven over Marionette (real pointer and key events); where a result is from a test or a script rather than the browser, it says so.

At the time of the check the designer's working tree had an uncommitted, reshaped playable boundary (28 vertices, extending west to lon -89.4036) and a regenerated geography (`generations/8e77e42a1f82`). That work was left alone and was used only for the read-only diagnostics in section 4.

## 1. Studio boundary workflow on the 5.7 x 3.5 km import

| # | Requirement | Result | How |
|---|---|---|---|
| 1 | Enlarged extent renders | Pass. The whole isthmus from campus to the east side, both lakes, authored places and spawns; the editor was interactive 2.3-5.6 s after navigation (first load slower) | browser |
| 2 | Extent and playable boundary visually distinct | Pass. Dashed grey import rectangle (`extent-line`) versus a solid red playable boundary with an outside mask | browser, screenshots |
| 3 | Boundary tool manipulates the polygon | Pass. A real mouse drag of the SE corner moved it and the server marked the change unsaved after 0.69 s | browser |
| 4 | Saving a valid boundary | Pass. Flash "Boundary saved", `boundary.geojson` changed on disk, stale banner appeared, `authored.json` byte-identical | browser + file hashes |
| 5 | Regeneration publishes one consistent revision | Pass. 29.7 s; new snapshot `b132c4e98eaa`; the `generated` symlink flipped once; stale banner cleared; build output ended "Valid geometry, topology, references, boundary, and source checksum" | browser + filesystem |
| 6 | Reload preserves the boundary | Pass. Same corner coordinates after a full reload | browser |
| 7 | Movement graph respects the new region | Pass (script, on a scratch copy). Halving the boundary and regenerating left 28 of 59 authored places standing outside it; 45 connections became unavailable (`outside_boundary`), 0 moves lead from an inside place to an outside one, 0 are offered from outside places, and the default spawn, now outside, makes `Game.start` refuse | `mix run` on scratch |
| 8 | Invalid boundary rejected without altering data | Pass, with two mechanisms. A corner dragged past the import area is accepted as a draft and **refused at Save** ("That boundary reaches beyond the import area..."), disk unchanged, draft kept for fixing. A drag that would make the outline cross itself is **stopped live by Terra Draw** at the last valid position (the server also rejects crossing outlines; covered by an existing test) | browser + tests |
| 9 | Authored places, connections and spawns intact | Pass. `authored.json` hash identical before and after save, regenerate and the invalid attempts | file hashes |
| 10 | Responsive on the larger dataset | Pass. During the corner drag 43 frames, max gap 17 ms; 20 animated pan/zoom jumps over the whole area gave 365 frames, median/p95/max 17 ms, none over 50 ms | browser frame sampling |

Findings from this run:

- A clear message appears for the out-of-area case, but nothing warns until Save. A live "outside the import area" indication while dragging would be friendlier. (Not built.)
- After the default spawn leaves the boundary the page used to say "The default spawn has no usable movement options." That is now "The default spawn lies outside the playable boundary..." (fixed, tested).
- Regeneration of the full import takes about 30 s with a progress message; acceptable, but it blocks editing.
- Not exercised: touch input, keyboard-only boundary editing, very small slivers, a boundary that touches the extent edge exactly.

### New controls (requested)

The editor's "Playable boundary" section now has **Reset to saved**, **Reset to default** (reads `default_boundary.geojson`; Madison's is the original First Settlement rectangle), **Expand to import area**, and **Fit to boundary**. Resets change only the working boundary (unsaved until Save). Verified in the browser: expand filled the import rectangle, reset to default and to saved restored the expected corners, the indicator read "Unsaved changes" until the reset to saved, the disk file never changed, and Fit to boundary reframed the map (zoom 12.8 for the whole area, 14.5 for the default). 7 LiveView tests and 5 unit tests cover it.

## 2. Field Atlas loading, measured

Scratch Madison, committed boundary, 1366 x 768 screen, headless Firefox on the same machine. The "earlier" column is the figure reported before the bbox work, taken on the previous 3.8 x 2.4 km import.

| Measure | Earlier | Now |
|---|---|---|
| Geography on disk for edges + context | about 19 MB (3.8 x 2.4 km) | 30.6 MB (5.7 x 3.5 km): 20.4 MB edges + 10.2 MB context |
| Geography decoded by the browser for `/play` | the whole files | 7.8 MB (edges 6.2 MB, context 1.7 MB), clipped to the area the camera can reach |
| Geography on the wire (browser sends gzip) | about 19 MB | **0.96 MB** (edges 657 KB, context 302 KB); uncompressed `curl` of the same clipped URLs: 7.8 MB + 2.2 MB |
| Time to a usable map (style loaded, edges source present, numbered markers drawn) | about 5.8 s | **1.3-1.6 s** (3.2 s on the very first load of a fresh server, which also pays the JS bundle and server decode) |
| First clipped request, cold server cache | n/a | 1.56 s edges + 0.34 s context (decode 20 MB JSON, filter, encode) |
| Repeat clipped request | n/a | 45 ms edges, 19 ms context (cached) |
| Keypress to updated turn on screen | n/a | 150-175 ms warm; the first two moves of a fresh server took 487 and 542 ms |
| Server work per move, authored graph (default) | about 110 ms | 130-150 ms warm |
| Server work per move, generated graph | n/a | 235 ms warm |
| Memory | n/a | `persistent_term` 53 MB; BEAM 175 MB in a script, 417 MB resident for the dev server |

Breakdown of one authored-graph load, warm: world metadata 10 ms; read and parse `authored.json` 5 ms; read the 20 MB edges file 20 ms; hash it 20 ms; decoded JSON 9 ms (cached; 0.9 s cold); route resolution 80-100 ms (rebuilds the adjacency over all 20,657 edges and runs 98 searches every time); the rest is validation. Cold decode of the edges file costs 0.9 s and of the node/edge geography index 0.6 s, paid once per generation.

### Filtering correctness

- `?bbox=` keeps every feature whose extent touches the box and returns it **whole**; features are not clipped, so a street crossing the box keeps vertices outside it (tested). The response is still a valid FeatureCollection.
- Malformed, reversed, empty, NaN and out-of-range boxes fall back to the full layer or return an empty/complete collection predictably (tested).
- A defect found and fixed: the margin was a fixed 800 m, which a 4K-wide window at the minimum zoom (0.436 m per CSS pixel) would outrun. The box is now the boundary plus the tether plus half the largest **screen** dimension at the minimum zoom (498 m on this 1366 px screen, about 1,040 m on 3840 px), tested.
- Game validity does not depend on the clipped layers: movement is validated on the server from the unclipped files.
- **Spoiler exposure (not fixed):** `/worlds/:world/authored` (all places and notes), `playable` and `provenance` are served to any client. `/play` does not request them, but anyone can. For a local single-player build that is acceptable; before any distribution these layers should be limited to the editor. Recommended.

## 3. Runtime world loading

Each LiveView event reloads the world: reads the 20 MB edges file to hash it for the revision, rebuilds the routing graph, and re-resolves 98 routes (authored) or revalidates 3,076 connections (generated). It does not re-decode JSON (cached by content, JsonCache). Measured cost is 130-235 ms per move, growing with the import size, with no change needed for correctness.

Recommendation (not implemented, as the measurements show it is acceptable today): (a) derive the revision from the immutable generation id instead of hashing the edges bytes (the id already digests all five generated files); (b) keep one immutable runtime world per revision in the existing recency cache, keyed by authored hash, boundary hash, generation id and graph mode, which respects atomic publication, authored edits, boundary changes and graph choice by construction; (c) build the authored routing graph only from edges inside the playable boundary. Expected per-move server work is then about 15-25 ms. No process per player, no distributed cache.

## 4. Authored graph diagnostics (designer's working copy, read-only)

Boundary and geography as the designer has them now (generation `8e77e42a1f82`, fresh):

- 59 of 60 places stand inside the playable boundary; the 60th, `loc:9821f05090ce`, is a free point and has no standing position.
- Place classes: 52 on or within 8 m of an intersection, 7 mid-block, 1 free point.
- 90 of 98 connections resolve to walks (33-213 m, median 97 m, mean 99 m), none blocked by access, closures or the boundary, none a long detour.
- The 8 unresolved connections all touch `loc:9821f05090ce` (`conn:1c6d2ceb69d4 26044b059617 3106fb10e52e 4bc88d8c01cd 7d4c353afd24 81e155811ed8 9c49c05c17b0 aa83ef7080bf`).
- The authored graph has 59 playable places and 90 walks; all 59 are reachable from the default spawn (`spawn:db793a6a4228`, mapped to an authored place 13.8 m away). One non-default spawn (`spawn:add6aae53325`) is 95 m from any authored place and is skipped; two places (`loc:742660a27859`, `loc:9514e272ab78`) share an intersection.
- No authored place was altered, snapped or removed.

### Changed source reference

`loc:bd9bbe31c34a` remains flagged **moved** against the newest snapshot. Its edge `edge:53326149-3414444398-6758194` still exists, but its recorded geometry hash (`dbf74cccf5ca5337`) differs from the current one (`5228035ea410db8d`). The point implied by its stored offset on the updated edge is 0.45 m from the authored point, so the change is small, but the system correctly refuses to accept it silently. The existing review workflow opens the inspector for reconnect or detach. What is missing is a **compare and accept** action: show the authored point and the updated-edge point together with the distance, and offer "accept the updated street shape" (refresh the recorded hash and derived point, keeping the offset, id, notes and connections), "reconnect to another street", or "detach". Recommended as a small editor increment; it needs no schema change.

## 5. Display position versus walking access

### What exists

A location has `anchor` (`node`, `edge` with `offset`, or `point`), always with a `point`. For `node` and `edge` anchors the server derives the point from the network, so the display position and the walking position are the same place. A `point` anchor has only a display position and therefore no way to be reached on foot, which is exactly the free-point problem. `movement_location` (an optional `pn:` id) attaches a place to the *generated* playable graph; it is unrelated to the authored graph and is unused in the real data. `RouteResolver` decides where a place stands from its anchor alone, and `EffectiveGraph` uses that standing point as the location's point.

### Smallest backward-compatible model

Keep `anchor` exactly as it is and add one optional field:

```json
"access": { "kind": "edge", "ref": "edge:...", "offset": 0.4, "ref_geometry_hash": "..." }
```

or `{ "kind": "node", "ref": "node:..." }`. It has the same shape as a network anchor without a client-supplied point (the server derives it, as for edge anchors today).

- **Display position** is `anchor.point` (a free point is now a legitimate display-only choice).
- **Geographic access anchor** is `access`, and when absent it is the `anchor` itself if that is a node or edge (so every existing place behaves as it does today). A free point with no `access` stays unwalkable, as now.
- **Game position** is the location id: the logical place the player occupies. Nothing about it changes; later interiors can attach to it.

### Effects

- **Existing authored data:** none. All 60 places keep working and no coordinate changes. The free-point place stays as the designer left it until an `access` is chosen for it.
- **Route resolution:** `position/4` uses `access || anchor`; the standing point comes from `access`; the place keeps its display point alongside it.
- **Effective graph and Atlas:** movement markers and routes use the standing (access) point, because that is where the player goes; the authored place's own marker uses the display point. Spawn mapping uses the standing point.
- **Validation and references:** the schema gains one optional key; moved or missing `access` edges are reported like anchors.
- **Editing interaction:** the inspector shows "Display position" (draggable) and "Walking access" (Same as display / On street / None), with candidate streets and intersections within a stated distance and a line drawn from the display marker to the access point. The Route check offers, for each unwalkable place, "Set walking access to the nearest street (3.4 m)" without moving its marker; the designer chooses.

This needs the designer's approval before any schema change (the memo and AGENTS both say so); none was made.

## 6. Prioritised next steps

1. **Decide the access model** (section 5) and, if approved, implement `access` end to end with the inspector and Route check actions. Resolves the 8 unwalkable connections without moving any marker.
2. **Compare-and-accept for moved anchors** (section 4); no schema change.
3. **Runtime world cache and revision from the generation id** (section 3), after the access model, since it touches the same loader.
4. **Restrict the `authored`, `playable` and `provenance` layers to the editor** before any distribution (section 2).
5. **Live feedback while dragging the boundary** (outside the import area), and an "area" read-out.
6. **Frontend V2 and the Classic Atlas visual system** (see `frontend-v2-proposal.md`), starting with the shared style module and tokens.

## Changes made while verifying

- Reset Boundary and Fit to Boundary controls, `default_boundary.geojson` for Madison (`e3da7fd`).
- The player map's geography request is sized from the screen; whole-feature selection and odd-bbox tests (`e92f777`).
- The Python pipeline tests no longer depend on the live Madison boundary, which broke when the designer reshaped it (`dae24a1`).
- A clear error when the default spawn lies outside the boundary.
