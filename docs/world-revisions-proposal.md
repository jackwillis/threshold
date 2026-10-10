# Proposal: session compatibility instead of whole-file revisions

Date: October 10, 2026 (revised after the designer's review). Status: **proposal for approval; nothing implemented.** Related: [gameplay-interactions.md](gameplay-interactions.md), [expanded-world-verification.md](expanded-world-verification.md).

## The problem

A saved walk records `world_revision`, and `Sessions.restore/2` refuses the save whenever it differs from the current world's revision (the player must start a new walk, which also deletes their discoveries). The revision hashes the exact bytes the movement world was built from, so renaming a place, fixing a typo in a note, or changing scene text resets progress. That is wrong for everything that does not change whether a saved position still works.

## Principles (from the designer's review)

1. **`world_revision` becomes a diagnostic stamp.** It is written on every successful write and shown when it differs, but it never gates anything by itself.
2. **Compatibility is an explicit, computed check**, not a hash comparison and not just "the location id exists". It asks whether the saved position is still a valid place to stand, and says why when it is not.
3. **Nothing is silently dropped.** Visited history and discoveries are never removed or rewritten by a compatibility outcome. The only operation that deletes them is the player's explicit, confirmed **New walk**, as today.
4. **Every non-compatible outcome has a defined recovery** that the player chooses; the game never relocates or resets on its own.

## The compatibility check

A pure function `Threshold.Game.Compatibility.check(world, progress)` over the compiled `Game.World` and the stored save. It runs everywhere `restore/2` runs today (load, move, complete), so every transaction applies one rule, under the same row lock.

**Position checks (in order; the first failure decides):**

1. **Exists.** `progress.location` is a key of `world.locations`. On the authored graph that already excludes places that cannot stand on the street network (free points without walking access, places on missing streets); on the generated graph it means the playable `pn:` id still exists.
2. **Traversable.** The location is a place the world can stand a player on, not merely a record: it has a standing point, and (authored graph) it was resolved by `RouteResolver` to a street position rather than left out as `:unanchored` or `:missing_edge`.
3. **Inside the playable boundary.** The location's standing point is covered by the playable boundary (`Geometry.inside?/2` on the boundary ring). A boundary that no longer contains the position makes it incompatible even though the id exists. This checks the position only; individual connections that leave the boundary stay unavailable exactly as now.

**Outcomes:**

| Outcome | Meaning | Play allowed |
|---|---|---|
| `:compatible` | Position is valid and the stamp matches. | Yes. |
| `:compatible_changed` | Position is valid but the stamp differs, so the world changed since this save last wrote. | Yes, with an informational note ("The map has changed since you last played"). Never blocks. |
| `:stranded` | Position is valid but no connection from it is currently available. | Walking has nothing to offer; investigating still works; recovery below is offered. |
| `{:incompatible, reason}` | Reason is one of `:location_missing`, `:not_traversable`, `:outside_boundary`. | Moves and completions are refused with a specific message; the page shows the recovery choices. |

**Reads versus writes.** `restore/2` returns the verdict alongside the player, and `Sessions.move/3` and `complete_interaction/5` proceed for `:compatible`, `:compatible_changed` and `:stranded` (a stranded move simply has no valid destination) and refuse `{:incompatible, _}` with `{:error, {:incompatible, reason}}`, writing nothing.

## What happens to history

- **Visited locations are never dropped.** The stored array is only ever extended. A visited id that no longer resolves stays in storage; it is excluded from the map markers and from the "places visited" figure, and the panel says how many are "no longer on the map" (for example "3 places visited (1 no longer on the map)"). If the place returns (an edit is undone), it counts again with no loss.
- **Discoveries and completed interactions are never touched** by a world change or a compatibility outcome. They are ids into `interactions.json` (see the interactions memo for removal and rename behaviour) and stay readable and inert if their content is removed. Only an explicit New walk removes them.
- **The turn counter and the save row are never rewritten** by a failed check.

## Recovery semantics

For `{:incompatible, _}` and `:stranded`, the panel offers, never applies automatically:

1. **Return to the starting point** (new): `Sessions.relocate(world, expected_turn)`, one transaction under the row lock. It requires the save to be incompatible or stranded (so it cannot be used as a free teleport), requires the default spawn to be a compatible position, moves the player there, adds the spawn to `visited`, **keeps the turn, the visited history and every discovery and completion**, and stamps the current revision. It spends no turn. If there is no valid default spawn the option is withheld and the message says to repair the spawn in the editor.
2. **New walk** (existing, with its confirmation): the only operation that clears history and discoveries.

A player who does neither simply stays on the recovery panel; nothing is lost.

## How each kind of edit behaves

| Edit | Behaviour |
|---|---|
| Location **name** or **notes** | Content. Applied on the next render; stamp differs, so an informational note at most; saves untouched. |
| **Scene text**, titles, choice labels, discovery labels | Content. Immediate; saved ids unaffected. |
| **Adding** a place, connection, closure or interaction | Compatible; new things become available. |
| **Moving** a place to another street (anchor or access) | Compatible if it still resolves to a standing point inside the boundary: same id, new position. |
| **Changing connections or closures** | Compatible; moves are validated against the current graph. If the player ends up with no available move: `:stranded`, with recovery. |
| **Spawn** changes | Affect new walks and "Return to the starting point" only. |
| **Deleting a place** the save stands on, or making it unwalkable (free point, missing street) | `{:incompatible, :location_missing}` or `:not_traversable`; recovery choices. Visited history kept. |
| **Shrinking the boundary** so it excludes the position | `{:incompatible, :outside_boundary}`; recovery choices. |
| **Deleting a visited place** | History kept in storage; shown as "no longer on the map". |
| **Regenerating geography** (generated graph) | Playable ids come from OSM; a vanished `pn:` id is `:location_missing`; otherwise compatible. |
| **Removing an interaction** | Completed rows and any discoveries it granted stay, inert. Players who earned a discovery keep it; new players cannot (the lint reports interactions that became unreachable). Re-adding the same id restores its completed state, so interaction ids are a stable contract. |
| **Removing or renaming a discovery id** | Saved rows stay but match nothing (a `requires` naming an undeclared id is a load error). A rename is a removal plus a new id; if that matters later, an `"aliases"` field maps old saved ids; deferred. |
| **Changing `requires`, a choice's `discovers`, or choice ids** | Not applied retroactively; recorded choice ids stay as history. Use New walk to replay. |
| **Moving an interaction to another place** | Completion is by id, so it shows as investigated at its new place. |

## What does not change

The row lock, the expected-turn check, `Game.move` validation, the world-cache keys (the compiled world is still keyed by the authored bytes, so edits recompile it), the `Sessions.reset` behaviour, and the interactions tables. No schema change is needed: `world_revision` stays as a column and becomes diagnostic.

## Tests (when approved)

Pure `Compatibility.check` tests over synthetic worlds: each reason, the order of checks, the position exactly on the boundary ring, the stamp differing with a valid position, a stranded position. Database tests: rename a place and edit its notes mid-walk (save continues, new text shows); delete the place the save stands on (moves and completions refused with the specific reason, nothing written, row untouched); shrink the boundary around the position (same); a missing visited place stays in the stored array through a successful move; discoveries and completions survive every outcome; `relocate` refused when compatible, works when incompatible or stranded, keeps turn, visited and discoveries, refuses with no valid spawn, is replay-safe under concurrent calls (16 competing relocations leave one coherent save); the stamp is rewritten on every write; the existing concurrency tests still pass. LiveView and browser: the recovery panel for each reason, "Return to the starting point" then a normal move, and the "no longer on the map" count.

## Needs your approval

1. **The three position checks and their order** (exists, traversable, inside the boundary), and the four outcomes.
2. **`Sessions.relocate/2` ("Return to the starting point")** as the non-destructive recovery: keeps the turn, visited and discoveries, requires a compatible default spawn, withheld otherwise.
3. **Visited display:** unresolved ids kept in storage and shown as a "no longer on the map" count, not counted as visited places.
4. **The informational "map changed" note** when the stamp differs but the position is valid, and that the stamp never blocks anything.
5. Whether a **stranded** position should also be reported when the player can still investigate something (the proposal: yes, with recovery offered but not required).
