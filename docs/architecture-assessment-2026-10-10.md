# Threshold — End-of-Night Architecture Assessment

**Date:** October 10, 2026 (end of October 9 local development session)  
**Baseline:** `main` at `6d59e97` when reviewed  
**Status:** Architecture assessment and next-session decision guide; **no new feature authorization**

## Executive assessment

Threshold has crossed from a geographic editing prototype into a small playable narrative game. The first complete chapter, **The Quiet Hour**, is now in `priv/worlds/madison/interactions.json`: four approved places, seven interactions, seven discoveries, two narrative branches, and two endings. The handoff reports scratch-world headless-browser playthroughs covering both branches and endings (19- and 21-hop variants), and the full gate at `cd9f7c3`: **311 Elixir, 42 Bun, 38 Python tests**, plus formatting, type checks, lint, world validation, and deterministic rebuild. These are *reported* verification results, not a fresh execution for this memo. The designer has **not yet done a human playthrough**.

**Assessment:** Keep the architecture. The major design choices are coherent and now supported by executable examples. The immediate risk is not the wrong language or framework; it is allowing systems work to outrun evidence about the player's experience. **Next session begins with playing The Quiet Hour and taking notes, not implementing another engine.**

## What is working well

1. **Real geography, playable graph, authored content, and player knowledge are distinct.** Pinned OpenStreetMap inputs and deterministic GIS builds are preserved separately from authored locations and interactions. Fictional geography can eventually change traversal or visibility without falsifying source geography.
2. **The functional core is emerging.** `Threshold.Game.move/3` validates and returns a transition; `Threshold.Interactions.at/4` computes available scenes; `Threshold.Game.Sessions` uses PostgreSQL transactions, row locks, expected-turn checks, and uniqueness constraints for durable progress. Opening a scene is presentation state; completing one is a validated write.
3. **Immutability is already paying off.** Generated geography is atomically published as a coherent snapshot. `Threshold.WorldCache` keys compiled movement worlds by their inputs, avoiding repeated route resolution while respecting changes.
4. **The content vocabulary is small and analyzable.** Declared discoveries, prerequisites, choices, and one-time completions support the first branching mystery without embedding a general-purpose language. Validation and reachability lint remain useful.
5. **Presentation remains independent of simulation.** Classic Atlas, its four seasonal palettes, and subtle deterministic watercolor materials render through MapLibre without changing player state. The investigation notebook follows the same visual language.
6. **The project is still a modular Phoenix application.** The Python GIS pipeline does offline processing. No separate game service, Redis, actor-per-player framework, or universal scripting runtime is justified.

## Concrete concerns and decisions

### P0 before any public multi-user deployment: isolate players and hide spoilers

`Game.Sessions` currently scopes progress to `player_key: "local"`. That is appropriate for a local single-player prototype but would cause different visitors to share progress if deployed unchanged. Introduce a server-assigned, authenticated or signed player/session identity and ensure every operation is scoped to it. Do not trust a client-supplied key.

The world endpoints currently expose authored layers and notes. A map layer being visually hidden does not make its underlying data secret. Before hosting, split public/client-safe cartography from editor-only content and project player-visible discoveries server-side. Verify these boundaries with authorization tests.

### P1: revise saved-world compatibility, without silently discarding progress

Current `Sessions.restore/2` rejects a save when the whole-file `world_revision` changes, even for harmless text edits. The **unimplemented** proposal in [world-revisions-proposal.md](world-revisions-proposal.md) correctly separates diagnostic revision identity from the actual question of whether a saved position is valid.

Support explicit outcomes (compatible, changed-but-compatible, stranded, incompatible with reason), preserve visited/discovered/completed records, and offer player-chosen recovery. Review the proposal's approval questions before implementing. If published releases become immutable, identify the exact release used by each command; an old cached world must not silently govern a write after publication switches.

### P2: clarify the future ownership of authored data

Today the source of truth for authored world content is reviewable JSON/GeoJSON files, while PostgreSQL stores game progress. This works. A *future* hosted Studio may use PostgreSQL for mutable drafts and editor leases, with validated, immutable published releases and deterministic GitHub exports. Decide on **one** authority for authored content at that stage; do not create automatic bidirectional DB/Git synchronization. Keep pinned source geography and derived build artifacts independent.

A nightly GitHub export is an archive and review mechanism, **not** a substitute for PostgreSQL backups and restore drills. If adding an editing lease, use a per-world database-backed renewable token, validate it atomically with each mutation, and retain revision checks for stale tabs. A shared world editor does not imply simultaneous editing of that world.

### P3: build an explicit compiled-world boundary only as needed

`Game.World` already compiles source geography and authored connections into an immutable usable graph. As the world grows, consider indexing adjacency by location rather than scanning all connections in `Game.available_moves/2`, and indexing interactions by place rather than filtering all interactions per lookup. Benchmark first. There is no current reason to replace MapLibre, Phoenix LiveView, Ecto, or the Python importer.

Keep these concepts distinct:
- **World definition:** places, routes, scenes, declared discoveries.
- **Runtime state:** current traversability or active anomalies, when such mechanics exist.
- **Player progress:** position, visited history, completed choices.
- **Player knowledge:** facts and revealed entities that determine what the client may see.

A player's map should ultimately be a *projection of permitted knowledge*, not a dump of all authored world facts. Don't build a generic epistemic engine for this.

### P4: resist premature scripting and event sourcing

The Quiet Hour validates the current declarative approach. Before considering Lua, Fennel, Scheme, or Gleam for scene scripts, implement an actual mechanic that cannot be represented cleanly by validated conditions and effects. Later effects may include revealing a connection, but that would be a server-validated command, not direct script database access.

Similarly, a small transactional activity history could eventually help diagnostics or the Field Journal. Do not change the source of truth to full event sourcing without a demonstrated replay/audit requirement. Do not introduce GenServers for ordinary turn-by-turn records; use supervised processes when a *live process* actually needs its own lifecycle.

## Player-experience questions the architecture cannot answer

The Quiet Hour route crosses roughly 2 km and up to 21 hops. This is not automatically too long: quiet movement may be a deliberate atmospheric feature. Only a human playthrough will tell us whether it feels contemplative or repetitive. In particular:

- Does the opening explain why the player should reach the Square?
- Does passing the church before its scene unlocks create curiosity or confusion?
- Can the player remember the significance of the bulletin and hatch without a journal?
- Does the hatch choice feel consequential?
- Are the map and investigation indicators sufficient to prevent aimless inspection of every node?
- Is the player reasoning, or merely following a sequence of prerequisite flags?

**Preserve the designer's explicit decisions:** no automatically added Nearby notes, no default-spawn change yet, no pacing interventions before playing; future environmental notes are persistent observations, not hidden conditional events.

## Proposed next-session order — not authorization

1. **Run the existing interaction-progress migration on the designer's development database** after checking the local environment, as described in [handoff.md](handoff.md); the agents intentionally did not run it there.
2. **Play The Quiet Hour personally**, including returning to the Square. Record friction, confusion, repetition, and moments of surprise. Do not change the story or add systems first.
3. **Review the already-recorded near-term UI requests** in [near-term-features.md](near-term-features.md): narrative introduction, Field Journal, and distinct map indicators for notes/available investigations. The Field Journal should derive from existing discoveries and completion records where possible, revealing no unknown leads or locations; it should aid reasoning rather than become a quest-arrow system.
4. **Separately approve or revise session compatibility** before editing world content frequently while preserving active saves.
5. **Before public hosting**, implement player isolation, spoiler-safe world endpoints, operational database backups, and deployment/CI verification.
6. **Only after playtesting demonstrates a need**, add dynamic route/knowledge effects, richer conversations, the Studio narrative editor, database drafts and renewable leases, or an embedded scripting runtime.

## Scope guardrails

- Do **not** refactor working modules into speculative contexts merely to match diagrams.
- Do **not** replace Elixir/Phoenix, MapLibre, or Python/OSMnx.
- Do **not** prematurely adopt full event sourcing, a general entity-component framework, a generalized quest engine, a distributed cache, or a universal scripting API.
- Keep geometry provenance and authored identities stable across source updates.
- Keep decisions and approvals distinguishable from implementations and tests.
- Preserve the designer's uncommitted boundary, generated symlink, geographic snapshots, and authored work. Do not assume GitHub reflects the local working tree.

## Bottom line

**The architecture is ready to support a serious vertical slice, and it now has one.** Its strongest long-term idea is that the *actual* geography, the *playable* world, and the *player's understanding* of that world are different things. The next design decisions should be driven by a human investigation of The Quiet Hour, not by the attractiveness of new infrastructure.

See [current-design.md](current-design.md), [gameplay-interactions.md](gameplay-interactions.md), [near-term-features.md](near-term-features.md), [world-revisions-proposal.md](world-revisions-proposal.md), and [handoff.md](handoff.md) for detailed current contracts and unresolved decisions.
