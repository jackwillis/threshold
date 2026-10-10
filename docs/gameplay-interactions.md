# Gameplay interactions: first vertical slice

Date: October 9, 2026. Status: **design memo, nothing implemented.** Decisions below were made by the designer after an independent architecture review; "Needs approval" lists what is still open. Terms: [game-design.md](game-design.md) section 9 (encounters), [movement-design.md](movement-design.md) (sessions), [expanded-world-verification.md](expanded-world-verification.md) (runtime world cache).

## 1. Decisions adopted

- Content lives in a separate, version-controlled **`interactions.json`** per world.
- Vocabulary: an **Interaction** is authored content attached to a place. Its **Scene** is its presentation (title and paragraphs), embedded in it; there is no chained scene engine. A **Discovery** is a declared id the player can acquire. A **Completed Interaction** is the durable record that a player finished one.
- Discoveries are **declared ids**, not free strings. V1 supports one condition, `discovered(id)`, and one effect, `discover(id)`.
- Discoveries and completed interactions are stored in **separate PostgreSQL tables** scoped to the existing durable session.
- Opening and closing a scene is **transient** (LiveView state, nothing persisted). Only a validated **completion** writes anything.
- A one-hop move costs a turn; investigating and choosing are free. A scene being open never blocks movement; walking away closes it.
- Arriving at a place only **indicates** that an investigation is available. Nothing opens or completes automatically.
- First scene panel is **LiveView**; the map stays visible.
- Deferred: journal, chained scenes, scripting, inventory, timers, world simulation, the Studio V2 authoring tool.

## 2. Data format (`priv/worlds/<world>/interactions.json`)

Absent file = no interactions (every existing world, including Madison, keeps working untouched). Strict like `authored.json`: unknown keys are errors, ids are validated, saves (when Studio arrives) go through the same `WorldFile` lock and conflict hash, encoding is deterministic.

```json
{
  "format_version": 1,
  "discoveries": [
    { "id": "disc:tapping", "label": "The tapping is a signal" }
  ],
  "interactions": [
    {
      "id": "int:door",
      "place": "loc:a",
      "title": "Unmarked door",
      "requires": [],
      "scene": { "title": "A faint tapping", "body": ["Evenly spaced. It stops when you stop."] },
      "choices": [
        { "id": "knock", "label": "Knock back", "discovers": ["disc:tapping"] },
        { "id": "listen", "label": "Only listen", "discovers": [] }
      ]
    },
    {
      "id": "int:lamp",
      "place": "loc:b",
      "title": "Dead streetlamp",
      "requires": ["disc:tapping"],
      "scene": { "title": "It answers", "body": ["Three taps from inside the lamp post."] },
      "choices": [ { "id": "note", "label": "Note it", "discovers": [] } ]
    }
  ]
}
```

- Ids: `disc:<slug>`, `int:<slug>`; choice ids are slugs unique within the interaction. `place` is an authored location id (`loc:...`). `requires` is a list of discovery ids, all of which must be discovered (no negation, no `or`, V1). `choices` has at least one entry (a read-only scene uses one "Note it" choice, so completion is always an explicit act). Each interaction completes at most once.
- **Validation (pure, at load):** unknown keys; id formats; duplicate ids; every `requires` and `discovers` id is declared in `discoveries`; every `place` exists in `authored.json` (a missing place is reported, never silently dropped or rewritten, as for other references); a discovery that is required but never discoverable, or discoverable but never used, is a warning.
- **Lint, read-only:** a `mix threshold.interactions` task (same spirit as `threshold.audit`) prints those warnings and flags interactions whose place has no walking route (a free point without `access`). Changes nothing.

## 3. Persistence

Two additive tables, both keyed to the existing `player_progress` row (the "durable session": one row per world name and `player_key`; the authored graph is a separate world name `<world>:authored`, so each graph has its own session and its own discoveries).

```
player_discoveries
  id uuid pk, progress_id uuid -> player_progress (on delete cascade),
  discovery_id text, turn bigint, source_interaction_id text, inserted_at
  unique (progress_id, discovery_id)

completed_interactions
  id uuid pk, progress_id uuid -> player_progress (on delete cascade),
  interaction_id text, choice_id text, turn bigint, inserted_at
  unique (progress_id, interaction_id)
```

The unique indexes make replay safe even without application checks. Ids are text, not foreign keys into the JSON, so editing or removing content leaves old rows harmless; a discovery no longer declared simply never satisfies anything.

**Reset consequence:** `Sessions.reset/1` is an upsert that keeps the progress row's `id`, so `on delete cascade` does not fire. Reset must delete both child tables for that `progress_id` inside its transaction. A new walk (including the forced one after a world-revision change) starts with no discoveries.

## 4. Reconciling with revisions and the runtime-world cache

- **Revision.** `Game.World.revision` guards saved progress and hashes `authored.json` (plus boundary and edges), not `interactions.json`. Keep it that way: editing scene text must not reset a player's walk. Completion still goes through `restore/2`, so a revision mismatch blocks it exactly like a move.
- **Cache.** `Threshold.WorldCache` holds the compiled movement world keyed by generation, authored hash, boundary hash and graph mode. Interactions are **not** put in it for V1: they are a small JSON file, parsed and validated against the world's places per LiveView event (measured in step 1, parse plus validate plus lint, upper bound for the per-event cost since lint need not run per event: 0.07 ms for 2 interactions, 2.4 ms for 50 interactions (92 KB), 13.5 ms for 200 interactions (370 KB); the world build the cache removed was 150 ms). If it grows or gains graph effects (for example locked connections), `interactions.json`'s hash becomes one more key component; no other cache change is needed.
- **Graph modes.** An interaction names an authored place. On the authored graph the player stands on that place; on the generated graph a place is reachable through `movement_location` and appears under `Game.nearby/2`. Do **not** use `Game.nearby/2` for this: on the authored graph `EffectiveGraph` only lists places that have a non-default name or notes, so an interaction on a still-unnamed place would never appear. Availability instead uses a small new `Game.at_place?(world, player, place_id)`: on the authored graph the place id equals the player's location; on the generated graph the place's `movement_location` equals it. One rule, tested on both graphs.
- **Database disabled** (`database_enabled: false`): interactions are unavailable, like saves.

## 5. Transactional API

All in `Threshold.Game.Sessions`, using the same per-session row lock (`SELECT ... FOR UPDATE`) as `move/3`.

```elixir
# Read model: one query each, no lock, for rendering.
Sessions.interaction_state(world) ::
  {:ok, %{discovered: MapSet.t(), completed: MapSet.t()}} | {:error, term}

# Pure, no database: which interactions the panel offers for the player's place.
Threshold.Interactions.at(content, world, player, state) ::
  [%{interaction: map, status: :available | :completed}]
  # hidden until every `requires` is discovered; completed ones are listed but not actionable

# The only write.
Sessions.complete_interaction(world, content, expected_turn, interaction_id, choice_id) ::
  {:ok, %{completed: map, discovered: [String.t()]}}
  | {:error, :stale_turn | :unavailable | :already_completed | :unknown_choice | :missing_save | String.t()}
```

`complete_interaction` runs one transaction: lock the progress row; `restore/2` (revision and location checks); `turn == expected_turn` else `:stale_turn`; the interaction exists, `Game.at_place?/3` is true for its place and the player's current location, every `requires` is in `player_discoveries` read **inside the lock**, it is not already completed, and the choice belongs to it, else the specific error with nothing written; insert the `completed_interactions` row and each `discovers` id (`on conflict do nothing`). Completion does not change the turn. Open/close are LiveView assigns only; `move` clears the open scene.

## 6. Interface (LiveView, first version)

- Arriving shows a line in the side panel, "Something here can be investigated", per available interaction; it does not open anything. The existing Nearby inspection (place notes, free) is unchanged.
- "Investigate" opens the scene in the panel (title, paragraphs, choice buttons). The map stays visible. The panel is a labelled region with a polite live region, **not a modal dialog**, so number keys keep meaning "move" (choices are buttons, not numbered shortcuts); the existing keyboard handler is unchanged.
- Choosing sends `complete_interaction` with the turn the panel was rendered for. A stale or rejected result shows the same kind of message moves do and refreshes the panel. Walking away closes it.
- Completed interactions show as "Investigated" and are not re-openable in V1. An interaction whose requirements are unmet is simply not shown (no hint); both are open to change in content, not in design.

## 7. Test plan

**Pure (`Interactions`):** unknown keys; bad ids; duplicates; undeclared discovery ids; missing place; warnings for unused or unreachable discoveries; `at/4` hides unmet requirements, shows completed ones, ignores other places; deterministic encode/parse round trip.

**Database (real transactions, independent connections like the existing concurrency tests):** complete once writes one completion and its discoveries; replay returns `:already_completed` and writes nothing; 16 concurrent completions of one interaction produce exactly one row set; completing B before A's discovery exists is rejected even though the request is well formed; stale turn after a move is rejected; a request from the wrong place is rejected; a choice from another interaction is rejected; revision mismatch blocks; moving, opening and closing write nothing; reset (and forced restart) clears both tables; deleting content leaves old rows harmless.

**LiveView:** arrival shows the indicator and does not open; open writes no rows; choosing records, and the second interaction then appears at its place; movement is not blocked while a scene is open and walking away closes it; disabled database shows no interactions.

**Browser (scratch world, scratch PostgreSQL, headless Firefox):** the A then B flow on the synthetic world; keyboard movement still works with a scene open; reload restores completions and discoveries. Fixture: the existing `test/fixtures/worlds/tiny` plus a fixture `interactions.json` with two places; never the Madison world, which has no `interactions.json`.

## 8. Implementation sequence (small commits, each passing `make check` with the database URL set)

1. `Threshold.Interactions`: schema, strict validation, load/encode, lint task, fixture, pure tests. **Done**; per-event load cost measured above.
2. Migration, two Ecto schemas, `Sessions.interaction_state/1`, `complete_interaction/5`, reset cleanup, database and concurrency tests. **Done** (`Game.at_place?/3` was added here because completion needs it).
3. `Interactions.at/4` read model and its tests. **Done.**
4. `PlayLive` panel: indicator, open/close, choose, stale handling, LiveView tests. **Done.**
5. Browser verification on the scratch world; short note in this memo and `handoff.md`. **Done**, see section 10.

## 9. Incompatibilities found, and what needs approval

None blocks the slice. Flagged:

1. **Reset must clear the new tables.** `reset/1` upserts and keeps the row id, so cascade deletes do not apply; the transaction must delete explicitly. *Needs your confirmation that a new walk (and the forced new walk after a revision change) discards discoveries.* I assume yes.
2. **Revision is coupled to all of `authored.json`.** Editing any place's name or notes already resets saved walks; with discoveries stored it hurts more. Out of scope for the slice; I recommend deciding before real playtesting whether the revision should cover only geography, graph and spawns. *Needs your decision later, not now.*
3. **Additive migration on your development database.** The new tables are additive, but your dev PostgreSQL holds your real saves. I will migrate only scratch databases; `mix ecto.migrate` against your dev database is your step.
4. **Defaults I will use unless you object:** unmet interactions are hidden (no hint); completed ones show as "Investigated" but are not re-openable; every interaction has at least one choice; each completes once.
5. **`Game.nearby/2` hides unnamed places** on the authored graph (see section 4), so it cannot define where an interaction is available; `at_place?/3` is added in step 3.
6. **Free-point places** without `access` are unwalkable, so their interactions are unreachable; the lint reports this (the walking-access field is how it gets fixed).

Nothing here requires touching `authored.json`, the Madison boundary, generated snapshots or the active symlink.

## 10. Implementation status and verification (October 10, 2026)

Steps 1-5 are implemented and committed. Commits: the pure module and lint task; persistence and `complete_interaction/5`; the `at/4` read model; the `/play` panel.

**Verified by tests** (`make check` with the disposable test database, 0 failures): strict validation and lint; every `complete_interaction` rule above (replay, forged request for a hidden interaction, wrong place, stale turn, unknown choice and interaction, revision change, missing save, reset, forced restart, removed content, per-session scope, unique-index backstop); independent-connection concurrency (16 competing completions record exactly once; a move or a reset racing completions leaves a coherent save, repeated runs); the LiveView panel on the authored graph (arrival only indicates, open/close writes nothing, choosing records for free and unlocks the second place, the other choice does not, an open scene does not block movement and walking away closes it, forged and stale completions are refused, completions survive reload, a new walk discards them, no interactions or an invalid file never breaks the walk).

**Verified in a browser** (headless Firefox, scratch tiny world, scratch PostgreSQL, never Madison): arrival shows "Something here can be investigated" with no scene and no rows; opening a scene writes nothing; pressing the move key with a scene open moves and closes it; at the second place before the discovery nothing is offered; after choosing "Knock back" at the first place the second place offers "Dead streetlamp"; both completions and the discovery are in the database (1 discovery, 2 completions) with the turn unchanged by the choices; reload shows both as investigated. Screenshots were reviewed for layout; the choice buttons' underline was fixed afterwards and that CSS change was not re-screenshotted.

**Accessibility increment (October 10):** a persistent live region (`#interaction-live`, always rendered, polite, atomic) announces arrival ("Something here can be investigated: ..."), recorded outcomes and refusals; the visible outcome text is not itself a live region. The investigate button is a disclosure (`aria-expanded`, `aria-controls`); opening moves focus to the scene title; the Close button and Escape (`phx-window-keydown`) return focus to that button; completing moves focus to the new outcome text (a fresh element per outcome, so `phx-mounted` fires each time). The scene is a labelled region, not a modal dialog, so the number keys keep moving. Verified in headless Firefox on the scratch world at desktop width and the narrowest viewport Firefox allows (500 px): focus targets after open, Escape, Close and completion; live region text; the digit shortcut moving the player with focus inside the scene and after completion; radial numbering unchanged (east 1, west 2 from the second place); no horizontal overflow; choice buttons 49 px tall (the text Close link was enlarged to 44 px afterwards and not re-measured). Not verified with a real screen reader, so announcement timing is by construction, not by listening. A known gap: if a number key walks away while focus is inside the scene, the scene is removed and focus falls to the page body.

**Not verified or not done:** the generated graph in a browser (covered by the pure `at_place?/3` tests only); the migration against the designer's development database (deliberately not run). Studio V2 authoring, the journal and everything in section 1 "Deferred" remain unbuilt.

## 11. Scene presentation (October 10, 2026)

The investigate panel is styled as a field-notebook page inside the Classic Atlas panel; no semantics, schema or movement rule changed. CSS lives in `priv/static/assets/css/atlas.css`, markup in `play_live.ex`:

- **Page:** paper ground with a margin rule, a small "Field note" eyebrow, the scene title in Atlas Serif (25 px), body at 17/28 px. Choices are italic serif entries with a leading em dash, at least 44 px tall, with a quiet hover tint; they stay unnumbered because the number keys move the player. The text Close button is 44 px tall.
- **Discovery outcome:** a short note with a "Noted" stamp (decorative, `aria-hidden`; the live region still says "Recorded: ...") and a left rule; refusals are a muted italic line; finished interactions read "Investigated: ..." with a check mark. Decorative pseudo-content uses empty alternative text.
- **Motion:** the scene and the outcome fade and rise 4 px over 0.22 s; choice hover tint transitions 0.15 s. With `prefers-reduced-motion: reduce` all animation and transitions are off.
- **Focus:** unchanged from the accessibility increment; the visible ring wraps the focused title, choice or outcome text (the outcome text now has a little padding so the ring does not hug it).

**Verified** in headless Firefox on a scratch world and scratch database at 1400 and 420 px: computed fonts and sizes, 44 px choice targets, no horizontal overflow, focus ring on a choice and on the outcome, screenshots reviewed, and reduced motion (Firefox `ui.prefersReducedMotion`) turning animations to `none` and transitions to `0s`. Not verified: other browsers, a real screen reader, dark themes, and the panel in each season (the panel uses fixed paper colours, not the season tokens).

**Room left for portraits and dialogue (not built, no schema change).** The scene is a header (eyebrow and title), a body of paragraphs and a choice list, so a portrait can later sit beside the header (a small grid with a fixed-size figure column) and a speaker line can style a paragraph. Simple dialogue is the existing model: a scene whose paragraphs are the speaker's words and whose choices are the player's replies, each granting discoveries. A future optional `speaker` (`name`, `portrait` asset id) on a scene or paragraph would be additive and validated by `Interactions`; portraits would be bundled assets like the fonts. Chained dialogue (a reply leading to another scene) is the deferred scene-chaining decision, not part of this pass.
