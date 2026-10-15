> **Status: Current — October 15, 2026.** Implementation summary for main at `a8a9772`; open PRs are separate. Work status and priority live on the [backlog board](https://github.com/users/jackwillis/projects/3).

# Implementation status

Read the [handoff](handoff.md) for current decisions and standing safety instructions, [architecture](architecture/ux-v2.md) for approved direction, and the [agent workflow](planning/agent-workflow.md) before implementing a ticket. Older implementation plans and reports are indexed as historical in [docs/README.md](README.md).

## Implemented on main

- **Geography:** pinned source snapshot; offline, deterministic generated nodes/edges/context/playable routes; boundary validation; authored references and walking-access anchors; atomic publication of coherent generation snapshots. The imported graph, authored places and runtime movement graph remain distinct layers.
- **Editor:** inspect/place/move/connect/closures/boundary tools, conflict-checked atomic saves under a per-world write lock, explicit reference repair, offline regeneration and stale-input rejection. LiveView owns the working copy; MapLibre/Terra Draw handle browser gestures.
- **Player:** strict one-hop movement on the authored graph by default, radial numbered shortcuts, constrained camera, separate generated-graph development mode, runtime-world cache, PostgreSQL progress, revision and stale-turn guards, transactional movement and interaction completion.
- **Presentation:** Classic Atlas seasonal styling and local EB Garamond typography; integrated subtle procedural watercolor materials; accessible field-notebook investigation scenes with focus management, live announcements and reduced-motion support. Season changes are presentation-only.
- **Interactions/content:** validated per-world `interactions.json`, declared discoveries, discovery requirements, scenes/choices and durable completions. Madison contains *The Quiet Hour*. #86 selects *The Red-Headed League* for later authoring; existing content stays until separately approved replacement work. No inventory, timer, dialogue tree or new rules engine is implied.
- **Release foundation:** environment-driven OTP release and migration task (#2), `/healthz` and `/readyz` (#3), production Docker image support (#4), and the GitHub CI gate (#34). See [release](release.md), [health checks](health-checks.md) and [local gameplay](local-gameplay.md).

## Verification

The full `make check` gate passed for this documentation update on October 15, 2026 using isolated PostgreSQL `threshold_test_81` on port 5433. See `make check` for current test counts and exclusions; a full run must set `THRESHOLD_TEST_DATABASE_URL` so database tests run. It covers warnings-as-errors compilation, formatting, Elixir tests (including database concurrency), ruff, TypeScript, Bun/material checks, Python tests, world validation and a byte-identical offline rebuild into a disposable copy.

GitHub CI is exercised: #34 is closed; the main run for `a8a9772` [passed](https://github.com/jackwillis/threshold/actions/runs/38357984109). Consult the [latest workflow runs](https://github.com/jackwillis/threshold/actions/workflows/ci.yml) instead of assuming a dated local gate proves current CI.

Prior browser reports used scratch worlds and disposable PostgreSQL, including editor boundary/regeneration/reference repair and Quiet Hour branches/endings in headless Firefox. They are retained as [expanded-world verification](expanded-world-verification.md), [Quiet Hour report](madison-mystery-proposal.md), [Classic Atlas typography](classic-atlas-typography.md) and [watercolor report](watercolor-atlas.md). They are historical checks, not browser automation in `make check` or a new browser run for this documentation update.

## Gaps and pending verification

- Real screen readers, touch-device behavior and a broader browser matrix remain unverified by the historical reports. LiveView tests do not exercise Terra Draw or MapLibre. Walking-access marker/connector presentation is deferred.
- #5 owns the fresh local production-style Compose smoke test; #58 owns fresh quick-start/native-Compose/browser verification. A built production image and a successful source gate do not establish those outcomes. No hosted deployment or backup/restore operation is claimed here.
- Agents do not verify migrations against the designer's development database. [Local gameplay](local-gameplay.md) lists migrations for the designer to apply; current application state must be inspected rather than inferred from an old handoff.
- Saves still use whole-file `world_revision`; [session compatibility](world-revisions-proposal.md) is subject to #31. The case schema/completion contract is subject to #27.
- Generated play remains available locally (#80); hosted gating (#82) is follow-up work. JSON snapshot draft storage (#30) is a decision, not implemented shared drafts. Fixture-only staging (#29) does not authorize hosting Madison.
- PRs #83 and #89 record recent decisions; PRs #90 and #91 implement Field Atlas focus-area/mobile-sheet changes. All are unmerged at this update; consult their current state before relying on them.

## Planned and deferred

Field Journal, introduction, map content indicators, LiveView Story editor, safe collaborative drafts, geographically anchored trees, asset ingestion and publishing are scoped separately on the board. Radio, null zones, Backrooms, achievements, portraits/dialogue, general scripting and multiplayer remain future systems requiring explicit decisions and authorization. The older editor [implementation plan](implementation-plan.md) is historical, not a live task queue.

Madison's boundary, `generated` symlink and snapshots are tracked. The standing restrictions in `AGENTS.md` apply equally to tracked and untracked work: do not edit protected world data, saves or the development database, and never stage/reset/clean/stash the designer's files. Tests use fixtures or scratch worlds and disposable PostgreSQL.
