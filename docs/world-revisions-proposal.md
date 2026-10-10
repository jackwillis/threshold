# Proposal: movement compatibility versus authored-content revisions

Date: October 10, 2026. Status: **proposal for approval; nothing implemented.** Related: [gameplay-interactions.md](gameplay-interactions.md), [expanded-world-verification.md](expanded-world-verification.md).

## The problem

A saved walk records `world_revision`, and `Sessions.restore/2` refuses the save (the player must start a new walk, which now also deletes their discoveries) whenever it differs from the current world's revision. The revision is a hash of the exact bytes the movement world was built from: `authored.json` (names, notes, anchors, connections, spawns, everything), the boundary, and the generated geography (the playable layer too, on the generated graph). So renaming a place, fixing a typo in a note, or moving a spawn resets a player's progress, which is wrong for everything that does not change what a saved position means.

## What a save actually depends on

A save holds a location id, a turn, visited location ids, and (new) discovery and completed-interaction ids. It is meaningful as long as **the location it names still exists in the world being played** and the ids it holds are not reused for something else. Ids are random (`loc:<hex>`, `pn:<osm node id>`) and never reused, so existence is the real test. Names, notes, scene text, connections, closures and spawns do not decide whether a position is valid; they decide what the player can do next, which is always evaluated fresh.

## Proposal (recommended): validate references instead of comparing a hash

Replace "revision must equal" with "the save must still make sense":

1. **Location exists.** If `progress.location` is not in the compiled world, the save is unusable: keep today's explicit block and "start a new walk" message. (Open question 2: an alternative is to relocate to the default spawn.)
2. **Visited is pruned in memory.** Ids no longer in the world are ignored; the stored array is rewritten, without them, on the next successful write. Nothing is deleted on read.
3. **Discoveries and completed interactions are never touched by a world change.** They are ids into `interactions.json`; see the table below.
4. **`world_revision` stays, as a diagnostic.** It is stamped with the current revision on every write, so it records which world a save was last played against, but it no longer gates anything. No migration is needed.
5. **Everything else is unchanged:** the row lock, the expected-turn check, `Game.move` validation (a move still needs a currently valid connection), the world cache keys (the compiled world is still keyed by the authored bytes, so edits recompile it), and the "New walk" action.

A save whose location survives but which is now stranded (no walkable connection) shows today's "No walkable routes from here" with the New walk button; no special handling.

### How each kind of edit behaves

| Edit | Behaviour under the proposal |
|---|---|
| Location **name** or **notes** | Content. Takes effect on the next render; saves untouched. |
| **Scene text**, titles, choice labels, discovery labels | Content. Immediate; saved ids unaffected. |
| **Adding** a place, connection, closure, interaction | Saves continue; new things are simply available. |
| **Moving** a place to another street (new anchor or access) | The id is the same place, so the save continues at its new position. |
| **Changing connections or closures** | Saves continue; moves are validated against the current graph. |
| **Spawn** changes | Affect new walks only. |
| **Deleting a place** the save stands on | Save unusable; explicit new walk (or relocate, question 2). Deleting a visited place only prunes `visited`. |
| **Regenerating geography** (generated graph) | Playable ids are OSM-derived; a save whose `pn:` id vanished is unusable as above, otherwise it continues. |
| **Removing an interaction** | Its completed row and any discoveries it granted stay, inert. If other interactions require that discovery, existing players keep it and satisfy them; new players cannot get it, which the lint already reports as unreachable. Re-adding the same id restores its completed state, so interaction ids are a stable contract. |
| **Removing or renaming a discovery id** | Saved rows stay but match nothing (a `requires` naming an undeclared id is a load error). A rename is a removal plus a new id: players lose it. If that matters later, add `"aliases": ["disc:old-id"]` to a discovery so saved rows still count; deferred until needed. |
| **Changing `requires`, a choice's `discovers`, or a choice id** | Not applied retroactively. Completed interactions keep the choice id they recorded as history; discoveries already granted stay. Use New walk to replay. |
| **Moving an interaction to another place** | Completion is by id, so it shows as investigated at its new place. |

## Alternative (not recommended): a movement digest

Hash only a canonical form of the compiled movement graph (location ids and standing points, connections, closures) and exclude names, notes and content. It is simpler to explain ("the map is the same") but still resets saves for harmless topology edits (adding a connection) that do not invalidate any save, and needs a new digest to define and keep stable. Reference validation gives the same protection for names and notes and strictly fewer needless resets.

## Risks

- A designer who edits the map heavily could leave a player standing somewhere that no longer connects to what they expect; the New walk button and the stranded message cover it, and this is a single-player development build.
- Narrative consistency is the author's responsibility: removing a discovery that later content needs is flagged by the lint but not blocked.

## Tests (when approved)

Rename a place and edit its notes mid-walk: the save continues and the new text shows. Add and remove connections: the save continues and moves follow the new graph. Delete the place the save stands on: unusable with the explicit message; deleting a visited place only prunes `visited`. Remove an interaction and a discovery: rows remain and are inert; completion of the remaining interactions still works. Revision stamped on write; stored revision never blocks. Concurrency tests unchanged and still pass.

## Needs your approval

1. **Reference validation (recommended) versus the movement digest.**
2. **When the saved location no longer exists:** block with "start a new walk" (today's behaviour, discards discoveries on reset) or relocate to the default spawn keeping discoveries (recommended only if you want long-lived saves while the map is still changing).
3. **Discovery aliases:** defer (recommended) or add now.
4. Confirm the stored `world_revision` becomes diagnostic only.
