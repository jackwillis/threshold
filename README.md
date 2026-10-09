# Threshold

A Madison-based single-player mystery and exploration project. The first milestone is a local geographic editor built with Phoenix, browser-based mapping, and a Python GIS pipeline.

**Status: initialized and paused.** Phoenix scaffolding and an unverified importer draft exist; the map/editor is not implemented and no geographic source snapshot has been acquired.

## Project memos

- [Original design memo](docs/initial-design-memo.md): the user's initial proposal, preserved verbatim. Its viewer-only milestone is superseded by the editor decision below.
- [Project decisions](docs/project-decisions.md): agreed direction, geographic boundary, technology, data layers, Git workflow, and open questions.
- [Implementation status](docs/implementation-status.md): existing scaffolding, limitations, environment notes, and proposed next steps.

## Draft layout

```text
lib/threshold/            Phoenix application / future world-file handling
lib/threshold_web/        Phoenix web interface (currently generated defaults)
priv/worlds/madison/      Boundary, import configuration, authored world
scripts/gis/             Unverified Python importer draft and pinned dependencies
docs/                    Project memos
```

Imported source geography, generated geographic graphs, and authored game metadata must remain separate. Editor saves should produce reviewable file changes; committing and deployment remain explicit actions.

Development and GIS instructions will be finalized when implementation resumes and the baseline is verified. No database, remote repository, CI provider, or deployment target has been selected.
