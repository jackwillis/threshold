# Handoff memo for Codex

Date: October 8, 2026. From: Claude Code (implementation so far). To: Codex.
Repository: `git@github.com:jackwillis/threshold.git`. Read `AGENTS.md` (commands and conventions) first, then this file, then `docs/implementation-plan.md` (the operational task list).

## What this project is

Threshold is a single-player, location-based mystery/exploration game inspired by Madison, WI. The current milestone is a **local geographic world-authoring editor**, not gameplay. A designer opens a real Madison map, authors fictional locations, connections and street restrictions on top of it, edits the playable boundary, and saves reviewable files. See `docs/game-design.md` (vision) and `docs/architecture.md` (long-term architecture); where they disagree with the plan, `implementation-plan.md` and `project-decisions.md` win for the current milestone.

## State of the code (all committed except where noted)

| Area | Where | What it does |
|---|---|---|
| GIS pipeline | `gis/src/threshold_gis/world.py` | Python/OSMnx CLI `threshold-gis`: `acquire` (only networked step), `build`, `validate`, `playable`. Deterministic output. |
| Playable layer | `gis/src/threshold_gis/playable.py` | Derived candidate "playable locations" (graph-radius clustering, 25 m) with connectivity-integrity checks and designer overrides. |
| World loading | `lib/threshold/world.ex`, `geography.ex`, `playable.ex` | Reads world files, staleness checks, a cached ID index of nodes/edges. |
| Authored layer | `lib/threshold/authored.ex`, `authored/edit.ex`, `references.ex`, `boundary.ex` | Strict schema and validation, pure edit operations, reference status (ok/moved/missing), boundary validation, conflict-checked atomic saves. |
| Editor UI | `lib/threshold_web/live/editor_live.ex`, `editor_components.ex` | LiveView owning the working copy; toolbar, inspector, save/discard. |
| Map | `assets/src/hooks/map_editor.ts`, `assets/src/map/*.ts` | TypeScript MapLibre hook; Terra Draw for placing, moving and boundary editing; snapping. Built with Bun. |
| Data | `priv/worlds/madison/` | Pinned OSM snapshot, generated geography, `boundary.geojson`, `authored.json`, `playable.json`. |

Verified: `make check` passed at the last commit (107 Elixir tests, 27 Python tests, ruff, TypeScript type check, world validation, byte-identical rebuild including `playable.json`). The map UI was driven in headless Firefox during development; **there are no automated browser tests**, and the LiveView tests do not exercise Terra Draw or MapLibre.

## Data model in one page

Three layers, never mixed in a file: (1) pinned source snapshot (`source/snapshot.osm`, checksum in `source/manifest.json`), (2) generated geography (`nodes/edges/context.geojson`, `provenance.json`, `playable.json`), (3) authored world (`authored.json`, plus the importer inputs `boundary.geojson` and `config.json`). The editor writes only `authored.json` and `boundary.geojson`. **Never edit generated files by hand; regenerate with `make build-world`.**

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

1. **Phase 6 (next planned):** in-UI regeneration (shelling out to `build`/`playable` via `Threshold.Importer`, which exists and is tested but is not yet wired to a UI action) and a reference "reconnect" workflow beyond the existing Move tool.
2. Provisional playable-layer choices awaiting the designer: alley protection (on), plaza gaps (not bridged), radius 25 m, whether suppression may remove junctions. See `docs/playable-node-experiment.md`.
3. The 96% `unknown` access problem is explained (`access_basis`) but not otherwise acted on.
4. No map labels (need a font source, which conflicts with offline); names show in the inspector.
5. Importer: Shapely `transform` deprecation warning; `world.py` is large and could be split; `gis/analysis/` holds exploratory scripts, not tested code.
6. Not started: CI provider/deploy target, dark "field-map" style, PostgreSQL/PostGIS, any game engine code, radio, encounters, null zones, Backrooms, achievements.

## Suggested first steps

1. Run `make setup && make check` and confirm green on your machine (needs Elixir 1.19/OTP 26, Python 3.12, and Bun; see README).
2. Read `docs/implementation-plan.md` (decisions and phases) and `docs/implementation-status.md` (verified vs not).
3. Ask the designer what felt wrong when using the playable layer on the real map; that, plus the Phase 6 regeneration button, is the highest-value next work.
