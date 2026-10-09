# Threshold

A Madison-based single-player mystery and exploration project. The first milestone is a local geographic editor built with Phoenix, browser-based mapping, and a Python GIS pipeline.

**Status: world-authoring editor working locally.** A pinned OpenStreetMap snapshot of the Madison study area is imported and viewable, and a designer can place locations, connect them, restrict streets and edit the playable boundary on the map, then save reviewable files. There is no gameplay yet. See [Implementation status](docs/implementation-status.md) for what is verified and what is not.

## Project memos

- [Original design memo](docs/initial-design-memo.md): the user's initial proposal, preserved verbatim. Its viewer-only milestone is superseded by the editor decision below.
- [Project decisions](docs/project-decisions.md): agreed direction, geographic boundary, technology, data layers, Git workflow, and open questions.
- [Editor design](docs/design.md) and [implementation plan](docs/implementation-plan.md): draft, with open product decisions listed in the plan.
- [Implementation status](docs/implementation-status.md): what exists and is verified, active work, planned and deferred items.
- [Game design memo](docs/game-design.md) and [engineering/architecture memo](docs/architecture.md): long-term vision. Where they differ from the implementation plan, the plan is the operational task list.

## Layout

```text
lib/threshold/            Phoenix application / future world-file handling
lib/threshold_web/        Phoenix web interface (EditorLive shell)
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
make check           everything CI would run (precommit, ruff, pytest, world validation, determinism)
make build-world     regenerate geography from the pinned snapshot (offline)
make acquire-world   download a new OSM snapshot (the only networked step)
```

 No CI provider or deployment target has been selected. PostgreSQL/PostGIS is the planned long-term store for player progress; it is introduced with the first persistent gameplay, not before (see project decisions).
