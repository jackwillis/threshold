# Threshold — Frontend V2 Architecture and Redesign Memo

**To:** Claude Code  
**From:** ChatGPT (GPT-6), Design and Architecture Review  
**Date:** October 9, 2026  
**Project:** Threshold  
**Status:** New design initiative — evaluate before implementing

## 1. Context

Threshold's first frontend has been successful as a development prototype.

It demonstrated that we can:

- Import and render actual Madison geography.
- Edit locations, connections, boundaries, and restrictions.
- Generate a playable navigation graph.
- Attach authored places to gameplay.
- Support server-authoritative movement.
- Persist player progress.
- Explore the city through an interactive map.

However, the frontend was developed incrementally as the backend and geographic systems evolved. The editor began as a GIS inspection tool and acquired editing capabilities over time. The player interface was subsequently added as a separate vertical slice.

Neither interface was designed from the beginning as a cohesive product.

**We now want to reconsider the entire frontend, including the map editor.**

This is not a rejection of V1. V1 established the functional requirements and validated the technology.

The goal of V2 is to build a coherent, maintainable, visually distinctive experience based on what we have learned.

## 2. Relationship to Existing Work

Claude is already working from two steering documents:

1. The reliability review and hardening plan.
2. The gameplay steering memo covering authored-map integration and strict one-hop movement.

**Continue those efforts. Do not abandon or restart them because of this memo.**

The V2 initiative should initially proceed as architecture and interaction design.

Do not begin a wholesale frontend rewrite until the current work is sufficiently stable and a V2 direction has been reviewed.

The reliability work is especially important because V2 should consume dependable world and gameplay APIs rather than reproduce backend validation rules.

Likewise, authored-map integration should inform the new editor's interaction design.

We want to avoid implementing the same feature twice without learning from the first implementation.

## 3. Product Vision

Threshold will have two primary interfaces.

### Threshold Studio

The geographic world-authoring environment.

Studio should feel like a specialized cartographic design application, not an administrative dashboard.

Its responsibilities include:

- Inspecting imported geographic data.
- Reviewing the generated playable navigation graph.
- Creating and editing authored places.
- Editing authored connections.
- Managing street restrictions.
- Defining and editing playable boundaries.
- Attaching authored locations to navigation locations.
- Reviewing stale and broken references.
- Managing spawn points.
- Previewing how the player will experience the world.
- Saving changes safely and explicitly.

### Threshold Field Atlas

The player-facing exploration interface.

Field Atlas should feel like an interactive geographic investigation instrument.

Its responsibilities include:

- Closely zoomed, player-centered geographic exploration.
- Strict one-hop movement choices.
- Glowing reachable nodes.
- Smooth movement along real walking routes.
- Geographic discovery.
- Nearby authored places.
- Investigation actions.
- Eventual radio instruments.
- Eventual null zones and impossible geography.

**The two applications should share cartography and visual language without sharing the same interaction model.**

The editor is a tool for constructing the world.

The player interface is a tool for discovering it.

## 4. Scope of the Redesign

This is a complete frontend redesign, not merely a CSS refresh.

Reconsider:

- Application layout.
- Navigation and information architecture.
- Interaction patterns.
- Editor tool organization.
- Layer controls.
- Map rendering.
- Visual hierarchy.
- Typography.
- Color palette.
- Responsive behavior.
- Component architecture.
- Client-side state management.
- API boundaries.
- Error presentation.
- Editing and saving workflows.

The new interface should feel intentionally designed.

However, the redesign should not automatically trigger changes to the Elixir domain model, PostgreSQL persistence, GIS importer, or authored-world format.

Preserve working backend components unless there is a demonstrated need to change them.

## 5. Frontend Architecture Evaluation

Evaluate three options.

### Option A — Phoenix LiveView with redesigned TypeScript hooks

Retain the current general architecture.

Redesign both interfaces, refactor the JavaScript hooks, and improve the separation of responsibilities.

Advantages:

- Minimal architectural disruption.
- Existing Phoenix integration remains useful.
- Server-managed forms, validation, and state.
- Reuse of established workflows.

Disadvantages:

- Rich map-editing operations require coordination across LiveView and TypeScript.
- Temporary interaction state can become awkward.
- Tool modes, dragging, snapping, and visual previews are naturally client-side concerns.
- Server/client synchronization may become increasingly complex.

### Option B — Preact + TypeScript + MapLibre

Use Preact for interactive application interfaces while retaining Phoenix as the backend.

Keep TypeScript, Bun, MapLibre, and the existing geographic tooling.

Advantages:

- Lightweight component model.
- Familiar React-like programming model.
- Efficient management of interactive UI state.
- Shared components across Studio and Field Atlas.
- Clear division between browser interaction and server-authoritative domain operations.
- Small dependency footprint.

Disadvantages:

- Requires a new client/backend API boundary.
- Some existing LiveView functionality must be replaced.
- Client state synchronization must be designed carefully.
- Additional frontend tests will be needed.

**This is currently the preferred candidate.**

### Option C — SolidJS + TypeScript + MapLibre

Use SolidJS for the application UI.

Advantages:

- Fine-grained reactivity.
- Strong performance for interactive applications.
- Convenient reactive state composition.
- Good fit for complex UI interactions.

Disadvantages:

- Another framework-specific programming model.
- Potentially more architectural novelty.
- Less direct continuity with familiar React-like tooling.

### Evaluation criteria

Prioritize:

1. Simplicity and maintainability.
2. Quality of interactive map editing.
3. Clear server/client responsibilities.
4. Minimal unnecessary dependencies.
5. TypeScript developer experience.
6. Ease of testing.
7. Reuse between Studio and Field Atlas.
8. Compatibility with the existing Phoenix deployment.

Do not choose a framework based primarily on benchmarks or popularity.

Also consider whether a small amount of framework-free TypeScript remains preferable for the MapLibre renderer itself, even if Preact manages the surrounding interface.

## 6. Recommended Architecture

My initial preference is:

- Phoenix/Elixir backend.
- PostgreSQL for persistent player state.
- Existing Python geographic pipeline.
- Preact for application UI.
- TypeScript for frontend implementation.
- Bun for dependency management and builds.
- MapLibre GL JS for cartography.
- Terra Draw where appropriate for geometry editing.
- Explicit HTTP APIs for world authoring and gameplay actions.

Do not introduce a separate backend application.

Do not introduce a heavyweight frontend build system without need.

Do not split Studio and Field Atlas into separately deployed frontend projects unless there is a concrete advantage.

A single frontend codebase can expose two application entry points or routes.

### Responsibilities

**Phoenix owns:**

- Domain validation.
- Canonical authored-world state.
- Revision and conflict checking.
- Player movement validation.
- Player persistence.
- World loading and publication.
- Geographic APIs.

**Frontend owns:**

- Tool selection.
- Dragging.
- Snapping previews.
- Hover state.
- Temporary selections.
- Map camera state.
- Visual transitions.
- Panel layout.
- Local unsaved editing state.
- Presentation and interaction feedback.

The frontend may maintain a local working draft of authored content, but the backend remains authoritative for validation and saving.

Do not duplicate complex business rules in TypeScript.

## 7. Suggested Frontend Organization

A possible structure:

```text
assets/
  src/
    app/
      studio/
      atlas/
    components/
      panels/
      controls/
      dialogs/
    map/
      renderer/
      layers/
      styles/
      interactions/
      geometry/
    domain/
      editor/
      gameplay/
    api/
    theme/
```

This is illustrative, not mandatory.

Avoid creating elaborate abstractions before multiple features require them.

The shared map code should handle rendering and camera operations.

Studio-specific editing tools should remain separate from Field Atlas movement interactions.

Shared components should represent genuinely shared behavior rather than forcing the applications into identical layouts.

## 8. Threshold Studio — Interaction Redesign

The world editor deserves a complete UX review.

### Recommended layout

Use the map as the dominant workspace.

Provide a compact layer and object panel on the left.

Use a contextual inspector on the right.

Editing tools should be easy to discover without permanently occupying excessive space.

A possible arrangement:

- Top: World name, save status, undo/redo, preview controls.
- Left: Layers, authored locations, playable graph, search.
- Center: Interactive geographic map.
- Right: Contextual inspector.
- Bottom or floating area: Diagnostics and validation messages.

Do not assume every panel must be visible at once.

### Layer organization

Clearly distinguish:

- Imported geography.
- Generated playable network.
- Authored places.
- Authored connections.
- Closures and restrictions.
- Spawn points.
- World boundary.
- Diagnostic overlays.

Users should understand which data is editable and which data is generated.

Generated geographic data should not appear directly editable unless an explicit override workflow exists.

### Authored-location workflow

The user should be able to:

1. Choose an appropriate creation tool.
2. Click a geographic location.
3. See where the marker was placed.
4. Inspect nearby navigation attachment candidates.
5. Choose or reject an attachment.
6. Configure the location's behavior.
7. Save the authored change.

Do not automatically move authored markers merely to satisfy network snapping.

Keep geographic display position separate from movement attachment.

### Snapping

Treat snapping as an explicit, understandable operation.

Distinguish:

- Snap marker to geographic node.
- Snap marker to source edge.
- Attach location to playable navigation node.
- Keep marker as a free point.

The UI should preview these relationships visually.

Avoid treating visual proximity as proof of walking connectivity.

### Authored connections

Make ordinary geographic routes and fictional connections visually distinguishable.

Straight-line editor links may be appropriate as design diagrams, but should not be mistaken for physical walking routes.

Where a geographic route is available, render its actual path.

### Preview mode

An important eventual feature is **Play from here**.

The designer selects a playable location and enters a temporary player preview using the current authored world.

The preview should not modify canonical player progress.

This could make Studio dramatically more useful for game design.

It is not a first-increment requirement, but the architecture should leave room for it.

## 9. Threshold Field Atlas — Interaction Redesign

The player interface should be designed independently of Studio.

### Core movement

Restore strict one-hop movement.

Only immediately reachable navigation locations glow.

No second-hop or third-hop preview markers.

One valid movement advances one connection and one turn.

The server remains authoritative.

### Camera

The map is closely centered on the player.

The camera follows movement but does not prevent manual map exploration.

Provide a recenter button.

Keep movement animations short and legible.

### Visual hierarchy

The most visually prominent map elements should be:

1. The player.
2. Immediate reachable locations.
3. Important nearby authored places.
4. The current geographic surroundings.
5. Previously visited information.

The complete navigation graph should not dominate the screen.

### Contextual interface

Use a compact contextual panel for:

- Current location.
- Nearby places.
- Inspection results.
- Available actions.
- Relevant discoveries.

The interface should avoid looking like an administrative tool.

Consider a side panel on desktop and a bottom sheet on mobile.

## 10. Shared Visual Identity

We want Threshold to have a distinctive cartographic aesthetic.

The design should combine:

- Municipal mapping.
- Topographic survey maps.
- Field investigation.
- Subtle analog instrumentation.
- Digital cartography.
- Architectural documentation.

Avoid generic commercial map styling.

### Primary palette

Explore:

- Warm ivory or cream map backgrounds.
- Muted sage-green parks.
- Slate or blue-gray pedestrian paths.
- Restrained building footprints.
- Teal movement indicators.
- Warm amber for discoveries, anomalies, or authored points.

Favor precision and legibility over decorative texture.

### Typography

Explore a combination of:

- Clean, functional sans-serif interface text.
- Technical or survey-inspired annotations.
- Small geographic labels.
- Carefully restrained monospaced metadata.

Do not make the entire interface resemble a terminal.

### Topography

Investigate subtle topographic contours, gentle hillshading, and survey-map details as part of the visual identity.

Treat topography as a visual research track initially.

Do not introduce a new elevation data pipeline without a separate decision.

### Dark field-survey mode

A future dark visual mode may emphasize radio measurements, technical overlays, and anomalies.

It should be a meaningful alternative presentation, not merely inverted colors.

Do not let development of this mode delay the primary atlas interface.

## 11. Map Rendering Architecture

MapLibre should remain the geographic rendering engine unless a concrete limitation is discovered.

Design a shared map-rendering layer with well-defined inputs.

Possible responsibilities:

- Geographic source loading.
- Style selection.
- Cartographic layer configuration.
- Marker and overlay rendering.
- Camera operations.
- Geographic hit testing.
- Coordinate transformations.

Keep MapLibre instances outside ordinary component rerender cycles.

For example, a Preact component may own the map container and lifecycle, while a dedicated TypeScript controller manages MapLibre sources, layers, and interactions.

Avoid rebuilding map state whenever a panel field changes.

Do not copy the full geographic dataset into reactive application state unnecessarily.

## 12. Migration Strategy

**Keep V1 functional throughout development.**

Do not remove the existing editor or player interface at the beginning of V2.

Develop V2 alongside it.

Possible temporary routes:

- `/studio-v2`
- `/atlas-v2`

The exact routes are implementation details.

### Migration milestones

**Milestone 1 — Architecture and visual specification**

Evaluate architecture choices, produce component boundaries, and define the visual system.

No wholesale code changes.

**Milestone 2 — Shared cartographic renderer**

Render actual Madison geography using the new visual system.

Demonstrate map initialization, layer control, and camera behavior.

**Milestone 3 — Studio vertical slice**

Implement one complete editing workflow:

- Select an authored location.
- Inspect its properties.
- Edit its movement attachment.
- Save safely.
- Reload and verify persistence.

This should use the canonical backend validation and conflict-checking mechanisms.

**Milestone 4 — Field Atlas vertical slice**

Implement:

- Spawn loading.
- Player-centered map.
- Strict one-hop movement.
- Glowing neighboring nodes.
- Movement animation.
- Persistent player progress.

Reuse the existing game engine.

**Milestone 5 — Remaining Studio tools**

Migrate creation, deletion, connection editing, closures, boundary editing, regeneration, and reference review.

**Milestone 6 — Replace V1**

Only after equivalent workflows have been demonstrated and tested should V1 be retired.

Do not remove V1 merely because V2 looks better.

## 13. Reliability and Data Integrity

The V2 frontend must preserve the guarantees being established in Reliability Pass 1.

Specifically:

- Canonical saves remain conflict-safe.
- Generated geography remains revision-consistent.
- Movement remains transactional.
- Browser-provided coordinates are validated.
- The client cannot bypass server traversal rules.
- Unsaved edits are clearly indicated.
- Failed saves preserve local draft state.
- Browser refresh and reconnect behavior are considered.
- Player progress is never silently replaced.

A frontend rewrite must not weaken these properties.

If new APIs are required, reuse existing domain functions and validation paths.

Do not create alternative save mechanisms that bypass the reliability work.

## 14. Frontend Testing

Introduce focused browser-level tests as V2 is developed.

Test workflows rather than implementation details.

Important cases:

- Map initializes correctly.
- Layers load and render.
- Selecting an authored location updates the inspector.
- Snapping previews are accurate.
- Unsaved changes are visible.
- Save conflicts are reported.
- Failed saves preserve local edits.
- Movement markers reflect server-approved adjacency.
- Clicking a valid destination moves the player.
- Nonadjacent destinations are rejected.
- Reload restores player progress.
- Camera movement does not interfere with editing or gameplay.

Avoid making screenshot snapshots the only test of correctness.

Visual regression tests may be useful later.

## 15. Subagent Strategy

Claude may use a separate frontend architecture or cartography subagent for the exploratory design work.

Recommended delegation:

**Main agent:**

- Reliability.
- Backend contracts.
- Authored-world integration.
- Movement semantics.
- Final architectural decisions.
- Integration and verification.

**Frontend architecture subagent:**

- LiveView versus Preact versus Solid evaluation.
- Component organization.
- MapLibre integration strategy.
- State management.
- Migration design.
- Frontend testing strategy.

**Cartography/design subagent, if useful:**

- Visual hierarchy.
- Palette.
- Typography.
- Map layer styling.
- Editor layout.
- Field Atlas layout.
- Movement indicator treatments.
- Topographic visual experiments.

These roles need not become permanent agents.

Avoid simultaneous edits to the same frontend files.

Prefer a shared design specification before implementation.

If subagents produce competing recommendations, the main agent should reconcile them and present one coherent proposal.

## 16. Non-Goals

Do not use this initiative to:

- Rewrite the GIS pipeline.
- Change backend language.
- Replace PostgreSQL.
- Introduce microservices.
- Build a separate frontend deployment system.
- Add a large state management framework automatically.
- Introduce a component library without evaluating its cost.
- Implement radio or Backrooms gameplay.
- Redesign the entire game domain.
- Migrate canonical authored data into browser storage.
- Remove V1 prematurely.

The scope is the frontend product experience and the minimum backend API work necessary to support it.

## 17. Requested First Deliverable

**Do not begin the V2 rewrite immediately.**

First, inspect the current frontend and backend interfaces.

Then produce a concise architecture and design proposal that answers:

1. Should V2 retain LiveView, adopt Preact, or adopt SolidJS?
2. How should map state and UI state be separated?
3. What API boundaries are needed?
4. How should Studio's editor interactions work?
5. How should Field Atlas implement one-hop exploration?
6. What should the shared visual system look like?
7. What is the smallest convincing V2 vertical slice?
8. How do we preserve V1 and all designer data during migration?
9. What new tests are needed?
10. Which V2 decisions depend on completing the current reliability and authored-map work?

Recommend one architecture and development sequence, rather than presenting a long list of equally weighted possibilities.

Treat this as a design review that the project owner can approve before implementation.

## 18. Final Guidance

Threshold V1 proved that the underlying geographic and game systems are feasible.

V2 should turn those systems into a cohesive product.

The editor should become a capable, pleasant geographic world-building environment.

The player interface should become an atmospheric, intuitive field atlas.

Both should share a carefully designed cartographic visual identity.

**Preserve the working backend. Redesign the browser experience deliberately. Build V2 beside V1. Validate one workflow end to end before migrating the rest.**

The goal is not simply to make Threshold look better.

It is to create a frontend architecture and interaction model appropriate for the game we are now building.
