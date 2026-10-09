# Threshold — Engineering and Architecture Memo

**Date:** October 8, 2026  
**Status:** Proposed architecture, pre-alpha  
**Audience:** Codex, Claude, and contributors  
**Primary stack:** Elixir, Phoenix, PostgreSQL/PostGIS, MapLibre, Python/OSMnx

## 1. Purpose

This document describes the proposed technical architecture for *Threshold*, a single-player geographic exploration and mystery game.

It is a companion to the Game Design Memo, which defines gameplay, creative direction, and the player experience.

The engineering goals are:

1. Build a reproducible geographic data pipeline.
2. Support a browser-based world editor and player interface.
3. Represent real and fictional geographic networks.
4. Implement game rules in a testable Elixir core.
5. Persist player discoveries, progress, and achievements.
6. Support gradual expansion without premature infrastructure complexity.

The current engineering priority is the geographic foundation, not the complete game.

## 2. Architectural Principles

### Separate data from behavior

Geographic data, authored world content, player state, and game rules should remain distinct.

Do not store all game behavior in arbitrary JSON expressions or mix it into UI code.

### Prefer a functional core

Game commands should produce explicit state transitions and domain events.

Pure functions should implement deterministic rules wherever practical.

Database operations, random number generation, clocks, and external services should remain at controlled boundaries.

### Keep one application initially

Use a Phoenix application with clearly separated contexts and modules.

Do not introduce microservices, a separate game server, or a distributed architecture.

The BEAM provides concurrency when we actually need it.

### Use PostgreSQL as the persistent data store

PostgreSQL will hold geographic data, authored content, and player progress.

PostGIS will support geographic geometry, indexing, and spatial queries.

This avoids introducing a file-only persistence system that will need to be replaced when player progress becomes central.

### Maintain reproducible geographic imports

PostgreSQL is not a substitute for reproducible source data.

We should retain source manifests and a repeatable import pipeline, independent of authored game content.

### Avoid speculative generalization

Design interfaces around immediate requirements.

The architecture should permit future features, but should not implement those features prematurely.

## 3. Technology Stack

| Responsibility | Technology |
|---|---|
| Web application | Phoenix |
| Application language | Elixir |
| Server-rendered UI | Phoenix LiveView, where appropriate |
| Interactive mapping | MapLibre GL JS |
| Browser tooling | JavaScript or TypeScript |
| GIS preprocessing | Python / OSMnx |
| Primary database | PostgreSQL |
| Spatial database extension | PostGIS |
| Data access | Ecto |
| Spatial Ecto integration | Geo/PostGIS-compatible library, to evaluate |
| Geographic interchange | GeoJSON |
| Flexible content fields | JSONB |
| Geometry editing | Terra Draw, when required |
| Automated testing | ExUnit |
| Source control | Git |

Use Phoenix's standard JavaScript tooling where sufficient.

Avoid adopting a separate frontend framework unless the map editor becomes complex enough to justify it.

Do not add Oban, Redis, pgRouting, or other infrastructure without a demonstrated requirement.

## 4. System Overview

The proposed system has five main areas.

### Geographic import pipeline

Acquires geographic datasets, generates pedestrian networks, performs simplification, and produces validated import artifacts.

### Geographic and world storage

Stores imported geography, authored game locations, world boundaries, and connections.

### World editor

Provides browser-based tools for viewing GIS data and authoring playable locations, routes, anomalies, and encounters.

### Game engine

Implements movement, investigation, world transitions, narrative triggers, and state changes.

### Player progress

Persists locations visited, discoveries, evidence, inventory, narrative progress, and achievements.

All five areas can exist inside one Phoenix application, with Python used for offline GIS preprocessing.

## 5. Geographic Data Pipeline

### Sources

OpenStreetMap is the initial geographic source.

Municipal GIS data may later supplement OSM, particularly for streets, pedestrian paths, alleys, and building geometry.

Start with a small section of Madison around First Settlement.

### Import stages

The pipeline should:

1. Read a geographic boundary configuration.
2. Calculate an appropriately buffered import extent.
3. Acquire or load a pinned OSM snapshot.
4. Extract relevant pedestrian routes and geographic features.
5. Normalize access and classification attributes.
6. Generate and simplify the routing graph.
7. Preserve detailed edge geometry.
8. Validate connectivity and geometry.
9. Produce import artifacts with provenance.
10. Load the results into PostgreSQL/PostGIS.

The process should be rerunnable without accidentally destroying authored game data.

### Reproducibility

Record:

- Data source and acquisition date.
- Source file or snapshot checksum.
- Import boundary and buffer.
- Tool and dependency versions.
- Network filters.
- Simplification parameters.
- Output schema version.
- Import run identifier.

Given the same pinned inputs and tool versions, the pipeline should produce equivalent geographic results.

Live OSM data should be treated as an acquisition source, not an implicit reproducible input.

### OSMnx

OSMnx is the preferred initial tool for extracting and simplifying street networks.

Preserve intermediate geometry and relevant access attributes.

Avoid assuming OSMnx's default network choices perfectly represent pedestrian accessibility.

Inspect how separately mapped sidewalks, crossings, service roads, and alleys are handled.

Some inaccessible or restricted paths may be present in source data.

### Coordinate reference systems

Use WGS84 longitude/latitude for geographic interchange and browser integration.

Store geographic features using explicitly declared spatial reference systems.

For metric measurements, use suitable projected coordinates or PostGIS geography operations as appropriate.

Do not treat degrees of longitude and latitude as meters.

## 6. Three Geographic Representations

The system should distinguish:

### Source geographic features

Detailed geographic geometry and attributes.

Examples include streets, sidewalks, crossings, building footprints, and alleys.

### Pedestrian routing graph

A directed or otherwise access-aware network containing nodes and edges representing traversable paths.

Each edge retains its geographic geometry and relevant access properties.

Directionality, turn restrictions, and crossing constraints should be represented where relevant and available.

### Playable location graph

A selective graph describing the locations and connections players interact with.

A playable connection may represent a route across several pedestrian routing edges.

A game location may be anchored to a street intersection, alley, building entrance, or manually authored point.

The playable graph is not identical to the imported routing graph.

### Node-generation strategy

Begin by generating candidates from meaningful routing intersections and endpoints.

Experiment with selective simplification, initially targeting approximately 40–100 meters between ordinary gameplay locations.

Preserve strategically important junctions, dead ends, alleys, and authored interaction points.

Do not use a fixed-distance simplification rule that accidentally removes meaningful connectivity.

Designers should eventually be able to override the generated selection.

Imported identifiers must not become fragile dependencies for authored game content.

Use stable game identifiers and explicit references or anchor metadata.

## 7. Boundaries

Represent geographic boundaries as GeoJSON polygons, including the initial rectangular boundary.

Maintain separate definitions for:

**Import extent:** The region from which geographic source data is retrieved.

**Playable boundary:** The geographic area accessible in the game.

The import extent may include a buffer to retain useful connectivity around the playable boundary.

Future tools should permit polygon editing and multiple playable regions.

For now, a configuration-defined rectangle is acceptable.

### Boundary validation

Check for:

- Valid polygon geometry.
- Incorrect coordinate order.
- Nodes outside the relevant boundary.
- Edges crossing the boundary.
- Accidental graph disconnections.
- Unexpected isolated components.

Do not automatically discard crossing edges without defining what should happen to their endpoints and routes.

## 8. PostgreSQL and PostGIS

PostgreSQL should be introduced as foundational infrastructure.

Use PostGIS for geographic columns and spatial queries.

The database should represent four broad domains.

### Geography

Potential tables:

- `worlds`
- `geographic_features`
- `routing_nodes`
- `routing_edges`
- `world_boundaries`
- `geographic_imports`

Geometry columns may include points, lines, and polygons, with spatial indexes where queries require them.

Avoid creating a generic spatial entity framework if conventional tables are sufficient.

### Authored world content

Potential tables:

- `locations`
- `connections`
- `anomalies`
- `encounters`

World locations need stable IDs independent of imported topology.

Surface locations may have geographic positions.

Backrooms locations may have local coordinates or no coordinates at all.

Connections should support links between different world regions.

Authored data should be distinguishable from regenerated geographic data.

### Player state

Potential tables:

- `players`
- `game_sessions`
- `player_discoveries`
- `player_observations`
- `player_inventory`
- `player_progress`

Player discoveries must persist independently of the world's actual hidden information.

The first implementation may use a single local player with no authentication.

Do not confuse single-player gameplay with disposable or session-only state.

### Achievements

Potential tables:

- `achievements`
- `player_achievements`

Achievement definitions may be maintained as application data or seeded records.

Awarded achievements should be persisted with uniqueness constraints so they cannot be accidentally awarded twice.

Additional progress counters can be introduced when required.

### JSONB usage

JSONB is appropriate for flexible properties such as narrative parameters, equipment metadata, and encounter configuration.

Prefer explicit relational columns and constraints for stable relationships, identifiers, and frequently queried progress.

Avoid storing the entire game state as an opaque JSON document without a clear transactional strategy.

### Spatial queries

PostGIS may be used to:

- Find geographic features near a location.
- Locate authored objects within a boundary.
- Search for nearby routing nodes.
- Test polygon intersections.
- Associate authored game locations with source geography.

PostGIS does not replace routing graph algorithms or game-state logic.

Consider pgRouting only if routing requirements justify it.

## 9. World Model

A location is an abstract game position.

It may belong to a real geographic world or a fictional region.

A connection links two locations and describes how traversal works.

Potential connection types include:

- Ordinary walking route.
- Door or corridor.
- Hidden passage.
- Null-zone transition.
- Temporarily inaccessible route.

The type may affect presentation and traversal rules.

### Geographic versus local coordinates

Surface locations may use WGS84 coordinates.

Backrooms locations may use local 2D coordinates, grid positions, or no fixed geometry.

Do not create fake geographic coordinates for fictional spaces.

Likewise, do not require connections to link geographically adjacent positions.

### World state and player knowledge

The authoritative world contains locations, connections, anomalies, and their actual conditions.

Each player has separate knowledge about that world.

The system must distinguish between:

- A location existing.
- A player knowing it exists.
- A player having visited it.
- A player having surveyed it.
- A route being currently accessible.
- A player believing a route exists.

These distinctions can initially be implemented with simple progress records.

Do not build a general epistemic reasoning engine.

## 10. Game Engine

Use Elixir for authoritative game behavior.

Prefer a functional core with explicit commands and state transitions.

For example:

```elixir
Game.step(state, {:move, location_id})
Game.step(state, {:scan, frequency})
Game.step(state, {:inspect, feature_id})
Game.step(state, {:choose, dialogue_option})
```

A transition should return updated state and a collection of relevant domain events or effects.

Illustrative events:

```elixir
{:location_visited, location_id}
{:signal_measured, beacon_id, reading}
{:encounter_triggered, encounter_id}
{:connection_discovered, connection_id}
{:artifact_collected, artifact_id}
{:achievement_unlocked, achievement_id}
```

These names are illustrative, not a prescribed public API.

### Persistence boundary

A command handler should:

1. Load the necessary game state.
2. Validate and execute the command.
3. Persist the resulting state changes transactionally.
4. Record or process relevant domain events.
5. Return a presentation-friendly result.

Protect against stale state or concurrent commands where needed.

The pure transition logic should not directly access Ecto or Phoenix.

We do not need full event sourcing.

A conventional relational state model with domain events is sufficient.

### Movement

Route planning should use the playable graph, with underlying pedestrian geometry retained for map display.

A long travel command should resolve as discrete movements so it can stop at an encounter, blocked route, or discovery.

The server must validate traversability. The browser's route preview is not authoritative.

Pathfinding can initially use a simple graph algorithm in Elixir.

### Radio measurements

Begin with a deterministic signal function that is easy to test.

The measurement model should be separate from UI rendering.

Later signal models can introduce interference, randomness, temporal variation, or cross-world behavior.

Randomized behavior should use explicit seeds or injectable sources where practical.

## 11. Browser Architecture

Phoenix hosts the game and editor.

Use MapLibre for rendering geographic layers and supporting map interaction.

Use JavaScript or TypeScript for interactions that benefit from local client state.

LiveView can handle inspector panels, forms, and other application UI where appropriate.

Avoid sending every map pointer movement through the server.

### Map rendering layers

Initially support:

- Streets and paths.
- Routing edges.
- Routing nodes.
- Candidate playable locations.
- World boundary.
- Selected features.

The developer viewer should support toggling these layers independently.

The eventual player map should hide GIS implementation details.

### Movement UX

The player selects a destination, previews a route, and confirms movement.

Movement is resolved by the authoritative game engine.

The interface should display important interruptions.

Allow panning, zooming, and recentering without changing game state.

### Styling

Use a custom MapLibre style with a dark cartographic aesthetic.

Develop the style using consistent tokens for:

- Background.
- Ordinary geography.
- Routing overlays.
- Player position.
- Measurements.
- Confirmed discoveries.
- Suspected anomalies.
- Warnings and inaccessible regions.

Avoid coupling visual styling to geographic or game rules.

## 12. World Editor

The editor should gradually grow out of the geographic viewer.

### Initial capabilities

- View imported geography.
- Toggle geographic and graph layers.
- Select and inspect nodes and edges.
- Inspect source metadata.
- Display the playable boundary.
- Review generated playable-node candidates.

### Later capabilities

- Edit boundaries.
- Add and remove playable locations.
- Merge or suppress candidate nodes.
- Create or override routes.
- Attach descriptions and features.
- Place anomalies and encounters.
- Define fictional rooms and connections.
- Preview the authored world.
- Validate and publish world changes.

Use Terra Draw or comparable tools for interactive geometry editing when required.

The editor should not modify imported source geometry when the intended operation is to author fictional content.

Consider distinguishing draft world content from published content once active player progress makes changes consequential.

Do not implement world-version migration until it is needed.

## 13. Achievements and Progress Tracking

Achievements should eventually be evaluated from game-domain events and accumulated progress.

Examples:

- First null-zone entry.
- Number of unique locations visited.
- Number of connections charted.
- Investigation completed.
- Beacon discovered without hints.
- Particular narrative encounters completed.

Keep achievement definitions separate from movement and narrative code.

Awarding an achievement must be idempotent.

Persist achievement records transactionally with the relevant progression updates where appropriate.

A basic implementation needs only a handful of achievements and a way to query unlocked results.

Do not build the entire planned achievement catalog immediately.

## 14. Testing Strategy

Testing should emphasize behavior, data integrity, and reproducibility.

### GIS tests

- Valid geometry and coordinate systems.
- Valid edge endpoints.
- Routing connectivity.
- Correct boundary behavior.
- Preservation of edge geometry.
- Access classifications.
- Deterministic imports from pinned source data.

Include small synthetic GIS fixtures so basic tests do not require live OSM access.

### Game tests

- Movement only across available connections.
- Route interruption behavior.
- State-dependent encounter triggers.
- Deterministic radio measurements.
- Discovery persistence.
- Cross-world transitions.
- Correct handling of unknown locations.

### Database tests

- Referential integrity.
- Unique discovery and achievement records.
- Valid spatial data.
- Transactional player progression.
- Isolation of player-specific knowledge.

### Browser tests

Prioritize essential interactions:

- Selecting map features.
- Displaying properties.
- Toggling graph layers.
- Previewing routes.
- Confirming movement when gameplay exists.

Use established Phoenix testing conventions.

## 15. Development Roadmap

### Milestone 0 — Geographic Foundation

**Current focus.**

Establish Phoenix, PostgreSQL/PostGIS, and MapLibre.

Import a small geographic region around First Settlement.

Generate the pedestrian routing network with a reproducible OSMnx pipeline.

Display and inspect geometry, routing edges, nodes, and the playable boundary.

Acceptance criteria:

- Phoenix runs locally against PostgreSQL/PostGIS.
- Geographic imports are repeatable from pinned inputs.
- Imported geometry is stored and queryable.
- MapLibre displays the geographic data.
- Nodes and edges can be inspected.
- Boundary changes can drive regeneration.
- Basic validation tests pass.

Do not implement actual gameplay.

### Milestone 1 — Playable World Authoring

Derive candidate gameplay locations from the routing graph.

Provide tools to retain, suppress, or add locations and define authored connections.

Store world metadata in PostgreSQL.

Acceptance: A small playable network can be authored and reopened without modifying application code.

### Milestone 2 — Movement and Player Persistence

Introduce minimal player state and the game engine.

Implement route selection, movement validation, and visited-location tracking.

Acceptance: A player can move through the authored world, close the application, and resume with their progress intact.

### Milestone 3 — Radio Investigation

Add a hidden beacon and basic measurement model.

Acceptance: A player can use signal readings to identify an anomalous location.

### Milestone 4 — Encounters

Add location-based triggers, minimal narrative state, and dialogue choices.

Acceptance: Movement and investigation can produce scripted encounters with persistent consequences.

### Milestone 5 — Null Zones

Add fictional regions, cross-world connections, and discovered-room tracking.

Acceptance: A player can enter a null zone, explore several rooms, find an artifact, and exit elsewhere.

### Milestone 6 — Cartography and Achievements

Add a basic field journal, discovery visualization, and an initial set of achievements.

Acceptance: Player exploration and completed investigations generate persistent records and rewards.

### Milestone 7 — Vertical Slice Review

Complete *The Beacon* scenario.

Evaluate movement density, radio gameplay, encounter pacing, map usability, and the player's sense of discovery.

Use the results to revise the design before expanding the world.

## 16. Explicitly Deferred

Do not implement these without a concrete need:

- Multiplayer synchronization.
- Distributed simulation.
- Oban-based background world scheduling.
- Redis or external message brokers.
- Procedural Backrooms generation.
- Dynamic world topology.
- Full narrative scripting DSL.
- GPS integration.
- 3D/WebGL environments.
- Advanced radio propagation.
- Sophisticated equipment progression.
- Full achievement catalog.
- Generalized player knowledge inference.
- Large-scale geographic streaming.
- Microservices.

These systems may eventually be useful, but their absence should not block the first vertical slice.

## 17. Open Technical Questions

The team should evaluate:

1. Which OSM network configuration best preserves pedestrian access and alleys?
2. How should separately mapped sidewalks be normalized?
3. How should stable authored locations reference regenerated routing features?
4. Should routing geometry live entirely in PostGIS or also be cached as generated artifacts?
5. What simplification strategy produces useful gameplay nodes?
6. How should playable-node density be adjusted interactively?
7. How should route execution and interruptions be represented?
8. How should persistent world edits affect existing player progress?
9. How should player hypotheses differ structurally from confirmed discoveries?
10. When does LiveView remain sufficient, and when should frontend functionality become a dedicated JavaScript module?

Avoid answering these through unnecessary infrastructure. Prefer experiments and small implementations.

## 18. Immediate Instructions for Codex and Claude

Continue work on the geographic foundation.

Use PostgreSQL/PostGIS as the primary persistent store, while preserving reproducible geographic source inputs.

Prioritize a working importer, inspectable routing network, and useful browser viewer.

Compare raw geographic geometry, pedestrian routing topology, and candidate playable-node graphs.

Preserve street and alley details while evaluating which nodes are meaningful for gameplay.

Do not implement radio systems, achievements, Backrooms, or narrative infrastructure during this milestone.

Keep future game requirements in mind, particularly:

- Fictional locations may lack real-world coordinates.
- Connections may violate ordinary geographic adjacency.
- Player knowledge differs from actual world state.
- Geographic imports must not erase authored content.
- Player progress must eventually persist across sessions.

**The immediate deliverable is a reproducible and inspectable geographic world, not a complete game engine.**

## 19. Engineering Thesis

*Threshold* should be built as a small, modular Phoenix application with a reproducible GIS pipeline, PostgreSQL/PostGIS persistence, and a functional Elixir game engine.

The geographic map is the foundation, but the actual game world is a separate authored model.

The player's experience emerges from traversing that model, gathering observations, discovering hidden connections, and accumulating persistent knowledge.

Build the minimum infrastructure needed to support those interactions, and expand it only as concrete gameplay requirements emerge.
