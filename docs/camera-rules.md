# Threshold — Field Atlas Camera and Viewport Rules

**To:** Claude Code  
**Status:** Approved design direction for Frontend V2  
**Applies to:** Player-facing Field Atlas only  
**Related:** Frontend V2 Architecture Memo, Radial Keyboard Navigation Memo

## 1. Objective

The Field Atlas should behave like a constrained, player-centered geographic exploration interface rather than an unrestricted map viewer.

Players explore the world by traveling between navigation nodes, not by freely scrolling across Madison.

The camera should permit limited local inspection while keeping the player's immediate surroundings and movement choices central to the experience.

## 2. Camera Configuration

Use the following initial settings:

| Setting | Value |
|---|---|
| Minimum MapLibre zoom | **17.0** |
| Maximum MapLibre zoom | **19.5** |
| Initial zoom | 18.5, configurable by authored spawn |
| Maximum camera-center displacement | **200 meters** from current player |
| Camera following | **After each completed move** |
| Recenter control | Enabled |
| Map rotation | North-up by default |

These values should be configurable rather than scattered as hardcoded constants.

A camera displacement of `0` meters means that the camera center is locked to the player's location.

The 200-meter restriction applies to the **camera center**, not every visible point within the viewport.

## 3. Camera Following

When the player completes a valid movement:

1. Update the authoritative player location.
2. Animate movement along the actual geographic route.
3. Move the camera to the destination using a restrained transition.
4. Recompute camera constraints around the new player location.
5. Display the newly available one-hop movement choices.

The camera should follow movement automatically, but players may subsequently pan and zoom within the permitted limits.

Manual camera movement must not alter player position or navigation eligibility.

The Recenter control returns the camera to the player's current location.

Honor reduced-motion preferences.

## 4. Player-Relative Pan Restriction

The camera center may be displaced no more than 200 meters from the player's current geographic position.

Implement this using geographic distance, not an arbitrary longitude/latitude offset.

A simple local-distance calculation or appropriate geodesic utility is sufficient.

When the player attempts to drag the camera beyond the radius, constrain the resulting center to the closest permitted position.

Prefer smooth, predictable behavior without aggressive snapping or jitter.

Support mouse dragging, touch gestures, inertial movement, and programmatic camera transitions.

Do not constrain the editor's camera using these gameplay rules.

## 5. Intersection With World Bounds

The camera must also respect the playable world's geographic limits.

The effective allowed camera-center region is:

**Allowed centers = player-centered 200 m region ∩ permitted world region**

Both constraints apply simultaneously.

For irregular world boundaries, distinguish the actual polygon from its rectangular bounding box.

MapLibre's rectangular bounds may provide a convenient coarse restriction, but they do not fully enforce an irregular polygon.

Use a lightweight additional constraint if the game requires polygon-accurate camera-center restrictions.

Do not introduce a complex geographic clipping system solely for this feature.

The playable world boundary remains a gameplay restriction enforced by the server. Camera restrictions are presentation rules and must not substitute for movement validation.

### Edge cases

If the player is near the world boundary, the camera should still be able to center on the player.

If the intersection is small, favor keeping the player visible over preserving a comfortable amount of panning freedom.

Ensure that the valid center region is never empty for an otherwise valid player location.

Do not allow the camera to jump or oscillate between competing constraints.

## 6. Keeping Reachable Nodes Visible

Camera restrictions must not make valid one-hop destinations impossible to see or select.

After a movement, calculate the positions of the currently reachable neighboring nodes.

Attempt to frame the player and those nodes within the viewport while respecting the configured zoom range.

Use the following priority:

1. Keep the player visible.
2. Keep all immediately reachable destinations visible where possible.
3. Respect world and camera-center bounds.
4. Prefer the normal close-up zoom and composition.

If all destinations cannot fit within the viewport at zoom 17.0, **do not violate the zoom restriction automatically**.

Instead, preserve access through the numbered movement list and keyboard shortcuts.

Consider a subtle directional indicator for an offscreen reachable node.

Do not silently hide or disable a valid destination because it falls outside the viewport.

Similarly, if the camera cannot center directly on a distant one-hop node without exceeding its tether, it should still animate the route and settle on a valid camera position after movement.

The movement graph, not camera position, determines reachability.

## 7. Integration With Radial Keyboard Navigation

Numeric movement shortcuts remain available regardless of camera position.

Destinations are numbered in radial order using geographic bearings, not screen coordinates.

Camera panning and zooming must not change the numbering.

Only legal one-hop destinations receive numeric movement shortcuts.

Pressing a number submits the same server-authoritative movement command as clicking a marker.

After movement, the camera follows the player and the numbered destinations are recalculated.

The camera must not consume numeric shortcuts or interfere with keyboard focus handling.

## 8. Implementation Guidance

Use native MapLibre zoom constraints:

- `minZoom: 17`
- `maxZoom: 19.5`

Implement the dynamic player-relative camera-center restriction separately.

Keep camera constraints in a dedicated frontend module or controller so that Field Atlas V2 can reuse them.

Avoid duplicating movement rules in the frontend.

The editor should retain its own, more flexible camera configuration.

Do not modify canonical world geography, playable nodes, or authored locations to enforce viewport constraints.

## 9. Acceptance Criteria

The implementation is complete when:

- Zoom cannot go below 17.0 or above 19.5 through ordinary user gestures or controls.
- The camera center cannot be moved farther than 200 meters from the player.
- A configured displacement of zero locks the camera center to the player.
- The effective camera region respects both the player-relative tether and the world boundary.
- The camera follows the player after movement.
- Manual local panning remains possible between moves.
- Recenter returns to the player.
- One-hop movement remains possible even when a destination is offscreen.
- Numbered movement shortcuts remain stable under camera changes.
- Map dragging, touch gestures, animations, and reduced-motion behavior work correctly.
- Studio's geographic editing capabilities are unaffected.

## 10. Final Design Principle

**The player moves through the city; the camera follows the exploration.**

The map should provide enough freedom to inspect the immediate environment without allowing players to survey the entire game world from one location.

The player-centered camera, strict one-hop movement, and radial keyboard navigation should reinforce one coherent exploration experience.

## Implementation notes (V1 player map, 2026-10-09)

Implemented in the current Field Atlas (`/play`), not only in V2. Rules live in `assets/src/map/camera.ts` (pure, 11 tests in `camera.test.ts`, run by `make check`) and are applied by `hooks/player_map.ts`. The Studio editor keeps its own camera.

- **Limits** default to zoom 17 to 19.5 and a 200 m tether, with the authored spawn zoom clamped into range. They are overridable in one place: `config :threshold, :atlas_camera, min_zoom: ..., max_zoom: ..., max_displacement_m: ...` (0 locks the centre to the player). Zoom uses MapLibre's `minZoom`/`maxZoom`, so wheel, pinch, controls and `fitBounds` all respect it.
- **Tether** is geographic distance from the player's current location. User gestures (drag, inertia, wheel, pinch) are clamped as they move; programmatic moves are allowed to run and are corrected with a short ease when they settle, so a camera animating towards the destination is never snapped mid-flight.
- **World bounds** are the playable boundary's bounding box (a coarse limit; no polygon clipping), intersected with the tether by alternating projections. The box is grown to include the player so the region is never empty, and the clamp is idempotent so it cannot oscillate between the two constraints.
- **Following:** after each move the camera frames the player and the new one-hop destinations (existing behaviour), then the tether re-anchors to the new location. Recenter does the same. Reduced motion skips the easing.
- **Offscreen destinations:** if the neighbours cannot all fit at zoom 17 the zoom is not violated; they stay reachable from the numbered list and keyboard shortcuts. The optional directional indicator for an offscreen node is not built.

Browser verification (headless Firefox, scratch Madison, test database): three large drags each stopped with the centre exactly 200 m (and once 188 m, at the bounds) from the player; wheel and API zoom-out stopped at 17 and zoom-in at 19.5; Recenter returned the camera to the player's framing; a programmatic jump 4 km away settled back at 200 m; after a keypress move the camera followed and the tether re-anchored. Not verified: touch gestures and inertia on a real touch device, reduced motion, the polygon-accurate boundary (only its bounding box is enforced).
