> **Status: Current — October 15, 2026.** Current resume page; historical reports are archived below.

# Handoff memo

## Resume here

Start with `AGENTS.md`, this page, [implementation status](implementation-status.md), the [documentation index](README.md) and the [agent workflow](planning/agent-workflow.md). Take only tickets explicitly authorized by the designer; the [backlog board](https://github.com/users/jackwillis/projects/3) owns work status and priority. The [dated handoff](history/handoff-through-2026-10-12.md) preserves previous sessions, not current instructions about what is built or uncommitted.

## State on main

- The local geographic editor, authored one-hop `/play` graph, PostgreSQL progress, declarative interactions and accessible investigation scenes are implemented. Classic Atlas has seasonal presentation and procedural watercolor materials. Madison's `interactions.json` contains *The Quiet Hour*; it is not an empty demonstration world.
- Madison's boundary, `generated` symlink and generation snapshots are tracked (`git ls-files priv/worlds/madison`). Their tracked status does not authorize agent edits. Inspect `git status` and `git worktree list` afresh; never reuse an old handoff's workspace inventory.
- Phoenix OTP release/environment configuration, health checks and production Docker image support landed (#2, #3 and #4). Local production-style Compose verification (#5) and fresh quick-start/browser verification (#58) remain separate work. An image implementation does not prove a Compose stack or hosted deployment works.
- GitHub CI runs `make check`; #34 is closed and the main run for `a8a9772` passed ([run](https://github.com/jackwillis/threshold/actions/runs/38357984109)). Use the latest [CI results](https://github.com/jackwillis/threshold/actions/workflows/ci.yml) and `make check` output for counts and current verification.

## Gate and verification

The full `make check` gate passed for this documentation update on October 15, 2026, using the isolated database `threshold_test_81` on port 5433. See `make check` for test counts: compile with warnings as errors, formatting, Elixir/database tests, ruff, TypeScript, Bun/material checks, Python tests, world validation and byte-identical rebuild. World validation reads the pinned geography; the rebuild writes a disposable copy. No development-database migration or live deployment is verified by that result. Historical browser checks and remaining accessibility/device gaps are listed in [implementation status](implementation-status.md); no new browser check is required by these documentation-only changes.

## Decisions and pending work

Approved direction is consolidated in [UX/story architecture](architecture/ux-v2.md), [staging architecture](architecture/staging.md), [authoring/publishing](architecture/authoring-and-publishing.md) and [milestones](planning/next-milestones.md). Direction is not blanket implementation authorization.

- Closed #29 selects **fixture-only staging for now**; hosting Madison later needs a new decision naming the main SHA. Closed #51 defines referenced-place deletion/re-id rejection; display-name/notes edits save freely, with saved-walk compatibility belonging to #31.
- Closed #80 retains generated play for local development; hosted gating is follow-up #82. Closed #30 selects per-document JSON snapshots with document-level optimistic concurrency. PR #83 records these decisions and is still unmerged at this update; do not assume its documentation is on main or that hosted gating/drafts exist.
- Closed #86 selects *The Red-Headed League*, with *The Call of Cthulhu* in reserve. *The Quiet Hour* remains test content until replaced. PR #89 records that decision and is still unmerged; #87 researches a site, while #88 requires the site and separate approval to edit world data. No story authoring is authorized by this handoff.
- Open #27 owns the case schema/completion decision; open #31 owns [session compatibility](world-revisions-proposal.md). Neither is approved by a roadmap. Current saves still use a whole-file world revision.
- Field Journal, new-walk introduction, map content indicators, Story editor and geographically anchored trees remain scoped follow-ups. Field Atlas focus-area and mobile-sheet changes are in open PRs #90 and #91, rather than implemented main behavior at this update. Recheck open PRs before starting overlapping work.

## Standing instructions

**Standing instructions from the designer (October 10, 2026):** no new gameplay systems without explicit approval; do not add environmental notes or change the default spawn (the designer is playing the mystery first); do not touch the development database, `authored.json`, the playable boundary, the `generated` symlink or the generation snapshots; do not push to `main`, merge or deploy (an agent may push an `issue-N-*` branch and open a PR only after the designer says go on that ticket).

**Gameplay decisions to preserve (the designer, October 10).**
- The designer will **play The Quiet Hour before any pacing change.** Do **not** add the three proposed Nearby notes (`loc:00ad92846572`, `loc:61d357749e47`, `loc:377bd2f999a8`) and do **not** change the default spawn yet.
- Quiet walking between encounters is not necessarily a problem. The pacing report in [madison-mystery-proposal.md](madison-mystery-proposal.md) is an observation (about 12 of 21 hops pass in silence, in the last two legs), not a defect list.
- If environmental notes are added later, they describe **persistent features** (a warm grating, a chalked number), never conditional story events. Anything conditional would be an interaction and must be discussed first.
- **Field Notes** (a read-only archive of recorded discoveries, built from existing persistent data) is the promising next feature; no generalized journal or inventory before it is needed.
- A future investigation should involve **more active player deduction**, not only unlocking interactions through discoveries (design open; it implies something beyond `requires: discovered(id)`).
- **No new gameplay systems are authorized right now.** Do not start any without the designer.

Tests and experiments use scratch worlds (`THRESHOLD_WORLDS_DIR`) and disposable PostgreSQL on port 5433. Parallel tickets use `threshold_test_<N>` and drop it afterward. Run `make check` before committing. Never stage, reset, clean or stash the designer's protected files; never migrate or write the development database. Agents must not acquire OSM data without explicit approval. Read [local gameplay](local-gameplay.md) for migrations the designer applies themselves.
