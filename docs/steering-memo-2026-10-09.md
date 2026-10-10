# Threshold — Steering Memo for Claude Code

**From:** ChatGPT (GPT-6), Design and Architecture Review  
**To:** Claude Code  
**Date:** October 9, 2026  
**Repository:** https://github.com/jackwillis/threshold  
**Reviewed commit:** `bdd9f1fa6e92`  
**Purpose:** Reliability hardening, authored-map integration, and one-hop exploration

## 1. Background

We are transitioning implementation from Codex back to Claude Code.

Since Claude's previous handoff, Threshold has gained its first playable exploration system:

- Server-authoritative movement in Elixir.
- PostgreSQL-backed player progress.
- A dedicated player map at `/play`.
- Authored spawn points.
- Player-centered camera and walking animation.
- Glowing reachable navigation locations.
- Nearby authored-place inspection.
- Two-stop movement with a third-stop preview.

This is substantial progress.

However, the designer wants to revisit two gameplay decisions:

1. **Restore strict one-hop movement and visibility.**
2. **Integrate the designer's manually authored map into gameplay more completely.**

We also have an engineering reliability memo, *Reliability Pass 1*, identifying correctness risks in the current implementation.

This handoff should address those risks before significantly expanding gameplay.

## 2. Read First

Read the following repository files:

1. `AGENTS.md`
2. `docs/handoff.md`
3. `docs/implementation-status.md`
4. `docs/movement-design.md`
5. `docs/playable-route-review.md`
6. `docs/game-design.md`
7. `docs/architecture.md`

Also review the separate *Engineering Memo: Reliability Pass 1*, provided by the designer.

That memo is a review and set of recommendations, not blanket authorization for every proposed architectural change.

Verify findings against the current code before implementing fixes.

## 3. Protect Existing Designer Data

**This is a non-negotiable requirement.**

The designer has manually created locations and connections in:

`priv/worlds/madison/authored.json`

This file may contain uncommitted creative work.

Do not reset, overwrite, reformat, regenerate, or discard it.

Do not use the real authored file for experiments or tests.

Use a scratch world via `THRESHOLD_WORLDS_DIR` or the existing fixture worlds.

Inspect `git status` before making changes.

Do not commit, push, deploy, or acquire new OSM data without permission.

Preserve existing location IDs, authored connections, names, notes, and coordinates during any future migration.

## 4. First Priority: Reliability Pass

The reliability review identifies several plausible consistency defects.

These should be evaluated and addressed through small, testable changes.

### 4.1 Continuous integration

Introduce a minimal GitHub Actions workflow.

It should run on pushes and pull requests, configure the pinned Elixir/OTP, Python, Bun, and PostgreSQL dependencies, then execute `make check`.

Ensure PostgreSQL-backed tests actually run.

Do not silently skip database tests.

No deployment automation or extensive CI matrix is necessary.

### 4.2 Geographic publication consistency

Inspect `Threshold.Importer.regenerate/1`.

The current implementation stages a validated geographic build but renames generated files individually during publication.

A concurrent reader may observe a mixture of old and new generated files.

A publication failure may also leave a partially replaced generation.

Design a small, defensible solution that ensures readers observe one coherent geographic revision.

Possible approaches:

- A shared reader/writer synchronization mechanism.
- Immutable generated snapshots with one atomic active-version switch.

Evaluate the tradeoffs.

Prefer a small solution, but do not claim that writer-only locking or atomic renaming of individual files solves the multi-file consistency problem.

Include tests for publication failure and concurrent reads.

Coordinate generated-world publication with operations that depend on stable world revisions.

### 4.3 Authored-save concurrency

Inspect `Threshold.Authored.save/3`.

Currently, the content-hash comparison and subsequent file replacement are not protected as one serialized operation.

The temporary filename is also shared.

Harden the check-and-save operation against concurrent writers.

Preserve the existing file-based source-of-truth approach.

Test two competing saves from the same base revision.

Exactly one must succeed; the other must receive a conflict.

Apply consistent protection to boundary edits and related publication operations as appropriate.

### 4.4 Player movement concurrency

Inspect `Threshold.Game.Sessions`.

Retain PostgreSQL transactions, row locks, and expected-turn checks.

Add concurrent tests covering:

- Competing moves from the same turn.
- Competing moves to different destinations.
- Replayed requests.
- Failed moves.
- Reset versus movement.
- Concurrent initialization.
- World revision mismatches.

The persisted state must advance exactly once when competing requests use the same expected turn.

Avoid event sourcing, job queues, and additional infrastructure.

### 4.5 Geographic and anchor validation

Strengthen tests for:

- Connection endpoint validity.
- Continuous route geometry.
- Source-edge consistency.
- Reverse traversal.
- Closures.
- Boundary restrictions.
- Deterministic graph generation.
- Spawn reachability.

Review `Threshold.Authored.Edit.resolve_anchor/2`.

Do not trust client-provided coordinates when authoritative geometry can be derived from a referenced source edge and validated offset.

Maintain a clear distinction between the geographic anchor and the playable movement attachment.

### 4.6 Editor recovery

Evaluate browser refreshes, LiveView termination, disconnects, and failed regeneration with unsaved work.

A lightweight recovery-draft feature may be useful, but defer it if it complicates the initial reliability pass.

Never silently replace canonical authored data with a recovery draft.

### Reliability acceptance criteria

Before proceeding with substantial new gameplay:

- Complete checks run under CI.
- Concurrent authored saves cannot silently overwrite edits.
- Geographic readers cannot observe mixed generations.
- Concurrent movement behavior is verified.
- Invalid geographic anchors are rejected or corrected using authoritative data.
- Failure paths preserve canonical authored data.
- Documentation reflects the actual guarantees.

Report anything that remains unverified.

## 5. Second Priority: Restore Strict One-Hop Movement

The designer prefers the original one-hop movement model.

Currently, `Threshold.Game.walk_options/2` calculates:

- First-hop destinations.
- Second-hop destinations.
- Third-hop preview locations.

`Threshold.Game.move/3` permits a destination up to two connections away.

This should change.

### Desired behavior

The player occupies one movement location.

Only immediately adjacent, currently traversable destinations are displayed as glowing movement choices.

Clicking a destination advances the player exactly one connection and one turn.

After moving, available choices update.

Do not display second- or third-hop preview markers.

Previously visited locations may remain subtly indicated, but should not glow unless directly reachable.

Do not hide normal city geography simply because its navigation nodes are outside the one-hop neighborhood.

### Implementation guidance

Reuse `Game.available_moves/2` or extract a similarly simple adjacency API.

Remove unnecessary breadth-first movement discovery from the normal game interaction.

Update `PlayLive`, `PlayerMap`, and the movement tests.

Preserve the actual route geometry for animation.

Retain camera following, panning, zooming, recentering, and reduced-motion support.

Every successful movement should advance exactly one turn.

### Important distinction

This is not a request for a conventional fog-of-war system.

The player may see the ordinary street map around them.

Only immediate navigation choices should glow.

The intended experience is:

**You are here. These are the places you can go next.**

Do not provide movement choices beyond the next hop.

## 6. Third Priority: Integrate the Designer's Authored Map

The manually authored map should become a meaningful part of the playable world.

At present, authored locations can be associated with playable locations through a `movement_location` field.

This supports nearby inspection but does not fully integrate authored connections or designer-defined traversal.

The next design milestone should improve this relationship without corrupting the authored layer.

### Three separate representations

Maintain:

**Geographic routing graph**

The detailed imported pedestrian network.

Provides actual walkable geometry, access classifications, and route connectivity.

**Playable navigation graph**

The simplified network of positions where the player can stand and select movement choices.

**Authored game layer**

Designer-created locations, connections, restrictions, and fictional geography.

The authored layer contains intentional game-design decisions.

It should not be replaced by generated geographic data.

### The main design principle

**Keep an authored place's location separate from how the player reaches it.**

An authored marker represents where a place exists or where the designer wants to display it.

Its movement attachment identifies where the player must stand to interact with or enter it.

Its fictional connections express intentional relationships with other authored places.

Do not treat these as interchangeable.

## 7. Snapping and Attachment Workflow

The designer wants to bring the manually authored map into alignment with real Madison intersections, sidewalks, and movement nodes.

Do not automatically snap every authored marker to the nearest intersection.

That would lose important geographic intent.

Instead, implement a non-destructive attachment workflow.

### Suggested approach

When selecting an authored location, show:

- Its existing geographic position.
- Its geographic anchor.
- Nearby candidate playable nodes.
- The proposed movement attachment.
- The walking-network relationship between the candidates and the place.

Allow the designer to choose a playable attachment.

Where useful, the editor may suggest candidates based on geographic proximity.

However, a proximity suggestion must not imply reachability.

Check actual network connectivity.

### Preserve positions

Attaching a storefront to a sidewalk node should not move its displayed marker away from the storefront.

The attachment is a gameplay relationship, not a coordinate replacement.

If the designer explicitly wants to move a marker, provide a separate operation.

### Existing data

Do not change real authored locations automatically.

Begin with a read-only attachment audit.

Show which authored places are:

- Already attached.
- Unattached.
- Attached to missing playable locations.
- Ambiguous.
- Apparently disconnected from their suggested access point.

Then provide explicit repair controls.

### Regeneration

Generated playable node identities may change following regeneration.

Preserve stable authored IDs and source geographic anchors.

Detect stale movement attachments.

Do not silently remap them to a new node.

Where practical, derive attachment suggestions from stable source geography and current graph connectivity.

## 8. Authored Connections

The authored editor currently permits manual straight-line connections between authored locations.

These are not automatically valid pedestrian routes.

Distinguish at least two conceptual connection types.

### Ordinary pedestrian connection

Represents intended travel between authored places using the real pedestrian network.

A connection of this type must resolve to a valid walking path.

Its gameplay animation should follow geographic route geometry.

It must respect traversal restrictions.

### Fictional or anomalous connection

Represents an intentional game-world transition that may not correspond to a geographic walking route.

Examples include:

- Hidden entrances.
- Tunnels.
- Wormholes.
- Backrooms passages.
- Impossible shortcuts.

Such a connection may have no meaningful geographic polyline.

It must be explicitly authored and made available according to its game conditions.

### Migration caution

Existing authored connections have a `kind` field, but their original meaning should not be assumed.

Before applying new traversal semantics, inspect existing data on a scratch copy and develop a backward-compatible representation.

Do not automatically convert every authored connection into a pedestrian route or fictional teleport.

If meaning is ambiguous, flag it for designer review.

## 9. Effective Movement Graph

The eventual game should operate on an effective graph assembled from:

- Generated playable navigation connections.
- Explicit authored movement locations where appropriate.
- Approved authored transitions.
- Current traversal restrictions.
- Player discovery state.

Do not mutate the generated graph directly to inject authored content.

Construct or derive the effective gameplay representation separately.

Keep movement rules server-authoritative.

Do not introduce a general graph database, custom query language, or complex rules engine.

The first implementation may support only a small set of explicit transition types.

### Design example

The player stands at a sidewalk junction.

Two neighboring sidewalk nodes glow.

A nearby storefront appears in the interaction panel.

The storefront's marker remains on the building.

If the storefront has an enterable interior, the player may select Enter.

Entering moves the player to an authored interior location.

The interior may later have its own graph.

These interactions should share coherent movement rules without treating all places as ordinary street intersections.

## 10. Recommended Development Sequence

Treat these as separate, reviewable increments.

### Increment A — Reliability assessment

Confirm the memo's findings against the current repository.

Run the tests and report results.

Identify which risks are reproducible.

Provide a short recommended implementation sequence.

### Increment B — Reliability hardening

Implement CI, authored-save concurrency protection, and coherent geographic publication.

Add targeted concurrency and invariant tests.

Avoid unrelated refactoring.

### Increment C — One-hop movement

Restore single-hop movement and remove distant previews.

Keep the existing player interface otherwise recognizable.

Verify browser behavior.

### Increment D — Authored integration audit

Examine how current authored places and connections relate to the playable network.

Work on a scratch copy.

Produce an attachment report without modifying designer data.

Recommend the minimum backward-compatible schema changes.

### Increment E — Authored integration UI

Implement explicit attachment and reconnection controls.

Preserve manual marker positions.

Ensure authored places become reachable and inspectable through the intended navigation locations.

### Increment F — Authored transitions

Add the smallest useful support for authored movement connections.

Separate ordinary pedestrian travel from fictional transitions.

Verify one-hop adjacency over the combined effective graph.

### Increment G — Playtesting

Test the interaction around Capitol Square and First Settlement.

Evaluate whether the generated graph yields useful choices, whether authored locations are naturally encountered, and whether the camera and glows remain readable.

Only adjust node clustering based on observed gameplay problems.

## 11. Non-Goals

Do not introduce:

- New frontend frameworks.
- A rewrite of Phoenix or the GIS pipeline.
- Distributed locks or orchestration.
- Event sourcing.
- Background job infrastructure.
- Graph databases.
- Comprehensive fog of war.
- Automatic multi-hop travel.
- Radio simulation.
- Narrative scripting engines.
- Procedural Backrooms generation.
- Multiplayer.
- Major visual redesign.

These can wait.

The current goal is a dependable, coherent movement and world-authoring system.

## 12. Expected Claude Workflow

First inspect and evaluate the current state.

Report:

1. Which reliability findings are confirmed.
2. Which findings have already been resolved.
3. Which risks are most serious.
4. What changes are needed for strict one-hop movement.
5. What work is needed to integrate authored locations safely.

Then recommend a small first implementation increment.

Do not treat the entire memo as authorization to execute every phase immediately.

Ask before making consequential changes to the authored-world schema or behavior.

Keep commits small and reviewable, and request authorization before committing or pushing.

Run `make check` with PostgreSQL-backed tests enabled.

Document any limitations in verification.

## 13. Final Direction

Threshold now has a working geographic editor, movement system, persistent player state, and a generated pedestrian navigation graph.

The next task is to make these components work together reliably.

**The designer's map should matter.**

Authored places should retain their intended positions and identities while becoming naturally accessible through the navigation network.

**Movement should remain simple.**

The player stands at one location, sees only immediately reachable destinations glowing, and chooses a single step.

**Reliability should remain foundational.**

Failed operations must not leave authored content, generated geography, or player progress inconsistent.

Preserve the existing architecture, strengthen its correctness, and make the first playable exploration experience coherent before expanding the game further.
