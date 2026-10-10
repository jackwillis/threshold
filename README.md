# Threshold

A Madison-based single-player mystery and exploration project. The first milestone is a local geographic editor built with Phoenix, browser-based mapping, and a Python GIS pipeline.

**Status (October 10, 2026): the world-authoring editor and a first playable slice work locally.** The editor (`/`) imports and shows the Madison study area and lets a designer place locations, connect them, restrict streets, give places a separate walking-access position, and edit the playable boundary. The player map (`/play`) walks the designer's authored graph one hop at a time in a Classic Atlas style (four seasons, display-only), with PostgreSQL-saved progress and a first interaction system: authored investigations at places, a field-notebook scene panel, declared discoveries, and completed interactions. There is no story content yet beyond a synthetic test world; Studio V2 (editing interactions) is planned. See [Implementation status](docs/implementation-status.md) for what is verified and what is not, and [docs/handoff.md](docs/handoff.md) for the current state and the one action the designer owes (applying a database migration).

## Project memos

- [Original design memo](docs/initial-design-memo.md): the user's initial proposal, preserved verbatim. Its viewer-only milestone is superseded by the editor decision below.
- [Project decisions](docs/project-decisions.md): agreed direction, geographic boundary, technology, data layers, Git workflow, and open questions.
- [Editor design](docs/design.md) and [implementation plan](docs/implementation-plan.md): draft, with open product decisions listed in the plan.
- [Handoff memo](docs/handoff.md): current state, decisions, gotchas and next steps for the next engineer or agent.
- [Network review](docs/network-review.md) and [playable-node experiment](docs/playable-node-experiment.md): findings on the real Madison data.
- [Implementation status](docs/implementation-status.md): what exists and is verified, active work, planned and deferred items.
- [Gameplay interactions](docs/gameplay-interactions.md), [session compatibility proposal](docs/world-revisions-proposal.md), [Classic Atlas typography](docs/classic-atlas-typography.md) and the [Frontend V2 proposal](docs/frontend-v2-proposal.md): the current gameplay and presentation direction.
- [Game design memo](docs/game-design.md) and [engineering/architecture memo](docs/architecture.md): long-term vision. Where they differ from the implementation plan, the plan is the operational task list.

## Layout

```text
lib/threshold/            World files, authored layer, movement, interactions, sessions
lib/threshold_web/        Phoenix web interface (editor, /play, /atlas prototype)
assets/                  TypeScript frontend (MapLibre, Terra Draw), built with Bun
priv/worlds/madison/      Boundary, import configuration, authored world
gis/                     Python importer package (threshold-gis), tests, pinned dependencies
docs/                    Project memos
```

Imported source geography, generated geographic graphs, and authored game metadata must remain separate. Editor saves should produce reviewable file changes; committing and deployment remain explicit actions.

## Development

Needs Elixir 1.19 / OTP 26, Python 3.12 and [Bun](https://bun.sh) (installed to `~/.bun/bin`; the Makefile adds it to PATH) (see `.tool-versions`; [mise](https://mise.jdx.dev) reads it).

```text
make setup           deps, .venv, gis package, Bun packages, build frontend
make assets          rebuild the TypeScript bundle (`make run` also watches in dev)
make run             start the Phoenix server (localhost:4000)
make test            Elixir and Python tests
make check           everything CI would run (precommit, ruff, Bun type check and tests, pytest, world validation, determinism)
make build-world     regenerate geography and the playable layer from the pinned snapshot (offline)
make build-playable  regenerate only the playable layer
make acquire-world   download a new OSM snapshot (the only networked step)
```

### PostgreSQL

Player progress, discoveries and completed interactions live in PostgreSQL; world files stay the source artifacts. See [docs/local-gameplay.md](docs/local-gameplay.md) for the Compose setup and for **applying new migrations to your development database** (agent sessions only use disposable databases). For the full gate including database tests:

```text
docker compose --profile test up -d --wait postgres-test
THRESHOLD_TEST_DATABASE_URL=postgres://threshold:threshold_local@localhost:5433/threshold_test make check
```

Without that variable the database tests are excluded, and `make check` still passes. No CI provider or deployment target has been selected (the CI workflow has never run on GitHub). PostGIS is not used yet.
