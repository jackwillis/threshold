# Authored-map integration audit (Increment D)

Date: 2026-10-09. Read-only. Run on a scratch copy of `priv/worlds/madison` (`THRESHOLD_WORLDS_DIR` pointed at the copy); the real `authored.json` was neither modified nor used by any test. Reproduce with `mix threshold.audit madison [--details]`, implemented by `Threshold.AttachmentAudit` (pure, tested on the `tiny` fixture) and `mix threshold.audit`.

## Update: route resolution on the street network (supersedes the walking comparison below)

The designer clarified that authored places are meant to be **traversable nodes**: street intersections, or sometimes halfway down a long block. That makes the authored graph the set of positions the player can stand on, with the real street network supplying the walk between them, rather than places needing an attachment to a separate playable graph. `mix threshold.routes [world] [--details]` (`Threshold.RouteResolver`, read-only, 8 tests) tests that model: a node anchor is its intersection; an edge anchor is a virtual node splitting its street at the stored offset; each authored connection is routed over the imported pedestrian network under the game's own rules (access status, vehicle service ways, authored closures, playable boundary). On a scratch copy of the real data:

- **52 of 60 places are within 8 m of an intersection** (median 1.4 m, max 7.9 m): the designer's snapping already put them on intersections. 6 are genuinely mid-block. **2 are free points** with no street position (`loc:6216b9ecc50a` "The High Crowd", 3.4 m from `edge:2726175794-4958781132-487772769`; `loc:9821f05090ce`, 14.3 m from the loop edge `edge:5449533723-5449533723-566001292`).
- **88 of 98 connections resolve to a real walk** (33-213 m, median 98 m), none blocked by access rules, closures or the boundary, and none an unreasonable detour (walk over 3x the straight line plus 60 m).
- **The other 10 are exactly the connections that touch the two free points.** The earlier "10 with no walking route" were an artefact of those two places having no street position, not of the network. Fixing two anchors would make all 98 resolvable.
- Only 20 of the 52 intersection places coincide with a generated playable location (the others fall inside a cluster whose representative is a different node), so matching authored nodes to the generated playable graph by position would conflate or lose most of them. Treating the authored nodes as the playable nodes avoids that.

The audit sections below were written before this clarification and assume places are separate from the nodes that a player stands on. Keep them for the findings about ids and ambiguity, but the schema proposal changes: with places as nodes, `movement_node` is unnecessary and `travel` becomes "this connection is a real walk (validated by this resolver)" versus a non-geographic transition.

## What the designer's data looks like

| | |
|---|---|
| Authored places | 60 (58 anchored to source edges, 2 free points); all inside the boundary |
| Names and notes | 57 are still "New location" and none has notes; 3 are named |
| Anchor references | all 58 edge anchors resolve (`:ok`); none moved or missing |
| `movement_location` attachments | **0 of 60** |
| Spawns | 3 (one default, at `pn:1183426912`) |
| Authored connections | 98, all `kind: "fictional"`, 98 distinct place pairs, every place has at least one (at most 8) |

The authored layer reads as a layout sketch: places and links drawn over real streets, not yet named or attached.

## Attachment audit (suggestions only; nothing implies reachability)

A suggested access point is the endpoint of a playable connection that runs along the place's own source edge, otherwise the nearest playable location within 150 m. Reachability is checked separately: a flood from the default spawn over the effective playable graph (closures and access policy applied).

- All 60 places are **unattached**; none is attached to a missing location.
- 31 have a source-edge suggestion; the rest only a proximity one.
- **46 are ambiguous** (the two best candidates are within 15 m of each other in distance). This is expected: a mid-block place sits between the two ends of its block, so proximity cannot choose, and a person must.
- **2 are disconnected**: their best candidate cannot be reached from the default spawn (`loc:1e9b8245ed76` near `pn:3269860297`, `loc:9821f05090ce` near `pn:5449533723`). Proximity there would have implied reachability that does not exist.

## Connection audit

For each connection, a shortest walk over the playable graph between the endpoints' suggested access points is compared with the straight line the editor draws (`plausible` = walk at most 3x straight plus 60 m).

- 86 look like short walkable links, 10 have no walking route between suggested access points (`conn:1c6d2ceb69d4 26044b059617 3106fb10e52e 4bc88d8c01cd 4e4b095a2c1b 768d5152c711 7d4c353afd24 81e155811ed8 9c49c05c17b0 aa83ef7080bf`), 2 resolve to the same access point (`conn:2b1b07a64c82`, `conn:2ed9762c7590`).
- Straight lengths are mostly 40-100 m, i.e. neighbouring places.
- The `kind` value is **not** evidence of intent: all 98 say "fictional", yet most look like ordinary short walks. This must be a designer decision; nothing here converts or reinterprets them.

## Recommended minimum schema changes (backward compatible, need approval)

All new fields are optional, so every existing `authored.json` stays valid and unchanged.

1. **Attachments: no change needed to attach.** `movement_location` (optional, `pn:<n>`) already separates "where the place is" (`anchor`) from "where the player stands". Add one optional companion, **`movement_node`** (the playable location's OSM `node` at attach time, e.g. `node:1183426912`). Playable ids `pn:*` come from the cluster's representative OSM node and can change on regeneration; with `movement_node` a stale attachment can be detected and a replacement *suggested* (same node, else nearest) without remapping silently. Old attachments without it are checked by existence only.
2. **Connection semantics: add an optional `travel` field**, `"walk"` or `"transition"`; absent means *unreviewed*. Keep `kind` untouched. Unreviewed connections must have no effect on movement, so gameplay does not change when this ships.
   - `walk`: a relationship between two places that must resolve to a valid walk over the pedestrian network between their attachments. It adds no movement edge (the generated graph already provides the walk); it is validated and drawn along the real route instead of a straight line.
   - `transition`: an intentional non-geographic link (hidden entrance, tunnel, wormhole). It is the only authored type that adds an edge to the effective movement graph, built beside the generated graph at load time, never written into it. Both endpoints need attachments; conditions are deferred.
3. **Effective graph** (Increment F, no change yet): `Game.World` adds approved `transition` edges to the generated connections, so one-hop adjacency, numbering and the server's validation stay on one graph.

## Decisions needed from the designer

- Are the 98 existing connections meant as walks, transitions, or neither? Suggest reviewing the 10 with no walking route first, then deciding whether the rest should default to `walk`.
- Is adding `movement_node` and `travel` acceptable? Nothing is written to `authored.json` until the explicit repair controls (Increment E) exist and the designer uses them.

## Proposed Increment E (UI, after approval)

A read-only attachment panel in the editor (the audit above, per place), then explicit controls: pick a candidate (showing distance, whether it is source-edge or proximity based, and whether the spawn can reach it), attach/detach, with the marker position untouched. Moving a marker stays a separate operation.

## Editor: Route check (2026-10-09)

The editor's "Route check" section runs the resolver on the working copy (read-only, nothing is saved) and lists every free-point or missing-street place and every connection that does not resolve, each with a button that focuses the object on the map; the result clears whenever the authored layer is edited. On the real data it reports the two free points (with their distance to the nearest street) and the 10 connections that depend on them. Browser-verified on a scratch Madison copy.
