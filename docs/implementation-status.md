# Implementation status

Last updated: October 10, 2026. This file separates what exists and has been verified from what is active, planned or deferred. The operational task list is [implementation-plan.md](implementation-plan.md).

## Completed and verified

Verified means exercised by an automated test and/or by driving the app in headless Firefox during development. `make check` (Elixir tests, Python tests, ruff, TypeScript type check, world validation, determinism) passed when this was last updated.

- **Geographic pipeline** (`gis/`, Python/OSMnx): acquire (the only networked step), build and validate. A pinned Overpass snapshot of the Madison rectangle plus a 250 m buffer is committed, with checksum and manifest. Generated nodes, edges, context and provenance are deterministic and covered by a byte-identical rebuild check. Edge IDs are topological (`edge:<from>-<to>-<lowest way id>`) with a separate geometry hash. Closed `area=yes` ways are context (pedestrian areas), not edges; cycleways are in the graph; elevators are kept as `vertical` context.
- **Read-only viewer** (Phoenix LiveView + a TypeScript MapLibre hook): layers, access/type/component colouring, legend with counts, components list, inspector, staleness banner. No basemap.
- **Authored layer:** strict schema and validation, deterministic conflict-checked atomic save, reference status (ok / moved / missing) for node, edge and closure references.
- **Editing tools:** inspect, place (snaps to node, edge with offset, or free point), move, connect, close street, boundary editing (Terra Draw), Save and Discard with an unsaved-changes indicator and leave-page guard. Saving a boundary makes the geography stale and is refused if boundary plus buffer exceeds the pinned snapshot.

- **Playable-location layer (candidate):** `threshold-gis playable` builds a derived network (graph-radius clustering, 25 m) beside the imported files with connectivity-integrity diagnostics and designer retain/suppress overrides; the editor displays it, flags staleness, and saves overrides with the authored layer. Verified by Python and Elixir tests and in headless Firefox. Playable connections now contain continuous source-network routes, ordered edge/node lists and actual route geometry; route integrity was audited on Madison and tested on synthetic data. See [playable-route-review.md](playable-route-review.md) for results and gameplay limits. Playability remains untested.

- **Walking access** (`0547583`): optional `access` on authored places, independent of the display marker; routing, validation, reference status, inspector and Route-check actions. LiveView-tested; the map does not yet draw the access point or a connector (Studio V2 backlog) and it was not browser-verified.
- **Runtime-world cache** (`e68269c`): `Threshold.WorldCache` keeps the four most recent compiled movement worlds keyed by generation, authored hash, boundary hash and graph mode; warm loads 148-210 ms to 0.3 ms. Tested including with PostgreSQL.
- **Classic Atlas** (`6e5f75e`, `d04e223`): season tokens, a shared MapLibre layer stack, bundled EB Garamond drawn locally by MapLibre 5.24 (no glyph PBFs), `/atlas` prototype and the `/play` map; season is display-only. Browser-verified in headless Firefox; see [classic-atlas-typography.md](classic-atlas-typography.md) for rendering limitations. The editor keeps its diagnostic style.
- **Interactions, first slice** (`5eafbca` to `6f9304a`): `interactions.json` with strict validation and lint (`mix threshold.interactions`), discoveries and completed interactions in two PostgreSQL tables, transactional `Sessions.complete_interaction/5`, and an accessible, field-notebook investigate panel on `/play` (live region, focus management, reduced motion). Verified by tests (including concurrency on independent connections) and in headless Firefox at desktop and 420-500 px on scratch worlds. See [gameplay-interactions.md](gameplay-interactions.md).

- **The Quiet Hour** (first Madison mystery): `priv/worlds/madison/interactions.json`, four approved places, seven interactions, two branches and two endings. Content tests over every choice order; scratch-world playtest of both branches and both endings in headless Firefox. Pacing of the last two legs is long (see [madison-mystery-proposal.md](madison-mystery-proposal.md)); not human-playtested.

## Verification status (October 10, 2026)

`make check` passes with 303 Elixir tests when `THRESHOLD_TEST_DATABASE_URL` points at the disposable test database (13 database tests are excluded without it), 35 Bun tests and 38 Python tests. Not verified: real screen readers, touch devices, browsers other than Firefox, the CI workflow on GitHub, Compose container startup, and the interactions migration against the designer's development database (not applied by agents). The designer's real `authored.json`, playable boundary, active generated snapshot and snapshots have never been modified by agent work.

## Near-term features recorded (not built, not yet authorized)

Full-screen introduction on a new walk, the Field Journal (cases, recorded discoveries, completed outcomes, with a proposed smallest `cases` data model), and map indicators for notes and investigations: [near-term-features.md](near-term-features.md). Also deferred: geographically anchored trees (see the handoff), Studio V2 interaction editing, portraits and dialogue. Standing decisions from the designer (play the mystery first; no Nearby notes or spawn change yet; environmental notes only for persistent features; no new gameplay systems) are in the handoff's "Resume here" section.

## Proposals awaiting approval

- [Session compatibility instead of whole-file revisions](world-revisions-proposal.md): an explicit position check (exists, traversable, inside the boundary), a diagnostic revision stamp, and non-destructive recovery. Not implemented.

## Known limitations and untested areas

- Regeneration and reference repair are implemented. Regeneration stages an offline build, playable build and validation before publishing generated files; saved-input changes reject publication. The editor preserves authored working data and save-conflict hashes. Missing/moved references open the inspector for deliberate reconnection, detachment or removal. Browser checks on a scratch Madison world exercised boundary drag/save/regenerate, map refresh, location-to-edge reconnection and missing-closure reconnection/save. Automated tests cover missing/moved references, unsaved guards and failed-build preservation. An end-to-end synthetic source update moved node 2 and removed way 105; in-editor regeneration flagged the location as moved and the closure as missing, and authored.json remained byte-identical. Browser console inspection during hot reload reported one MutationObserver error; the exercised editing, saving and regeneration actions still completed.
- Network review done (see [network-review.md](network-review.md)): undirected edges are correct for walking; open items are retaining sidewalk/crossing tags, an optional derived access basis, and plaza/entrance handling in the playable-node layer.
- The full designer workflow was driven in headless Firefox against a scratch copy of the world, not against a long editing session on the committed Madison files; no browser tests are automated (the LiveView tests do not exercise Terra Draw).
- Map labels are not drawn (they would need a font source); names appear in the inspector.
- Shapely emits a deprecation warning from the importer.
- A GitHub Actions workflow (`.github/workflows/ci.yml`) runs `make check` with a PostgreSQL service and fails if database tests would be skipped. It has not yet run on GitHub, so its action versions and `.tool-versions` handling are unverified. No deployment target is configured.

## Reliability guarantees (Reliability Pass 1, 2026-10-09)

What the code now guarantees, each with the test or check that backs it:

- **Authored and boundary saves cannot silently overwrite each other.** The content-hash check, write and rename run under one per-world lock (`Threshold.WorldFile`) with unique temp files; of N saves from one base revision exactly one wins and the rest get `:conflict` (tests with 8 concurrent writers; the same test failed with 3-5 winners before the fix).
- **Generated geography is published as one coherent snapshot.** Five files are copied into `generations/<digest>/` and the `generated` symlink is repointed by one atomic rename; readers resolve it once and read every file from that snapshot, and browsers pin layer requests with `?generation=`. A failed publication leaves the previous snapshot active (tests: publication failure, concurrent readers during 40 publications, plain-directory conversion, pruning). Regeneration re-checks inputs and publishes under the same lock as saves, so an input cannot change between the check and publication.
- **Player movement is transactional.** Row lock plus expected-turn check: 16 competing moves from one turn (same or different destinations) advance the save once; replays and failed moves leave it unchanged; concurrent initialisation creates one row; resets racing moves leave a coherent save; a revision mismatch blocks moves (tests use independent connections, not the shared sandbox).
- **Edge anchors are derived from imported geometry.** The client supplies an edge and an offset; the position comes from the edge, and offsets outside 0..1 are rejected.
- **The game-world revision describes the bytes actually used,** all read once from one snapshot.
- **Committed Madison geography satisfies the movement invariants** (`madison_geography_test.exs`): 1,080 of 1,631 playable connections are valid walks and the other 551 are excluded only by the boundary; none fails structurally; every valid connection starts and ends on its locations and is reversible; excluded connections are never offered.

Not verified or not done: the CI workflow has never run on GitHub; the editor's recovery-draft idea (4.6) is deferred; `mix release` copies `generated` as a real directory (it dereferences the symlink, so a release works but holds the files twice and the first in-release publication converts it); `make build-world` still writes into the active snapshot in place and non-atomically; a held advisory lock covers one running node only; browser behaviour on touch devices, reduced motion and multiple tabs is untested.

## Active

Gameplay content: *The Quiet Hour* is implemented ([madison-mystery-proposal.md](madison-mystery-proposal.md)); next are pacing notes for its long legs (the designer's decision), then Studio V2 interaction editing, portraits and simple dialogue.

## Planned

1. Apply the agreed fixes from the network review (retain sidewalk/crossing tags; decide on a derived access basis).
2. Playable-node approach: an experiment compared candidate networks ([playable-node-experiment.md](playable-node-experiment.md)); graph-radius clustering preserved connectivity, proximity merging did not. Productized as a derived layer; alleys are protected and plaza gaps are not bridged as provisional choices (undecided by the designer). Imported routing topology and playable locations stay distinct.
3. PostGIS: not used yet; PostgreSQL and Ecto now hold player progress and interactions. World files remain the reproducible source artifacts.
4. Done: strict one-hop movement on the authored graph (see Completed).

## Deferred

Radio, encounters beyond the first interaction slice, null zones, Backrooms, achievements, cartography/knowledge UI, journal, chained scenes, portraits and dialogue, Studio V2 interaction editing, a dark "field-map" style, multiplayer, hosted deployment, CI provider selection.

## Environment

Elixir 1.19 / OTP 26, Python 3.12 and Bun (see `.tool-versions` and the README). Bun is installed at `~/.bun/bin` and added to PATH by the Makefile.
