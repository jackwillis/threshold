# Design Memo: Geographic World Importer and Viewer

**Project:** Untitled Madison AR/ARG Game  
**Date:** October 8, 2026  
**Status:** Initial implementation proposal  
**Audience:** Codex / Engineering

## 1. Background

We are developing a location-based, single-player mystery and exploration game set in Madison, Wisconsin.

The player will eventually move through a geographic network, investigate unusual events, take radio signal measurements, encounter characters, and discover anomalies. The game may later incorporate dynamic geographic changes, hidden connections, and Backrooms-inspired environments.

The game will use real geography, but its world will be partially fictionalized.

Before implementing gameplay, we want to establish a reproducible process for importing geographic information and generating an editable game world.

**The first deliverable is a geographic importer and browser-based viewer, not a playable game.**

## 2. Goals

Build a small Phoenix application that can:

1. Import real pedestrian-accessible geographic data from OpenStreetMap.
2. Generate a connected graph of streets, paths, intersections, and alleys where available.
3. Simplify that graph without discarding the underlying geographic geometry.
4. Define a geographic boundary for the imported and playable areas.
5. Display the imported geography and graph in an interactive browser map.
6. Inspect individual graph nodes and edges.
7. Regenerate geographic data through a documented, reproducible pipeline.
8. Establish a foundation for future world-editing tools.

The first geographic test area should be approximately 10–20 blocks around Madison's First Settlement neighborhood.

Use a rectangular boundary initially, but represent it as a GeoJSON polygon so that arbitrary polygon editing can be supported later.

## 3. Non-goals

Do not implement the following in this milestone:

- Player movement or game sessions.
- Radio beacons or signal simulation.
- Encounters, dialogue, quests, or inventory.
- Authentication or multiplayer.
- GPS tracking.
- WebGL interiors.
- Persistent world simulation.
- Job scheduling.
- A complete world-authoring interface.
- Procedural generation of fictional geography.

Avoid building abstractions for systems that do not yet exist.

## 4. Proposed Technology

| Component | Technology |
|---|---|
| Application | Elixir / Phoenix |
| Browser map | MapLibre GL JS |
| GIS ingestion | Python / OSMnx |
| Geographic exchange format | GeoJSON |
| Game metadata | JSON, initially |
| Editor interactions | JavaScript or TypeScript |
| Initial storage | Version-controlled files |
| Future geometry editing | Terra Draw |

Phoenix should host the application and provide endpoints for geographic data.

MapLibre should handle browser rendering and interactive selection.

JavaScript should own map interactions where client-side state is more natural than LiveView.

OSMnx should handle the initial geographic extraction and network simplification. Python is acceptable as a preprocessing dependency; the game engine itself will be implemented in Elixir.

Avoid introducing PostgreSQL/PostGIS, Oban, or an additional frontend framework unless a concrete requirement justifies them.

## 5. Geographic Data Model

We should distinguish three representations of the world.

### 5.1 Source geography

Geographic data originating from OpenStreetMap or, eventually, municipal GIS.

This contains geographic geometry and source attributes, including streets, walkways, alleys, intersections, and access restrictions.

Preserve enough provenance to reconstruct and inspect how the data was produced.

### 5.2 Simplified geographic graph

A connected network derived from the source geography.

Nodes represent meaningful intersections, endpoints, and junctions. Edges represent traversable connections.

Edges should retain their geographic polylines even when intermediate geometry vertices are removed from the graph topology.

The graph should retain:

- Node identifiers and coordinates.
- Edge identifiers and endpoint references.
- Edge geometry.
- Relevant OSM identifiers and attributes.
- Access and pathway classifications where available.
- Connectivity information.

Use OSMnx's topology simplification as a starting point.

Do not assume that all service roads or alleys are publicly accessible. Preserve relevant access metadata and document the traversal filtering rules.

Do not assume that the simplified geographic graph is already the final game movement graph.

### 5.3 Authored game world

A future layer of hand-authored locations, routes, fictional features, and narrative metadata.

This layer will reference the geographic network without modifying the source dataset.

Eventually, designers should be able to:

- Select or place playable locations.
- Attach descriptions and metadata.
- Create or override movement connections.
- Define inaccessible areas.
- Place anomalies and encounters.
- Introduce fictional connections.

**The imported geographic graph and authored game metadata must remain separate.**

This is a key architectural requirement.

## 6. Geographic Boundaries

Maintain two distinct concepts:

**Import extent:** The geographic area retrieved from the source, ideally including a small buffer around the playable area.

**Playable boundary:** The area in which the game may permit player movement.

Represent the playable boundary as a GeoJSON `Polygon`, even when its initial shape is rectangular.

For the first implementation, define the boundary in a version-controlled configuration file.

Eventually, the browser editor should support dragging vertices, drawing new boundaries, and saving changes.

The import pipeline should handle boundary intersections carefully. Avoid accidentally generating invalid connections or misleading dead ends when roads cross the edge of the selected area.

For the initial milestone, visualizing and inspecting boundary behavior is sufficient. Full polygon editing can wait.

## 7. Reproducible GIS Pipeline

Create a documented import process that can be invoked from the repository.

A possible command interface is:

```bash
mix world.import madison
mix world.validate madison
```

These commands are proposed interfaces, not existing functionality. Simpler scripts are acceptable if they make the implementation more maintainable.

The pipeline should:

1. Read the world configuration and playable boundary.
2. Determine the buffered import extent.
3. Load geographic source data.
4. Filter for relevant pedestrian-traversable features.
5. Simplify the graph topology.
6. Retain the edge geometries and relevant source metadata.
7. Export nodes and edges in a documented, interoperable format.
8. Validate topology, geometry, and references.
9. Record import provenance.

The import process must be reproducible from pinned input data. Live OpenStreetMap queries may be used to acquire a source snapshot, but a repeatable build must not silently depend on whatever OSM happens to contain on the day it runs.

Record:

- Source and retrieval date.
- Source snapshot identifier or checksum.
- Geographic boundary.
- Software and dependency versions.
- Import parameters and filters.
- Simplification settings.
- Output format version.

Ensure appropriate OpenStreetMap attribution and license compliance.

### Suggested repository structure

```text
lib/
  game/
    geography/
    worlds/

lib/game_web/
  controllers/
  live/

assets/
  js/
    world_map/

priv/
  worlds/
    madison/
      config.json
      boundary.geojson
      graph.geojson
      provenance.json

scripts/
  gis/
    import.py
    requirements.txt
```

This structure is illustrative. Adapt it to Phoenix conventions and avoid unnecessary files or directories.

The exact serialization of graph nodes and edges should be selected based on ease of validation, debugging, and MapLibre rendering. A GeoJSON representation may need additional properties or companion files for graph topology.

Do not rely on unstable automatically generated graph identifiers for future authored game content without defining a stable-reference strategy.

## 8. Browser Map Viewer

Implement a minimal geographic viewer within Phoenix.

The viewer should:

- Open centered on the imported Madison test area.
- Display a custom-styled street network.
- Distinguish ordinary streets, pedestrian paths, and alleys when that data is available.
- Display graph nodes and connections.
- Show the playable boundary.
- Allow zooming and panning.
- Support clicking nodes and edges.
- Display selected feature information in an inspector.

The inspector should show relevant properties such as:

- Feature ID.
- Coordinates or geometry.
- Connected graph nodes.
- Street or pathway classification.
- OSM provenance.
- Access restrictions, when available.

We should be able to determine visually whether the importer is producing a plausible graph.

### Rendering approach

Prefer rendering imported GeoJSON directly in MapLibre for the small initial study area.

Use a simple custom map style rather than relying on a commercial map aesthetic.

The first version does not require custom vector tile generation or a sophisticated basemap service.

The visual priority is clarity: distinguish geographic geometry, graph topology, and the playable boundary.

A later version can explore a field-investigation or radio-surveillance visual style.

## 9. Future World Editor

The geographic viewer should evolve into a world editor, but this is explicitly outside the first milestone.

We anticipate using Terra Draw or similar browser-based tools for editing points, lines, and polygons.

Future capabilities include:

- Interactive boundary editing.
- Creating playable nodes.
- Linking playable nodes to imported geographic features.
- Editing location names and descriptions.
- Marking passages inaccessible.
- Adding fictional connections.
- Defining encounter and anomaly placements.
- Saving and loading authored worlds.

These features should operate on a separate authored layer.

Avoid writing our own low-level geometry drawing tools if established libraries can provide them.

## 10. Google Street View and Photography

Google Street View is not part of the initial architecture.

We may use official mapping services as visual references where permitted, but should not assume Google imagery can be extracted, stored, modified, or incorporated into our own assets.

The eventual game may include location photographs, ideally original or appropriately licensed.

The primary geographic interface should remain a stylized 2D map.

## 11. Implementation Plan

Implement this in small, verifiable increments.

### Increment A: Phoenix and map foundation

- Initialize the Phoenix application.
- Integrate MapLibre.
- Display a simple map with a custom style.
- Load and render a small local GeoJSON fixture.
- Confirm that selection and inspection work.

**Acceptance:** A developer can start Phoenix and inspect geographic features in the browser.

### Increment B: Geographic importer

- Define the initial First Settlement boundary.
- Add the OSMnx-based import script.
- Retrieve and pin an OSM source snapshot.
- Generate the simplified pedestrian graph.
- Export geography in the selected format.
- Document and validate the output.

**Acceptance:** The same source snapshot and configuration regenerate equivalent geographic topology and output data.

### Increment C: Graph visualization

- Load the generated graph into the Phoenix application.
- Render edges and nodes separately.
- Display streets, pedestrian paths, and alleys.
- Add feature inspection.
- Display the boundary.
- Identify any disconnected components or suspicious routing artifacts.

**Acceptance:** A developer can explore the imported Madison graph and understand its topology.

### Increment D: Boundary-driven regeneration

- Change the configured rectangular boundary.
- Regenerate geographic data.
- Verify that the resulting network reflects the new boundary.
- Document how edge clipping, buffered imports, and boundary crossings are handled.

**Acceptance:** Changing the configured geographic study area does not require manually editing generated GIS outputs.

## 12. Testing and Validation

Use automated tests where practical.

Prioritize:

- Valid GeoJSON geometry.
- Valid node and edge references.
- Coordinate reference consistency.
- Correct graph connectivity.
- Correct treatment of disconnected components.
- Deterministic builds from pinned inputs.
- Correct boundary configuration handling.
- Correct edge geometry retention after simplification.

Add a small synthetic graph fixture to test topology independently of OpenStreetMap.

Include basic error reporting for malformed or missing source data.

Do not overengineer the testing infrastructure.

## 13. Definition of Done

The milestone is complete when:

1. Phoenix serves an interactive MapLibre-based viewer.
2. A real section of Madison has been imported.
3. The street and pedestrian network has been simplified.
4. Alleys and relevant paths are represented where source data supports them.
5. Nodes, edges, and boundary geometry are independently visible.
6. A user can click geographic features and inspect their metadata.
7. The boundary is defined in an editable configuration file.
8. Regeneration works from a pinned source snapshot.
9. The import and validation procedures are documented.
10. The architecture does not mix geographic source data with fictional game metadata.

No actual gameplay is required.

## 14. Guidance for Codex

Start by inspecting the repository and identifying any existing code or architectural conventions.

Before making significant implementation decisions, briefly assess:

- The simplest suitable Phoenix project structure.
- The most practical way to acquire and pin a small OSM dataset.
- The appropriate OSMnx pedestrian-network configuration.
- Whether output should use one GeoJSON graph file or separate node and edge files.
- How to preserve useful feature identifiers across re-imports.
- How to avoid losing alleys or inventing pedestrian access.
- Whether a blank MapLibre style with our own GeoJSON layers is sufficient.

Prefer the simplest reliable implementation.

Do not implement future game systems or build generic frameworks preemptively.

Keep the GIS pipeline independently executable and testable. Keep browser rendering separate from geographic preprocessing.

Document tradeoffs or unresolved questions rather than inventing requirements.

**The objective is to establish a trustworthy geographic foundation on which we can subsequently build a world editor, a turn-based movement system, and eventually the single-player anomaly-investigation game.**