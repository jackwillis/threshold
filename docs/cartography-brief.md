# Threshold — Cartography and Player UI Brief

> **Update 2026-10-09 (designer's direction):** the primary visual identity is **Classic Atlas**: warm ivory, detailed building footprints, sage parks, pale blue water, elegant curved street labels, subtle topographic influence, restrained movement markers. The design must support **spring, summer, autumn and winter** palettes and environmental treatments through one shared style system (paint only; geometry and gameplay never change with the season). Radio/sonar is a **secondary investigation overlay or instrument**, not the default map or HUD. See [frontend-v2-proposal.md](frontend-v2-proposal.md), section 6.

**Role:** Visual design and frontend implementation (handled by the main Claude Code session)  
**Scope:** Player-facing map appearance, interaction styling, and cartographic presentation

## Objective

Develop Threshold's distinctive visual identity as a turn-based geographic investigation game.

The map should combine:

- Precise municipal cartography.
- Subtle USGS-inspired topographic design.
- A restrained archival survey aesthetic.
- Modern interactive movement indicators.
- A mysterious but believable atmosphere.

The starting point is the existing Madison map and MapLibre implementation.

Do not replace the geographic foundation.

## Visual Direction

### Primary map

Use warm ivory or cream backgrounds, muted sage-green parks, subtle blue-gray streets, restrained building footprints, and fine pedestrian paths.

Favor legibility and cartographic precision over dramatic effects.

Avoid conventional commercial navigation-map aesthetics.

### Topographic influence

Explore fine contour lines, quiet terrain relief, survey annotations, and appropriate typography.

Topography should remain visually subordinate to streets, buildings, movement paths, and interactive locations.

Do not introduce DEM processing or new GIS infrastructure without approval.

### Movement indicators

The current player position must be immediately recognizable.

Only one-hop reachable destinations should glow.

Visited locations may remain subtly visible.

Authored places should look different from navigation nodes.

Movement routes must follow actual pedestrian geometry.

Avoid neon clutter, excessive animation, and large glowing circles that obscure the street map.

### UI

Keep the map as the dominant surface.

The context panel should be compact, readable, and responsive.

Develop an interface appropriate to a quiet geographic mystery rather than a tactical military application.

Support desktop and mobile layouts.

Respect reduced-motion preferences.

## Engineering Boundaries

Focus on:

- MapLibre layer styling.
- TypeScript presentation code.
- CSS and HEEx presentation.
- Existing map UI components.

Do not modify:

- Python GIS processing.
- Geographic graph structure.
- Elixir game rules.
- Authored-world schemas.
- Persistence.
- Server-side movement validation.

Check with the designer before any required data additions.

Do not modify the designer's uncommitted authored data.

## Deliverables

First produce a concise visual design proposal containing:

1. Recommended map palette.
2. Cartographic layer hierarchy.
3. Player and destination marker treatments.
4. Authored-place styling.
5. Typography and UI recommendations.
6. A minimal implementation plan.

Then implement the approved treatment as a small, reviewable frontend change.

Test it against the actual Madison map at close zoom levels.

Provide screenshots where the environment permits, and clearly identify what was actually verified.

Do not commit or push without authorization.

## Success Criteria

The player should immediately understand:

- Where they are.
- Which locations they can reach in one movement.
- Which places are authored game content.
- What geography surrounds them.

The map should feel like a believable, beautifully designed municipal field atlas that is gradually revealing a strange hidden world.

