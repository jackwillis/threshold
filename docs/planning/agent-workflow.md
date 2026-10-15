> **Status: Current.** Required ticket implementation/review workflow and authorization boundaries.

# Working from the backlog

Tasks are GitHub Issues on the [Threshold Backlog board](https://github.com/users/jackwillis/projects/3) (Backlog, Ready, In Progress, Review, Done). Priority and RICE scores are board fields (see [Priority and RICE](#priority-and-rice)). The loop is short:

**Ready ticket → Codex implements and opens a PR → Claude Code reviews → Codex fixes → the designer merges.**

## Who does what

- **Designer:** decides what to build, says "go" on a ticket, resolves decision issues, and is the only one who merges, deploys, provisions or spends.
- **Codex:** implements Ready tickets, writes the tests, opens the PR.
- **Claude Code:** independently reviews the PR diff; also checks the approach first on `risk:high` tickets.
- **Claude (design chat) and ChatGPT:** design input and continuity. Anything that matters goes on the issue, not only into chat.

## Start of a session

Read `AGENTS.md`, `docs/handoff.md` ("Resume here") and this file. Run `git status` and `git worktree list`. The designer's world files (`boundary.geojson`, the `generated` symlink, `generations/`) are tracked and protected: never stage, reset, clean or stash them. See what is in flight with `gh pr list` and the board.

## Picking a ticket (Codex)

Take the designer's named ticket, or choose one that: is labelled `ready` and not `blocked` or `needs-decision`; has all its listed dependencies closed; has no assignee or open PR; and is highest on the board by Priority, then Score (`gh project item-list 3 --owner jackwillis --format json`). `ready` is not authorization: wait for the designer's go on that ticket.

If the work depends on an unresolved choice, comment on the issue and stop. Never decide an irreversible semantic quietly.

## Implementing (Codex)

1. Assign yourself, move the card to In Progress.
2. Work on branch `issue-N-short-slug` from current `origin/main`, preferably in a separate worktree (`git worktree add ../threshold-issue-N -b issue-N-slug origin/main`).
3. Stay in the ticket's Scope; Out of scope is binding. Spot adjacent work? Open a new issue.
4. Follow the ticket's Safety section and `AGENTS.md` (disposable PostgreSQL, scratch worlds, no development-database migrations, no new gameplay systems).
   Concurrent worktrees each create their own scratch database on the test container (port 5433), named `threshold_test_<N>` (the runtime guard accepts `threshold_test`, `threshold_test_<suffix>` and names ending `_test`), and drop it when done.
5. Add tests; check UI changes in a real browser at desktop and narrow widths; run `make check`.
6. Push the issue branch and open a PR using the template, with `Closes #N`, each acceptance criterion with how it was verified, and any gaps stated honestly. Move the card to Review. Do not touch `main`, merge or deploy.

## Reviewing (Claude Code)

On a new PR, review the real diff and the code around it against the ticket, not the PR description:

- Each acceptance criterion is genuinely met, and tests actually prove it.
- Correctness, concurrency, persistence and migrations (additive, applied nowhere but the disposable database).
- Security and authorization where relevant; accessibility and responsive behaviour for UI.
- Protected data untouched; no scope creep or needless complexity.

Post one comment that starts with a verdict: **Approve** (ready for the designer), **Request changes** (concrete findings, file and line), or **Escalate** (needs a product or architecture decision, linked to a decision issue). Codex addresses findings, pushes, and Claude Code re-checks only what changed.

## `risk:high` tickets

Auth and sessions, database migrations, publishing, uploads and infrastructure carry the label `risk:high`. Before coding, Codex posts a short plan on the issue (approach, files, risks) and Claude Code replies "proceed" or with constraints. Everything else skips this step. It ends in one reply, not a loop.

## Bad or unclear tickets

Comment with the specific question, add `blocked` or `needs-decision`, and tell the designer. Do not rewrite acceptance criteria to match what was built. A needed decision becomes an issue from the Decision template.

## Board

Enable the built-in project workflows (project settings, Workflows): new issues to Backlog; closed issues and merged PRs to Done; a PR opened for an issue to Review. Ready and In Progress are moved by hand.

## Rules that do not change

All "Standing instructions" in `AGENTS.md` still apply. In particular: protected data stays untouched; agents may push **issue branches** and open PRs only after the designer says go on that ticket, and never push `main`, merge, deploy, provision or spend.

## Priority and RICE

The board has a `Priority` field (P0, P1, P2) and number fields `Reach`, `Impact`, `Confidence`, `Effort` and `Score`. Score = Reach x Impact x Confidence / Effort. These are quick judgments to order the queue, not measurements; revisit when facts change. P0 is a score of 3 or more, P1 is 1.5 to under 3, P2 is the rest (and unscored or decision tickets, which are scored when they become candidates).

- **Reach** 1 to 3: 1 touches one area, 2 several, 3 unblocks or affects most later work or most players.
- **Impact** 1 to 3: 1 nice to have, 2 clearly valuable, 3 essential to a milestone goal.
- **Confidence** 0.5, 0.8 or 1: how sure we are the scope and approach are right (0.5 means an open design question).
- **Effort** in rough working sessions (0.5, 1, 2, 3).

Decision issues are not scored; do each just before the issue it blocks.
