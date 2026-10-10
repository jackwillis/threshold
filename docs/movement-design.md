# Threshold — Movement and Exploration Design Memo

**Date:** October 8, 2026  
**Status:** Proposed design  
**Audience:** Codex and project contributors  
**Suggested file:** `docs/movement-design.md`

## 1. Overview

Threshold is a turn-based geographic exploration game built around a detailed map of Madison, Wisconsin.

The player occupies a location on a movement graph. From that location, the map highlights the immediately reachable neighboring locations with a subtle glow.

**The player moves by selecting one of these glowing locations. Each movement advances one turn.**

After moving, the camera follows the player and the next set of reachable locations becomes visible.

This creates a simple exploration loop:

**Look → Choose → Move → Discover → Repeat.**

The goal is to make ordinary navigation feel like exploring an adventure-game world, rather than operating a conventional GIS application.

## 2. Core Movement Mechanic

The player occupies exactly one movement location at a time.

The game computes the locations reachable through one connection from the current location.

These neighboring locations appear as glowing markers on the map.

The player selects one to move there.

After a valid move:

1. The player's position changes.
2. One movement turn advances.
3. The camera smoothly follows the player.
4. The previous location becomes part of the visited history.
5. The available neighboring locations are recalculated.
6. Any relevant discoveries or encounters are presented.

The initial implementation should permit only one-hop movement.

Automatic multi-hop travel and destination-based pathfinding may be introduced later, but should not complicate the first prototype.

## 3. Player-Centered Map

The player interface should initially show a closely zoomed view of the immediate surroundings.

The map uses the project's understated municipal-cartography aesthetic, potentially incorporating subtle topographic styling.

### Camera behavior

- Start centered on the player.
- Use an initial zoom around MapLibre levels 18–19, subject to playtesting.
- Smoothly follow the player after movement.
- Allow manual panning and zooming.
- Provide a button to recenter on the player.
- Avoid abruptly resetting the camera when the player is inspecting nearby geography.

The immediate movement choices should be easy to see.

If adjacent nodes fall outside the viewport, the interface may adjust the camera framing to include them, within reasonable zoom limits.

The camera is a presentation concern. Its position does not affect game state or movement eligibility.

## 4. One-Hop Visibility

The current location is visually distinct from its reachable neighbors.

### Marker states

| State | Presentation |
|---|---|
| Current location | Prominent player marker |
| Reachable neighbor | Glowing, clickable marker |
| Previously visited | Small, subdued marker |
| Known but not reachable | No movement glow |
| Undiscovered | Hidden or represented only by ordinary map geography |
| Blocked connection | Not offered as a valid move |

A location glows only when there is a currently traversable connection from the player's location to that destination.

**Visibility must be determined by graph adjacency and game state, not geographic proximity.**

A nearby location separated by a wall or inaccessible route should not become available merely because it is physically close.

A more distant location may be reachable in one hop if the graph contains a valid connection.

### Movement highlights

Glowing markers should communicate available actions clearly without overwhelming the map.

Use restrained teal or cyan illumination, a clear player marker, and optional subtle animation.

Do not render the entire navigation graph to the player.

The development editor can continue displaying all nodes and connections for debugging.

## 5. Map Discovery

The camera's field of view and the player's knowledge of the world are separate concepts.

The initial prototype may show ordinary streets and buildings within the current viewport.

However, the game should separately record visited locations and discovered content.

### Discovery states

Distinguish between:

- Ordinary geographic features visible on the base map.
- Locations the player has visited.
- Game locations the player has discovered.
- Hidden connections the player has uncovered.
- Connections that currently permit traversal.

The initial implementation needs only current position, visited locations, and immediately available movement choices.

Later, the player may progressively reveal geographic information around visited locations.

This should be a separate visual layer, not a requirement for basic navigation.

**One-hop movement visibility does not require conventional fog of war.**

## 6. Three Graph Layers

Threshold already distinguishes imported geographic data from generated playable locations and authored content.

Preserve that distinction.

### A. Geographic routing graph

Derived from OpenStreetMap and processed through the GIS pipeline.

Contains detailed sidewalks, intersections, crossings, alleys, and pedestrian connections.

Used for geographic connectivity and accurate route geometry.

This graph is not directly exposed as the player's movement interface.

### B. Playable movement graph

Derived from the geographic routing network.

Contains a smaller set of meaningful movement locations and their connections.

This is the primary graph for turn-based navigation.

A connection may summarize multiple underlying geographic edges.

Each playable connection should retain enough information to reconstruct its physical route.

### C. Authored game content

Contains designer-created places, entrances, fictional connections, and later encounters.

Authored game locations may attach to playable nodes or positions along geographic edges.

They must not require modification of imported geographic topology.

The authored layer may also introduce genuinely new movement locations and connections.

The game engine should eventually combine the playable movement graph and applicable authored transitions into a single effective movement graph.

Do not merge the three source representations into one mutable dataset.

## 7. Navigation Nodes Versus Game Locations

Not every navigation node needs narrative or interactive content.

Not every interactive object needs to become a navigation node.

Distinguish three concepts.

### Navigation location

A position where the player may stand and choose a movement connection.

Examples:

- Sidewalk junction.
- Street corner.
- Alley entrance.
- Pedestrian path endpoint.

### Interactive place

An authored object or location associated with a geographic position.

Examples:

- Radio cabinet.
- Storefront.
- Strange markings.
- Character.
- Locked door.

Interactive places may appear in a Nearby panel when the player reaches an appropriate navigation position.

They do not automatically create new movement nodes.

### Enterable location

A place that has its own spatial identity and can be entered.

Examples:

- Building interior.
- Stairwell.
- Tunnel.
- Null zone.
- Backrooms room.

Entering such a place is an explicit movement transition.

It may connect to an interior or fictional graph that has no meaningful geographic coordinates.

### Example

A player reaches an alley intersection.

The map highlights three neighboring street locations.

The Nearby panel also displays an unmarked doorway.

Inspecting the doorway is an interaction at the current location.

Entering the doorway is a movement transition into another location.

This avoids creating unnecessary graph vertices for every object that can be inspected.

## 8. Attaching Authored Places to Geography

Authored places may be anchored to:

- An imported geographic node.
- A position along an imported geographic edge.
- A free geographic point.
- An authored movement location.

The existing authored-world anchoring model should be reused where possible.

For a place along an edge, the system must determine which navigation location makes it accessible.

The first implementation may use an explicit association selected by the designer.

Do not automatically assume the nearest location is reachable.

Later, important entrances can create intermediate movement locations when needed.

Keep the geographic anchor, the movement attachment, and the visual marker conceptually separate.

## 9. Spawn Points

Worlds or scenarios should support authored spawn-point definitions.

The initial game should use one deterministic default spawn.

Additional spawn points may support alternate scenarios, testing, or future replay modes.

A spawn point should reference a valid playable or authored movement location.

### Suggested properties

- Stable identifier.
- Referenced movement location.
- Whether it is the default spawn.
- Optional initial camera zoom.
- Optional initial discovery settings.

The first implementation requires only one default spawn.

Avoid random spawning and respawn mechanics for now.

### Validation

The spawn must:

- Reference an existing movement location.
- Belong to a valid world or scenario.
- Be usable as an initial player position.
- Have at least one intended movement option, unless isolation is deliberate.

The game should not silently choose an arbitrary geographic node if the authored spawn is invalid.

## 10. Turn Resolution

A movement command should be validated by the server.

Conceptually:

```elixir
Game.available_moves(state)
Game.move(state, destination_id)
```

The exact API should follow the existing application's conventions.

A successful movement should:

- Confirm the destination is adjacent.
- Confirm the connection is currently traversable.
- Update the current location.
- Advance the movement turn.
- Record the visited location.
- Produce relevant domain events.

An invalid movement must not modify player state.

The browser should display choices supplied or validated by the game engine.

Do not trust client-submitted destinations merely because their markers appear clickable.

### Turns

Initially, only successful movement advances the movement turn.

Scanning, inspecting, dialogue, and other actions may acquire turn costs later.

Do not design a complicated action-point or time-management system before those mechanics exist.

## 11. Hidden and Conditional Connections

The effective movement graph may change based on game state.

Examples:

- A closed street cannot be traversed.
- A hidden entrance becomes available after discovery.
- A locked door requires a key.
- A null zone connects geographically distant locations.
- A passage becomes inaccessible during a narrative event.

Keep these conditions simple and explicit initially.

A hidden connection should not glow before the player has discovered it.

A visible but blocked connection may be shown as environmental information without appearing as a valid movement option.

This distinction allows the world to communicate possibilities without falsely promising traversal.

## 12. Movement UI

The recommended player interface is map-first.

The map occupies most of the screen.

A compact contextual panel presents the current location, nearby interactions, and relevant observations.

### Map

Show:

- Player marker.
- One-hop reachable destinations.
- Previously visited locations, subtly.
- Selected destination preview.
- Relevant geographic detail.

### Context panel

Show:

- Current location name or description.
- Nearby interactive places.
- Available actions.
- Encounter or discovery information.
- Optional movement history.

### Interaction

Clicking a glowing neighbor should clearly select or move to it.

For the initial prototype, a direct click-to-move interaction is acceptable.

A later confirmation step may be used for consequential transitions, unusual passages, or dangerous destinations.

Avoid requiring confirmation for every ordinary sidewalk movement if it makes exploration tedious.

### Mobile and desktop

Design the map as the primary surface on both.

On desktop, the context panel may sit beside the map.

On mobile, it may appear as a compact bottom sheet.

Do not expose technical node identifiers in the normal player interface.

## 13. Movement Animation

Movement should communicate travel without forcing the player to watch a long animation after every click.

Initially:

- Highlight the chosen connection.
- Move the player marker smoothly to its destination.
- Follow with a restrained camera transition.
- Update available neighboring markers.

Where available, the marker should follow the connection's underlying pedestrian polyline rather than moving in a straight line between geographic endpoints.

Later, movement can be interrupted by events during transit.

The authoritative movement result should not depend on whether the animation completes.

Provide a reduced-motion treatment.

## 14. How the Graph Creates Gameplay

The playable graph does more than enable routing.

Its structure determines the choices presented to the player.

A simple corridor offers forward and backward movement.

An intersection offers several routes.

A dead end suggests inspection or backtracking.

An alley entrance invites a detour.

A hidden passage changes the local network after discovery.

This suggests evaluating playable-node generation partly through the quality of movement choices.

Useful measures include:

- Number of available exits per location.
- Frequency of meaningful junctions.
- Length of ordinary movement steps.
- Preservation of interesting detours.
- Number of unnecessary intermediate stops.
- Reachability of authored places.
- Absence of invalid geographic shortcuts.

Do not optimize only for total node count or average connection length.

The existing graph-radius clustering approach is a useful starting point, not a final gameplay rule.

## 15. First Playable Prototype

Build the smallest demonstration of this movement system.

### Scope

- Existing Madison geographic map.
- Existing derived playable graph.
- One authored default spawn.
- One visible player marker.
- One-hop glowing neighboring locations.
- Click-to-move.
- Smooth camera following.
- Visited-location tracking.
- One authored interactive place attached to the movement network.
- A compact current-location/Nearby panel.

No radio simulator, narrative engine, achievements, Backrooms, or advanced discovery system is required.

### Acceptance criteria

A player can:

1. Start at the authored spawn.
2. See the immediately reachable neighboring locations.
3. Click a glowing neighbor.
4. Move exactly one graph connection.
5. See the map recenter and the available neighbors update.
6. Backtrack through previously visited locations.
7. Encounter a nearby authored place.
8. Inspect that place without necessarily changing movement position.
9. Reload the game and restore current position and visited history once persistence is integrated.

The server rejects movement to nonadjacent, hidden, or blocked destinations.

The normal player interface does not display the entire navigation graph.

## 16. Implementation Guidance for Codex

Preserve the existing imported geographic graph, derived playable graph, and authored-world separation.

Implement a small Elixir movement model and a separate player-oriented LiveView.

Do not turn the development editor into the player interface.

Reuse geographic rendering utilities where practical, but separate editor overlays and gameplay overlays.

Use the generated playable graph for adjacency.

Do not introduce multi-hop pathfinding as a prerequisite.

Represent authored interactive places separately from traversal nodes.

Keep spawn definitions in authored world content.

Use PostgreSQL/PostGIS for persistent player progress when introducing durable game sessions, while retaining the Git-versioned world artifacts.

Protect existing uncommitted designer data and follow the repository handoff instructions.

Make the implementation small, testable, and reviewable.

## 17. Open Design Questions

The following require playtesting:

- What zoom level feels best for walking?
- Should all immediate neighbors always fit in the viewport?
- Should movement occur on click or require confirmation?
- How much previously visited geography remains emphasized?
- Should long, uninteresting corridors advance automatically?
- When does an interactive place deserve its own movement node?
- How should entrances halfway along geographic edges work?
- Should scanning and inspecting consume turns?
- How should hidden connections first become perceptible?
- Should the player eventually have an optional wider atlas view?

These are not blockers for the first prototype.

## 18. Design Thesis

Threshold's movement interface should emerge directly from the structure of its world.

The player stands at a location, sees the available paths glowing around them, and chooses where to go next.

The full geographic network remains underneath, providing realistic structure and route geometry.

Authored places give those locations meaning.

Hidden connections gradually change the player's understanding of the world.

**The graph determines where the player can go. The map shows what the world looks like. Exploration reveals what the world contains.**
## Implemented persistence setup

Player progress uses PostgreSQL via `Threshold.Repo`; geography and authored world data stay in files. The editor runs without a database. To enable gameplay, create a dedicated local database, set `THRESHOLD_DATABASE_URL=postgres://USER:PASSWORD@localhost/threshold_game`, and run `mix ecto.migrate` before starting Phoenix. One local player save is stored per world. Moves lock the save row, check the expected turn and world revision, and update location, turn and visited locations atomically. Changing the authored world requires an explicit new walk.

Database tests require a separate database whose name ends in `_test`: run `THRESHOLD_TEST_DATABASE_URL=postgres://USER:PASSWORD@localhost/threshold_test make check`. Without this variable, database tests are explicitly excluded; the development database URL is never used by tests.

## First playable verification (2026-10-09)

The `/play` LiveView shows only immediate legal destinations, animates along the validated route geometry, frames the player and adjacent destinations, offers recentering, and respects the browser's reduced-motion preference. Directions also have accessible buttons. Nearby authored places use an explicit `movement_location` attachment; inspecting one does not spend a turn. In the editor, select a fresh playable location and choose **Use as default spawn**, attach a place with **Nearby at playable location**, then save.

The full gate passed with PostgreSQL enabled: 131 Elixir tests and 32 Python tests, TypeScript checks, world validation, and byte-identical rebuild. Coverage includes closures on interior route edges, invalid/replayed moves, world revisions, save restoration, free nearby inspection, and editor spawn/attachment controls. Browser verification on a scratch Madison world confirmed a glowing marker click, updated adjacent destinations, backtracking, visited counts, inspection without a turn, and turn/location restoration after restarting Phoenix in production mode. The designer's real authored file was not edited. Reduced-motion handling is implemented but was not separately exercised in the browser; concurrent-tab locking is covered by stale-turn tests, not a browser race test.

### Two-stop visibility

The player map now shows immediate destinations as bright clickable markers and locations exactly two legal stops away as faint rings. Two-stop previews exclude the current location and immediate neighbors, deduplicate locations reached through multiple paths, and use only the already validated movement graph. Previewing a location does not permit a multi-hop move or spend a turn. Camera framing includes both distances. The full gate passed with 133 Elixir tests and 32 Python tests; browser verification showed distinct near/far markers with no overlapping destination IDs.

### Two-stop walking, third-stop preview

The clickable range is now one or two stops, with faint rings exactly three stops away. A two-stop click follows a server-chosen path through validated connections, spends two turns, and adds the intermediate location to visited progress. Route selection prefers fewer stops, then lower total distance, with stable ID ordering for ties. Both steps save atomically under the existing revision/turn checks; third-stop destinations remain unavailable. Browser verification in a separate scratch walk confirmed turn 0 to turn 2, three visited locations and restoration after reload. The full gate passed with 134 Elixir tests and 32 Python tests.

### Spawn marking UI

The editor's Spawn points section reveals playable points and lists marked starts. The inspector can mark a point, choose it as default, or remove its mark. The first mark becomes default; switching the default preserves every spawn identity. Removing the default does not silently select another point. Missing playable references remain visible for deliberate removal or repair. Gold rings identify marked points while the playable layer is visible. Browser verification used a scratch tiny world: marked two points, switched the default, saved and reloaded. The full gate passed with 136 Elixir tests and 32 Python tests.

### Strict one-hop movement (2026-10-09, supersedes the two-stop sections above)

At the designer's request, movement is again strictly one hop. `Game.walk_options` and the breadth-first search are gone: `Game.available_moves/2` lists the immediately adjacent, traversable destinations, and `Game.move/3` accepts only one of those, spends exactly one turn and records only the destination as visited. The player map has no second- or third-stop preview markers, and camera framing includes only the player and adjacent destinations. The ordinary street map is still fully visible. Tests cover non-adjacent destinations being refused at the game, session and LiveView levels, and the absence of previews from the map state. Browser verification (headless Firefox driven over Marionette, scratch copy of the Madison world, disposable test database, port 4011): the initial view showed the player and the seven adjacent glowing markers with no faint rings, no `preview` map source or layer, and no `preview` key in the map state; a real mouse click on a marker moved one connection and one turn (turn 1, 2 places visited, new destinations shown), and a panel button backtracked (turn 2). Not exercised in a browser: reduced motion, touch input, and a stale-turn race between two tabs (covered by server tests).

### Radial keyboard shortcuts (2026-10-09; design memo: `keyboard-navigation.md`)

`Game.numbered_moves/2` gives each one-hop move a `bearing` (degrees clockwise from north, from the player's location to the destination, longitude scaled by cos latitude) and a shortcut `key`: moves are sorted clockwise from north with ties broken by destination id, and the first ten get `1`-`9` then `0`. Further moves have no key and stay available by click or panel button. Numbering depends only on geography, so camera rotation, zoom and layout cannot change it. The server computes it once and the same `key` is rendered in the movement panel, on the map (DOM labels over the glowing markers) and in the keyboard handler, so the three cannot disagree; this deliberately puts the ordering in Elixir rather than TypeScript. Keys are presentation only and are never stored.

Keyboard handling lives in `assets/src/map/shortcuts.ts` (pure, tested with `bun test`, run by `make check`) and `hooks/player_map.ts`. A digit requests a move by destination id and turn through the same `move` event as a click, so the server validates it identically. Ignored: held-key repeats, Ctrl/Alt/Meta/Shift combinations, already-handled events, IME composition, text fields, selects and contenteditable, open dialogs, and any time a walk animation or an earlier request is in flight (so two presses in one tick request one move). Top-row digits are read by key code so non-QWERTY layouts work; numpad digits count only with Num Lock on. The listener is removed when the hook is destroyed.

Destination versus route-departure bearing: the first implementation orders by the bearing to the destination, which matches where each label sits on the map. On the Madison playable graph, 510 locations have two or more exits and ordering by the first segment of the walking route would order 207 of them differently (mostly those with five or more exits). The map memo asked for this to be a deliberate choice; destination bearing is kept because the player reads direction from where the labelled marker is drawn. Worth revisiting after playtesting complex intersections. The largest location has 14 exits, so unnumbered moves do occur in the real data.

Browser verification (headless Firefox over Marionette, scratch Madison copy, disposable test database): labels 1-7 on the map and in the panel matched and ran clockwise from north; a held-key repeat, Ctrl/Alt/Shift+1, a focused text input and an open dialog each left the turn unchanged; Digit2 moved to the destination labelled 2 (one turn) and renumbered the new choices; Numpad1 moved; two presses in one tick advanced one turn; an unused digit did nothing; a mouse click on a numbered marker still worked; the keydown listener was removed on LiveView teardown. Not verified: other keyboard layouts, touch devices, Num Lock off, and the visual treatment at more than ten exits.

### Authored graph (opt-in: `/play?graph=authored`, 2026-10-09)

The designer's authored places are traversable nodes (street intersections, or halfway down a block), so `Threshold.EffectiveGraph` builds the movement graph from them: each place stands on its intersection or at its offset on its street (`Threshold.Polyline`), and each authored connection that `Threshold.RouteResolver` resolves to a walk over the pedestrian network (access policy, vehicle-service ways, authored closures, playable boundary) is a one-hop move along that walk's real street geometry. The result is an ordinary `Game.World`, so movement, numbering, the server's turn and adjacency checks, and the keyboard shortcuts are unchanged. Nothing is written to the generated graph or `authored.json`.

Rules chosen and where they can be revisited: every authored connection is treated as a walk whatever its `kind` (the designer has not given `kind` a movement meaning; it is never rewritten); free points, places on streets missing from the geography, and links whose walk does not exist are left out and listed as unavailable; authored spawns point at generated playable locations, so each maps to the nearest authored place within 25 m and an unmappable default spawn is an error (a schema change allowing spawns on authored places would be cleaner); places with a name or notes appear under "Nearby" for inspection; player progress is stored separately under `<world>:authored`. The generated playable graph remains the default.

On the committed Madison data (checked on a scratch copy): 58 places stand on the network, 88 of 98 connections are walks (33-213 m), the other 10 touch the two free-point places, the default spawn maps to an authored place 13.8 m away and starts with five numbered choices, all 58 places are reachable from it, and two places share one intersection. Browser verification (headless Firefox, scratch Madison, test database): the authored map loaded with its notes, numbered choices rendered on the map and panel, six consecutive keypresses each advanced exactly one turn and ended on the previous choice's route endpoint, the generated map kept an independent save at turn 0, and the authored walk resumed at turn 6 after reload. Not exercised: stale-turn races between tabs, touch input, the editor round trip after changing authored places.
