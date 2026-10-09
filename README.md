# Threshold

A Madison-based single-player mystery and exploration project. The first milestone is a local geographic editor built with Phoenix, browser-based mapping, and a Python GIS pipeline.

**Status: initialized and paused.** Phoenix scaffolding and an unverified importer draft exist; the map/editor is not implemented and no geographic source snapshot has been acquired.

## Project memos

- [Original design memo](docs/initial-design-memo.md): the user's initial proposal, preserved verbatim. Its viewer-only milestone is superseded by the editor decision below.
- [Project decisions](docs/project-decisions.md): agreed direction, geographic boundary, technology, data layers, Git workflow, and open questions.
- [Editor design](docs/design.md) and [implementation plan](docs/implementation-plan.md): draft, with open product decisions listed in the plan.
- [Implementation status](docs/implementation-status.md): existing scaffolding, limitations, environment notes, and proposed next steps.

## Draft layout

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

Development and GIS instructions will be finalized when implementation resumes. No database, remote repository, CI provider, or deployment target has been selected.
