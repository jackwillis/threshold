# Project decisions

Date: October 8, 2026 (America/Chicago)
Status: Agreed direction; editor implementation in progress (see implementation-plan.md for operational decisions)
Project directory and application name: `threshold`
Game title: Not yet chosen

## Game direction

A location-based, single-player mystery and exploration game inspired by Madison, Wisconsin. Investigation, radio measurements, characters, anomalies, hidden connections, and Backrooms-inspired spaces are possible later systems.

The first game experience will involve navigating a fictionalized Madison remotely. Physical exploration of real Madison is a possible later direction, not a requirement for the first milestone. Preserve real geographic evidence so that future work can assess actual access independently of fictional routes.

The first milestone is now a **geographic editor**, expanding the original memo's importer-and-viewer milestone. Gameplay remains outside this milestone. The exact minimum editing actions still need to be agreed.

## Initial study area

The user supplied these corners as latitude, longitude:

- Northwest: `43.080139, -89.391777`
- Southeast: `43.069930, -89.369448`

The rectangle is the initial playable boundary. GeoJSON stores coordinates in **longitude, latitude** order:

```json
{
  "type": "Polygon",
  "coordinates": [[
    [-89.391777, 43.069930],
    [-89.369448, 43.069930],
    [-89.369448, 43.080139],
    [-89.391777, 43.080139],
    [-89.391777, 43.069930]
  ]]
}
```

Import a buffer around the playable area. Keep the buffered geographic network intact and overlay the playable boundary, rather than clipping routes at the playable boundary and manufacturing apparent dead ends. The amount of buffer is an implementation default to review; the draft configuration uses 250 meters.

The supplied rectangle supersedes the original approximate “10–20 blocks” description. Its exact neighborhood coverage has not yet been visually reviewed against imported geography.

## Technology and responsibilities

Agreed direction from the discussion:

| Part | Responsibility |
|---|---|
| Phoenix / Elixir | Serve the editor, load/save versioned world files, validate requests, later support the game |
| Browser / JavaScript | MapLibre map, selection, inspector, layer controls, future editing interactions |
| Python / OSMnx | Acquire geographic snapshots, filter and simplify networks, validate and export geography |
| JSON / GeoJSON | Interoperable version-controlled world and geography files |

Start as a local browser application on `localhost`. Public hosting is not required. Keep the GIS pipeline independently executable. Python need not run a separate web service; an eventual regeneration action can invoke the command-line importer.

A native Python GUI was considered. A browser GUI was recommended because the editor centers on interactive maps and will grow alongside the Elixir game. A Python web backend remains technically possible but is not the chosen direction.

Avoid background job infrastructure and an additional frontend framework (React or a separate SPA) without a concrete need. PostgreSQL/PostGIS is the revised long-term persistent store (see Files, Git, and CI/CD), but is not needed for the editor milestone. Terra Draw or a comparable established tool is a candidate for geometry editing, not yet integrated or selected definitively.

## Source geography

OpenStreetMap is the initial source. OSMnx is the processing tool; Overpass is a means of acquiring an OSM extract. Municipal GIS may supplement it later. Google Street View imagery is not an input asset source.

Acquire source data explicitly and save a snapshot with a checksum. Regeneration must use that pinned input, not silently query live OSM. Record retrieval details, source bounds, dependency versions, filters, simplification settings, and output format version. Include OpenStreetMap attribution and applicable license information.

The initial display should include lightweight context such as building footprints, parks, and water where available, alongside the street/path network. Iterate on context after seeing the first import.

## Geographic inspection and traversal

Preserve disconnected components and make them inspectable. A disconnected path can represent real isolation, incomplete source mapping, or a filtering artifact. Do not silently discard all but the largest component by default.

Preserve access classifications and relevant source tags. A service road or alley does not automatically imply public pedestrian access. Distinguish public, restricted, unknown, and conditional or mixed access where appropriate. Presence in the geographic editor does not imply permission for real-world walking.

Simplify topology while retaining edge polylines. Geographic vertices, graph junctions, and authored playable locations are different concepts. The imported graph is not automatically the game's final movement graph.

## Editor options

The questions discussed should be represented as inspectable settings or controls, rather than permanent hidden choices. Keep their responsibilities distinct:

| Area | Options or behavior |
|---|---|
| Viewer | Visibility of disconnected components, access classifications, nodes, edges, context, and buffered geography |
| Import configuration | Buffer size, access filtering, retained components; changes require regeneration |
| Authored world | Playable routes, geographic references, inaccessible routes, and fictional connections |
| Source management | Pinned source selection and explicit snapshot updates |
| Reference review | Missing or changed geographic references after regeneration or updates |

The earlier suggestion to leave all import settings in files was made while discussing a viewer-only milestone. The later decision to build an editor expands that scope; exactly which settings get browser controls is still open.

## Source updates and stable references

Builds from the same snapshot and settings should yield equivalent geography and deterministic feature identifiers. Avoid graph enumeration order as the reference strategy.

When explicitly updating source geography:

- Preserve authored locations and metadata.
- Retain references that still resolve.
- Flag references that disappear or need review.
- Let the designer reconnect a location, retain it as fictional, or remove it.
- Do not silently move or delete authored content.

For example, an encounter attached to an intersection must survive an OSM update even if that intersection is reorganized. Its geographic link may become unresolved, but its authored content remains.

Sophisticated automatic matching is unnecessary for the first milestone. Reliable references within a snapshot and detection of unresolved references are the starting point. IDs that remain present do not by themselves prove that geometry or meaning remained unchanged; a future update workflow needs an explicit definition of material changes.

## Files, Git, and CI/CD

Start with three separate file layers:

1. **Source snapshot:** In the repository if small enough, otherwise a versioned artifact identified by a checksum recorded in Git.
2. **Generated geography:** Versioned node/edge/context data for the initial small area.
3. **Authored world:** Separate readable JSON/GeoJSON describing locations, metadata, closures, and fictional connections.

The local editor loads and saves files through Phoenix. Saving creates working-tree changes; it must not automatically commit or deploy them.

Intended workflow: edit → save files → review diff → commit → CI validation → deploy approved world files with the application.

CI should check geometry, topology, references, and world structure. When relevant pipeline inputs change, it can regenerate from the pinned snapshot and check equivalent outputs. Do not make CI depend on live OSM queries.

**Revised:** PostgreSQL with PostGIS is the planned long-term platform for player progress, discovered connections, inventory, narrative flags, achievements and spatial queries, and possibly persistent editing state. It is introduced incrementally with the first database-backed gameplay requirement (persistent player movement), not as a migration of the world files. The version-controlled source snapshot, generated geography and authored world files remain reproducible source artifacts. The Python pipeline stays independent of Phoenix and the database. Previously: deferred until shared hosted editing or runtime writes justify it. A future database could hold drafts and export reviewed world releases. Player progress, sessions, and inventory are separate from world definitions and may eventually use database storage.

## Non-goals retained from the original memo

No player movement, game sessions, radio simulation, dialogue, encounters, quests, inventory, authentication, multiplayer, GPS tracking, WebGL interiors, persistent simulation, scheduling, or procedural fictional geography in this milestone.

The geographic editor does not imply implementing a complete narrative or gameplay authoring suite.

## Resolved since this memo was written

The editor milestone decisions (editor actions, anchoring, closure semantics, edge IDs, LiveView with one JS hook, Bun/TypeScript tooling, Terra Draw, no basemap, committing data files, keeping the sidewalk-level graph) are recorded in [implementation-plan.md](implementation-plan.md). The list below is the original open list; items it covers are marked there.

## Remaining decisions

- Agree the minimum editor actions and acceptance criteria. Boundary editing, placing/naming locations, marking routes inaccessible, and creating fictional connections have been proposed, not individually confirmed.
- Select the geometry editing library and define save/discard behavior.
- Finalize access filters and whether conservative filtering is optional alongside inspection of all candidate features.
- Finalize the buffer size and behavior when an edited boundary exceeds pinned snapshot coverage.
- Finalize graph serialization and reference semantics. Separate node and edge GeoJSON files are the current draft choice.
- Define source-update comparisons and how unresolved references are shown.
- Decide whether source data is small enough to commit once acquired.
- Establish CI provider and deployment target when needed; neither has been chosen.
