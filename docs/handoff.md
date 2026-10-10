# Handoff memo

Date: October 8, 2026. From: Claude Code (implementation so far). To: Codex.
Repository: `git@github.com:jackwillis/threshold.git`. Read `AGENTS.md` (commands and conventions) first, then this file, then `docs/implementation-plan.md` (the operational task list).

## Update, October 9, 2026 (Claude Code): read this first

Newer than the tables below. The steering memos are in `docs/` (`steering-memo-2026-10-09.md`, `frontend-v2-memo-2026-10-09.md`, `keyboard-navigation.md`, `camera-rules.md`, `cartography-brief.md`, `cartographic-labels-memo.md`); `implementation-status.md` lists what is guaranteed and what is unverified.

- **Reliability (done):** per-world write lock (`world_file.ex`), atomic generated-geography snapshots (`generated.ex`), server-derived edge anchors, concurrency tests, CI workflow (never yet run on GitHub).
- **Player map (`/play`):** strict one-hop movement; radial numbered keyboard shortcuts (`Game.numbered_moves/2`, `assets/src/map/shortcuts.ts`); camera limits (`assets/src/map/camera.ts`; zoom 17-19.5, 200 m tether). `make check` also runs `bun test`.
- **Authored map as the playable graph (the default for `/play`; `?graph=generated` plays the generated graph, `config :threshold, :play_graph` changes the default):** the designer's authored places are traversable nodes (intersections or mid-block); `RouteResolver` resolves each authored connection to a real street walk and `EffectiveGraph` turns them into a `Game.World`. Progress is saved separately per graph. See `docs/movement-design.md` and `docs/authored-integration-audit.md`.
- **Import area vs playable boundary:** `config.json` `import_bounds` (west, south, east, north) sets the area that is imported and drawn in the editor, currently about 5.7 x 3.5 km, the whole isthmus from the campus to the east side (14,731 nodes, 20,657 edges, 25 MB pinned snapshot, acquired 2026-10-10 with the designer's approval via `acquire --replace`; Overpass can answer 504 on a big area, retrying worked). The playable boundary (`boundary.geojson`, edited in the editor with the Boundary tool, Save, then Regenerate) can be any polygon inside it; play is limited to it by the server. Without `import_bounds` the extent is the boundary plus `buffer_m`. The layer endpoint takes `?bbox=west,south,east,north` and the player map requests only the playable boundary plus a margin, so a large import area does not slow `/play`.
- **Read-only tools:** `mix threshold.audit`, `mix threshold.routes [--details]`, and the editor's "Route check" section. They change nothing.
- **Classic Atlas (done for `/play`):** the player map uses the shared season tokens and layer stack in `assets/src/map/atlas/` (see `docs/classic-atlas-typography.md`); a season switcher is display-only. `/atlas` is a prototype page. MapLibre draws text locally from bundled EB Garamond, no glyph PBFs. The editor keeps its diagnostic style.
- **Walking access and world cache (done):** optional `access` on authored locations, and `Threshold.WorldCache` (see `docs/expanded-world-verification.md` sections 3 and 5 for the reasoning; measurements are in the cache commit).
- **Interactions (first slice done):** `interactions.json` per world (absent = none), `Threshold.Interactions`, two session tables, `Sessions.complete_interaction/5`, and a LiveView investigate panel in `/play`. Design, API, tests and what is unverified: `docs/gameplay-interactions.md`. Madison has no `interactions.json`. Run `mix ecto.migrate` on your development database: until then "New walk" (which clears the new tables) and any world that has an `interactions.json` will fail; a world without one (Madison) otherwise keeps working.
- **Open designer decisions:** the two free-point places (`loc:6216b9ecc50a`, `loc:9821f05090ce`) have no street position, which leaves 10 connections unresolved; whether to add `travel` on connections and to allow spawns on authored places (both schema changes needing approval); how the authored area meets generated scaffolding beyond it; destination versus route-departure bearing for key numbering.
- **Not built:** Frontend V2 (Studio/Atlas), curved cartographic labels (note: MapLibre text labels need a glyph source the offline style lacks), editor recovery drafts, the offscreen-destination indicator.
- The committed `authored.json` is the designer's real work: never run tests against it; experiment on a copy via `THRESHOLD_WORLDS_DIR`.

## What this project is

Threshold is a single-player, location-based mystery/exploration game inspired by Madison, WI. The current milestone is a **local geographic world-authoring editor**, not gameplay. A designer opens a real Madison map, authors fictional locations, connections and street restrictions on top of it, edits the playable boundary, and saves reviewable files. See `docs/game-design.md` (vision) and `docs/architecture.md` (long-term architecture); where they disagree with the plan, `implementation-plan.md` and `project-decisions.md` win for the current milestone.

## State of the code (all committed except where noted)

| Area | Where | What it does |
|---|---|---|
| GIS pipeline | `gis/src/threshold_gis/world.py` | Python/OSMnx CLI `threshold-gis`: `acquire` (only networked step), `build`, `validate`, `playable`. Deterministic output. |
| Playable layer | `gis/src/threshold_gis/playable.py` | Derived candidate "playable locations" (graph-radius clustering, 25 m) with connectivity-integrity checks and designer overrides. |
| World loading | `lib/threshold/world.ex`, `geography.ex`, `playable.ex` | Reads world files, staleness checks, a cached ID index of nodes/edges. |
| Authored layer | `lib/threshold/authored.ex`, `authored/edit.ex`, `references.ex`, `boundary.ex` | Strict schema and validation, pure edit operations, reference status (ok/moved/missing), boundary validation, conflict-checked atomic saves (check, write and rename run under a per-world lock in `world_file.ex`; the same lock covers the importer's final input check and publication). |
| Editor UI | `lib/threshold_web/live/editor_live.ex`, `editor_components.ex` | LiveView owning the working copy; toolbar, inspector, save/discard. |
| Map | `assets/src/hooks/map_editor.ts`, `assets/src/map/*.ts` | TypeScript MapLibre hook; Terra Draw for placing, moving and boundary editing; snapping. Built with Bun. |
| Data | `priv/worlds/madison/` | Pinned OSM snapshot, generated geography (`generated` -> `generations/<id>/`), `boundary.geojson`, `authored.json`. |

Verified: `make check` passed at the last commit (107 Elixir tests, 27 Python tests, ruff, TypeScript type check, world validation, byte-identical rebuild including `playable.json`). The map UI was driven in headless Firefox during development; **there are no automated browser tests**, and the LiveView tests do not exercise Terra Draw or MapLibre.

## Data model in one page

Three layers, never mixed in a file: (1) pinned source snapshot (`source/snapshot.osm`, checksum in `source/manifest.json`), (2) generated geography (`nodes/edges/context.geojson`, `provenance.json`, `playable.json`), kept as immutable snapshots in `generations/<id>/` with a `generated` symlink to the active one (see below), (3) authored world (`authored.json`, plus the importer inputs `boundary.geojson` and `config.json`). The editor writes only `authored.json` and `boundary.geojson`. **Never edit generated files by hand; regenerate in the editor (atomic) or with `make build-world`.**

Generated geography is published atomically: `Threshold.Generated.publish/2` copies the five files into `generations/<content-digest>/`, then repoints the `generated` symlink with one rename (the three newest snapshots are kept). Readers call `Threshold.Generated.active/1` once and read everything from that directory, so they never see a mix of builds, and a failed publication leaves the old snapshot active. Browsers pin their layer requests with `?generation=<id>`. The CLI (`make build-world`) writes into whatever `generated` points at, in place and non-atomically; use the editor's Regenerate while the app is serving the world. A plain `generated/` directory (test fixtures) is also readable and is converted on first publication.

- Edge IDs: `edge:<from>-<to>-<lowest OSM way id>` (suffix `-1`, `-2` only for distinct parallel geometries). Shape edits keep the ID; a separate `geometry_hash` property detects "moved". Node IDs: `node:<OSM id>`. Playable locations: `pn:<OSM node id>`; connections `pc:<a>-<b>`.
- Authored schema: see `docs/design.md`. Locations anchor to a node, an edge with an offset, or a free point. Closures are layered on imported access (whole edge, `kind: restricted`) and never overwrite it. `playable_overrides` (retain/suppress) apply on the next `playable` build.
- References never rewrite silently: missing/moved targets are flagged for review.
- Imported graph is undirected (correct for walking; see `docs/network-review.md`). `access_status` is unchanged OSM-derived; `access_basis` explains it (explicit / default_allowed / uncertain).

## Decisions already made (do not reopen without the designer)

Recorded in `docs/implementation-plan.md` (numbered). In short: LiveView plus one JS hook (no React/SPA); Terra Draw; Bun/TypeScript tooling (no Node); no basemap (own geometry only, offline); commit snapshot and generated files as-is (no LFS, no gzip); keep the sidewalk-level imported graph; closures annotate rather than override; files remain the source artifacts and **PostgreSQL/PostGIS arrives later with the first persistent gameplay** (see `project-decisions.md`), not as a migration of world files.

## Working agreements with the designer

- The designer (Jack) does not know Elixir. Explain choices in plain language; recommend rather than survey.
- Small, reviewable commits, made when asked. Do not push, deploy, or contact external services without asking; `make acquire-world` is the only networked step.
- Gate commits on `make check` actually passing (one commit here slipped through with a failing test; do not repeat that).
- Report what was verified and what was not. Do not claim browser behaviour you did not exercise.

## IMPORTANT: uncommitted designer data

`priv/worlds/madison/authored.json` contains the designer's real in-progress authoring (dozens of locations and connections created in the editor). **Do not reset, overwrite, reformat or regenerate it, and never run tests or scripts against it.** Tests use `test/fixtures/worlds/tiny`; for experiments set `THRESHOLD_WORLDS_DIR` to a scratch copy. The editor's own conflict check protects it from concurrent writes.

## Gotchas learned the hard way

- Endpoint: the LiveView socket in `lib/threshold_web/endpoint.ex` was commented out by the generator; tests cannot catch a missing socket (they do not use WebSockets). Check in a browser.
- Terra Draw: a polygon mode must be registered for polygon features to be accepted; points must be selected before they can be dragged; features need `properties.mode`; it rejects invalid features silently (the hook logs them). Verify with `window.thresholdMap` / `window.thresholdDraw` (exposed for tests).
- Elixir: `handle_event/3` clauses must be grouped; the formatter is not idempotent on very long multi-line guards (rewrite the guard); LiveView DOM ids with `:` are invalid CSS selectors (the editor strips them).
- The map canvas is `phx-update="ignore"`; server state reaches it through `data-state` and the hook's `updated()`. Bump `rev` (see `bump_rev`) to force Terra Draw to resync after rejected edits.
- OSMnx simplification merges edges unless an attribute is listed in `SIMPLIFY_DIFFER`; add attributes there when new distinctions matter. Output determinism depends on library versions (recorded in `provenance.json`).
- Overpass rejects the default `python-requests` user agent (406); the importer sends its own and the public endpoint can 504 transiently.
- Selenium for browser checks is not in the repo. Headless Firefox works (`--no-remote --profile <scratch>` if the user's Firefox is already running); a scratch virtualenv with `selenium` was used.

## Known limitations and open items

1. **Phase 6 completed:** staged offline regeneration (`build`/`playable`/`validate`) and deliberate location/closure reconnect actions are wired to the editor. Boundary regeneration and a simulated moved/deleted source update were exercised in scratch worlds. See `implementation-status.md`.
2. Provisional playable-layer choices awaiting the designer: alley protection (on), plaza gaps (not bridged), radius 25 m, whether suppression may remove junctions. See `docs/playable-node-experiment.md`.
3. The 96% `unknown` access problem is explained (`access_basis`) but not otherwise acted on.
4. No map labels (need a font source, which conflicts with offline); names show in the inspector.
5. Importer: Shapely `transform` deprecation warning; `world.py` is large and could be split; `gis/analysis/` holds exploratory scripts, not tested code.
6. Not started: CI provider/deploy target, dark "field-map" style, PostgreSQL/PostGIS, any game engine code, radio, encounters, null zones, Backrooms, achievements.

## Suggested first steps

1. Run `make setup && make check` and confirm green on your machine (needs Elixir 1.19/OTP 26, Python 3.12, and Bun; see README).
2. Read `docs/implementation-plan.md` (decisions and phases) and `docs/implementation-status.md` (verified vs not).
3. Review `docs/playable-route-review.md`: candidate connections now retain complete ordered walking routes and actual geometry. The 993 locations and 1,631 connections remain; corrected median length is 58.0 m. Retain overrides protect exact nodes during clustering. Before persistent movement, settle traversal policy for access values, authored closures and routes leaving the playable boundary.

## First playable exploration update — October 9, 2026

The project now also has a first playable exploration prototype at `/play`, with pure movement in `lib/threshold/game.ex` and `lib/threshold/game/`, PostgreSQL progress through `Threshold.Repo`, a dedicated `PlayLive`, and `assets/src/hooks/player_map.ts`. The editor remains at `/`. World files remain source artifacts; there is no PostGIS schema or database migration of geography yet.

Authored spawns and optional location `movement_location` attachments are now supported. The designer approved allowing public/unknown/mixed/conditional routes provisionally, while blocking explicit restrictions, authored closures and any route leaving the boundary. Every constituent edge is checked, with no alternative rerouting. Saves check world revision and expected turn under a PostgreSQL row lock. Nearby inspection is free. An explicit new walk resets progress when a world revision changes.

See `docs/local-gameplay.md` for Compose, test and production-mode commands, and `docs/movement-design.md` for verification. The full gate passed with PostgreSQL enabled: 131 Elixir tests, 32 Python tests and deterministic rebuild. A scratch Madison browser session verified marker movement, backtracking, free inspection and save restoration after restarting Phoenix. Docker itself was unavailable; Compose YAML parses but container startup remains unverified. Reduced motion is implemented but not browser-verified. The designer's real `authored.json` was left untouched and remains uncommitted.
