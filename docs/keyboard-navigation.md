# Threshold — Radial Keyboard Navigation Design Memo

**To:** Claude Code  
**From:** ChatGPT (GPT-6), Game Design and Architecture Review  
**Date:** October 9, 2026  
**Status:** Proposed design  
**Suggested file:** `docs/keyboard-navigation.md`

## 1. Overview

Threshold is a turn-based geographic exploration game in which players move between locations on a graph.

The intended movement interface is simple:

**The player occupies a location. Immediately reachable neighboring locations glow on the map. The player selects one, moves there, and the next set of choices appears.**

We want to make this interaction accessible from the keyboard.

Each currently reachable destination receives a temporary numeric label from `1` through `9`, followed by `0` for the tenth destination.

Pressing the corresponding number moves the player to that destination.

Numbers are assigned in radial order around the player's current position, beginning at geographic north and proceeding clockwise.

The result should feel like a geographic adventure game that can be explored almost entirely through the keyboard.

## 2. Core Interaction

When the player arrives at a navigation location:

1. The server determines the immediately reachable destinations.
2. The client arranges those destinations by geographic bearing.
3. Each destination receives a number.
4. The map renders that number inside its glowing marker.
5. The movement panel displays the same number beside the corresponding destination.
6. The player can click the marker, click the movement-panel entry, or press its number.
7. The server validates and executes the selected movement.
8. The numbers are recalculated after movement.

The numeric labels are temporary interface shortcuts, not persistent identifiers.

Do not store them in the authored world, the generated graph, or player progress.

## 3. Radial Ordering

Use the player's current geographic location as the center of the radial ordering.

### Assignment rule

- Start at geographic north, corresponding to 12 o'clock.
- Sort reachable destinations clockwise.
- Assign `1` to the first destination.
- Continue through `9`.
- Assign `0` to the tenth destination.

For example, a four-way intersection with approximately north, east, south, and west exits would ordinarily produce:

| Bearing | Shortcut |
|---|---|
| North | `1` |
| East | `2` |
| South | `3` |
| West | `4` |

Only actual, currently available destinations receive labels.

Do not reserve numbers for empty compass sectors.

### Geographic bearings

Calculate geographic bearings from the current playable location to the neighboring destination coordinates.

Do not derive ordering from screen positions.

Map rotation, camera movement, zoom, viewport dimensions, and responsive layout must not change the numbering.

A suitable implementation may use a geographic bearing utility or a small dedicated function.

Use deterministic tie-breaking, such as destination ID, when bearings are equal or nearly equal.

### Important limitation

The direction of a connection's endpoint is not always the direction in which the walking route initially departs.

A winding path might begin eastward but end north of the player.

For the first implementation, destination bearing is acceptable and simple.

However, evaluate whether ordering by the initial segment of the actual route produces a more intuitive result at complex intersections.

If route-departure bearing is adopted, use the server-approved, directionally oriented walking geometry rather than a straight line between endpoints.

This should be a deliberate design choice, not an accidental consequence of rendering.

## 4. Strict One-Hop Navigation

Numeric shortcuts apply only to immediately adjacent, currently traversable locations.

The current design preference is strict one-hop movement:

- Only immediate neighbors glow.
- No second-hop or third-hop movement previews.
- No automatic multi-hop movement.
- One movement traverses one connection.
- One successful movement advances one turn.

Do not assign shortcuts to distant geographic features or merely nearby locations.

Adjacency must come from the effective gameplay graph.

The keyboard must never bypass the server's movement rules.

If V1 still supports two-stop movement, restore strict one-hop behavior before finalizing numeric shortcuts.

## 5. Visual Design

The numbered destinations should be visually integrated into the map's cartographic style.

### Current player

Use a distinct player marker that cannot be confused with a numbered destination.

### Reachable destinations

Each destination should have:

- A restrained teal or cyan glow.
- A clearly readable numeric label.
- A suitable clickable target.
- A visible hover, focus, or selection state.

Avoid excessive glow, flashing, or animations that obscure the underlying geography.

The numeric labels should remain legible over streets, buildings, parks, and other map features.

### Movement panel

The movement panel should use the same numeric assignments as the map.

For example:

- `1` — Walk north.
- `2` — Walk east.
- `3` — Enter the alley.
- `4` — Walk southwest.

These are illustrative labels, not fixed compass assignments.

Show distance and other useful context where available.

The user should be able to identify the corresponding option without inspecting technical node IDs.

### Authored locations

Authored game locations should have a distinct visual treatment.

A radio cabinet, storefront, or discovered entrance should not automatically receive a numeric movement shortcut merely because it appears nearby.

Numeric shortcuts represent movement destinations.

Interaction shortcuts, if added later, should use a separate, clearly documented control scheme.

## 6. Input Behavior

Listen for keyboard input while the player interface is active.

### Valid input

Use the ordinary number keys `0`–`9`.

Support numeric keypad keys where available.

The keyboard input should invoke the same action as selecting a destination with the mouse or touch.

Do not implement a separate movement engine for keyboard controls.

### Ignore input when appropriate

Numeric movement shortcuts must not activate when:

- A text input has focus.
- A textarea has focus.
- A contenteditable element is active.
- A modal dialog is open.
- The user is interacting with a control that expects numeric input.
- A movement animation or transition is already in progress.
- The game is not accepting movement commands.

Do not intercept browser shortcuts involving Ctrl, Alt, Meta, or other relevant modifiers.

Respect `event.defaultPrevented`.

### Key repeat

Ignore repeated keydown events generated by holding a key.

One physical keypress should request at most one movement.

Do not allow a held digit to initiate repeated movement through newly numbered destinations.

### Focus

The player should not have to click an invisible canvas to activate keyboard navigation.

However, keyboard shortcuts should operate only when the Field Atlas is the active interaction context.

The shortcut system should cleanly register and unregister event listeners with the player interface lifecycle.

## 7. Server Authority and Concurrency

Keyboard labels are client-side presentation state.

The canonical movement action must identify the actual destination or connection, not merely a numeric shortcut.

For example:

```elixir
Game.move(world, player, destination_id)
```

The browser resolves the pressed digit to a currently displayed move, then submits the corresponding destination through the existing movement interface.

The request should include the expected player turn or equivalent revision information.

The server must validate:

- The player's current location.
- The expected turn.
- Adjacency.
- Traversability.
- Applicable restrictions.
- World revision consistency.

A stale keypress must never cause movement to an unintended destination after the graph or available choices change.

On stale or rejected movement, refresh the available choices and show appropriate feedback.

Do not trust the client-provided numeric assignment as proof that a movement is valid.

## 8. More Than Ten Neighbors

The numbering system supports ten destinations per set.

The playable Madison graph will ordinarily have far fewer choices, but the interface must handle locations with more than ten available exits.

For the first implementation:

- Assign `1`–`9`, then `0`, to the first ten destinations in radial order.
- Keep additional destinations accessible using the mouse, touch, or movement panel.
- Clearly distinguish destinations without numeric shortcuts.
- Never silently remove valid movement options.

Consider keyboard pagination or another shortcut mechanism only if real gameplay demonstrates that more than ten exits is common.

Do not build a complicated paging system prematurely.

## 9. Backtracking

The previous location should be treated as an ordinary legal destination when a reverse connection is available.

It receives a number according to the same radial ordering.

Do not reserve a number exclusively for backtracking.

A dedicated backtrack shortcut, such as Backspace, may be considered later.

If implemented, it must still obey traversal rules. The previous connection may no longer be available because of a changed game condition.

Backtracking must not bypass authored closures, conditional passages, or other movement restrictions.

## 10. Interaction With Authored Geography

The effective movement graph will eventually combine generated navigation connections with explicitly approved authored transitions.

Numeric shortcuts should operate on this effective graph.

For example, if a discovered doorway leads into an authored interior location and entering it is modeled as movement, it may appear as a numbered destination.

An inspectable object at the current location should not automatically receive a movement number.

This preserves the distinction between:

- Navigation.
- Inspection.
- Entering a location.
- Other gameplay actions.

The keyboard system should remain independent of whether the destination is a sidewalk intersection, authored location, or fictional room.

Only the legal movement options matter.

## 11. Frontend V2 Architecture

This feature should be included in the Field Atlas V2 design.

However, its implementation does not require a frontend rewrite.

If the current interface is being maintained while V2 is developed, a small V1 implementation is reasonable.

Avoid coupling the keyboard shortcut logic directly to MapLibre.

Prefer a reusable mechanism that accepts a list of legal movement options and returns a deterministic mapping from shortcut keys to those options.

Conceptually:

```typescript
type NumberedMove = {
  key: string;
  destination: string;
  bearing: number;
};
```

A pure function can calculate radial ordering.

A UI controller or component can handle keyboard events.

MapLibre is responsible for rendering the resulting labels and markers.

This separation will make the feature easier to reuse in V2.

The backend should not need significant changes solely to support numeric labels.

## 12. Testing Requirements

### Ordering tests

Verify:

- North-first clockwise ordering.
- Correct handling of irregular bearings.
- Deterministic ordering for ties.
- Stable numbering under map rotation and zoom.
- Correct `1`–`9`, then `0` assignment.
- More-than-ten-destination behavior.

### Input tests

Verify:

- Number keys select the expected destinations.
- Numpad keys work.
- Repeated keydown events are ignored.
- Input fields suppress movement shortcuts.
- Modal dialogs suppress movement shortcuts.
- Modifier combinations are not intercepted.
- Listeners are cleaned up when the interface is destroyed.

### Gameplay tests

Verify:

- Only one-hop destinations receive shortcuts.
- A shortcut cannot move to an unavailable location.
- Movement advances exactly one turn.
- Stale requests are rejected.
- Number assignments update after movement.
- Keyboard and mouse selection use equivalent server-authoritative actions.

Use browser-level tests to verify the actual keyboard interaction.

Pure ordering tests alone are insufficient.

## 13. Suggested Implementation Sequence

1. Restore strict one-hop movement if not already completed.
2. Extract a deterministic radial ordering function.
3. Add numeric labels to the movement panel.
4. Add numeric labels to glowing MapLibre markers.
5. Implement keyboard input handling.
6. Add focus, modifier, and key-repeat protections.
7. Add unit and browser interaction tests.
8. Playtest complex intersections and irregular route geometry.
9. Evaluate whether ordering by destination or route-departure bearing is more intuitive.
10. Incorporate the finished interaction into the Field Atlas V2 design.

Keep changes small and reviewable.

Avoid coupling this work to unrelated map styling or architectural changes.

## 14. Acceptance Criteria

The feature is complete when:

1. A player starts at a valid spawn point.
2. Only immediately reachable destinations glow.
3. Each of up to ten reachable destinations has a unique digit.
4. Digits are assigned clockwise from geographic north.
5. Pressing a digit requests movement to its displayed destination.
6. The server validates movement.
7. A successful movement advances exactly one connection and one turn.
8. The map follows the player.
9. Numbers update for the new set of destinations.
10. Mouse and keyboard navigation produce equivalent results.
11. Typing into text fields never unintentionally moves the player.
12. Holding a number key does not cause repeated movement.
13. No existing authored data or canonical geography is modified.

## 15. Design Rationale

Threshold's movement graph is not merely a routing implementation. It determines the choices the player encounters while exploring.

Radial keyboard navigation makes those choices immediate and tactile.

The player can see the available exits, understand their relative directions, and select one with a single keystroke.

The changing number assignments reinforce the turn-based structure: every arrival presents a new local decision.

The map remains geographically faithful, while the controls feel closer to a roguelike or interactive adventure.

**The player should be able to explore Madison by looking at the map and pressing numbers, one intersection at a time.**

This should become a defining interaction of Threshold's Field Atlas.
