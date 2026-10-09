# Implementation status and next steps

Date: October 8, 2026 (America/Chicago)
Status: Paused at the user's request after repository initialization and documentation

## What exists

The workspace was initially empty. The following preliminary work happened before the request to pause:

- Generated a Phoenix 1.8.15 application named `threshold`, module `Threshold`, without Ecto, mailer, dashboard, or an asset build pipeline.
- Downloaded Elixir dependencies and created `mix.lock`.
- Created a local Python 3.12 virtual environment in `.venv` and installed OSMnx 2.1.0 and its dependencies.
- Recorded installed Python package versions in `scripts/gis/requirements.txt`.
- Created the initial Madison rectangle in `priv/worlds/madison/boundary.geojson`.
- Created a draft import configuration and empty authored world file.
- Wrote a preliminary independently executable GIS script with `acquire`, `build`, and `validate` commands.
- Initialized Git after the generator's first attempt encountered a read-only `.git` directory.
- Archived the user's original design memo and documented the subsequent discussion.

The user subsequently requested an initial repository commit. The project has no configured remote, CI pipeline, or deployment target.

## What does not exist yet

- No OSM snapshot has been acquired.
- No real Madison graph or map context has been generated.
- No MapLibre integration, custom editor page, save endpoints, or drawing tools have been implemented.
- No authored locations or routes exist.
- No application server is running.
- End-to-end GIS processing has not been verified. Before the initial commit, `mix precommit` passed: compilation with warnings treated as errors, formatting, and all five generated Phoenix tests. These tests cover the scaffold, not the future editor or GIS pipeline.
- No CI/CD configuration exists.

The default Phoenix landing page and generated tests are still present. The GIS script is a **draft**, not a validated implementation or evidence that the milestone is complete. Its help command was exercised, but source acquisition, filtering, geometry retention, deterministic builds, and boundary behavior still require tests and real data review.

The configured 250-meter buffer, access policy names, source layout, coordinate projection, and exact serialization are preliminary implementation choices. They do not replace the agreed requirements.

## Environment notes

Elixir 1.19.6 / Erlang OTP 26 are available. The shell's Python is 3.14; the project's `.venv` was created using an available Python 3.12 runtime for GIS package compatibility. Node is available through the bundled workspace runtime but not on the default shell PATH.

Hex and the Phoenix generator were installed in `/tmp/threshold-mix`, with Hex data in `/tmp/threshold-hex`. These are temporary setup locations, not durable project requirements. Future sessions may need to install standard Mix tooling or use their own local tooling paths.

Dependency downloads required network-enabled execution. Normal source regeneration should remain offline after a snapshot is pinned.

The generated `AGENTS.md` contains Phoenix coding conventions. It includes boilerplate assumptions, such as Req already being installed, that must be checked against `mix.exs` before relying on them.

## Proposed sequence on resume

1. Review the decision memo and agree the minimum editor interactions.
2. Verify the generated Phoenix baseline and replace the landing page with a map and inspector using a synthetic fixture.
3. Test the GIS script with a synthetic network, especially parallel edges, loops, access changes, disconnected components, and boundary crossings.
4. Acquire and pin real OSM source data covering the rectangle and buffer, including enough coverage for the intended boundary-editing workflow.
5. Generate and inspect streets, paths, alleys, nodes, access tags, components, and context.
6. Integrate the chosen geometry drawing library and implement validated file saves with visible unsaved changes.
7. Implement the agreed authored editing actions while keeping geographic data separate.
8. Add reference diagnostics, regeneration/error reporting, and meaningful validation tests.
9. Document reproducibility and wire CI to pinned inputs when the repository hosting choice is known.

Before treating the draft importer as production-ready, verify dependency compatibility, filter behavior, stable references, contextual feature extraction, and deterministic output. Ensure an edited boundary can never appear current against a stale graph without a visible regeneration requirement.
