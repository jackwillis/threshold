# Working from the backlog (for Codex, Claude Code and other agents)

Work lives in [GitHub Issues](https://github.com/jackwillis/threshold/issues) and the [Threshold Backlog board](https://github.com/users/jackwillis/projects/3) (columns: Backlog, Ready, In Progress, Review, Done). Priorities are in [backlog.md](backlog.md). `gh` is the interface; it must be authenticated (`gh auth status`).

## 1. Load the project (every session)

1. Read `AGENTS.md`, then `docs/handoff.md` ("Resume here"), then this file.
2. `git status`, `git worktree list`, `git log --oneline -10`. The designer's uncommitted world files (`boundary.geojson`, the `generated` symlink, untracked `generations/`) are expected and protected; never stage, reset, clean or stash them.
3. See what is in flight: `gh issue list --label ready`, `gh pr list`, and the board's In Progress and Review columns. Another agent or the designer may already hold a ticket.

## 2. Pick a task

Ask the designer which ticket, or if they say "pick one", choose by these rules, in order:

1. The issue is in the **Ready** column / has label `ready`, and is not `blocked` or `needs-decision`.
2. Every issue in its **Dependencies** section is closed or merged. If one is open, take that one instead.
3. Highest RICE score in [backlog.md](backlog.md); `priority:high` breaks ties; prefer the infrastructure track and the player-experience track alternately only if the designer is waiting on both.
4. It is not assigned to someone else and has no open PR.

`ready` means defined and unblocked, **not authorized**. Do not begin implementation until the designer says go for that ticket (or for that milestone). Planning, reading and opening discussion comments are always fine.

Never silently decide an irreversible semantic. If a ticket needs a choice that a **decision issue** (`needs-decision`) covers, stop, comment, and ask; do not guess.

## 3. Claim it

- Assign yourself or comment "Starting #N" with your agent name; move the card to **In Progress**.
- Work in a branch named `issue-N-short-slug`, made from current `origin/main`, preferably in its own `git worktree` so the designer's tree is untouched.

```sh
git fetch origin
git worktree add ../threshold-issue-N -b issue-N-slug origin/main
```

## 4. Do the work

- Stay inside the ticket's **Scope**; the **Out of scope** list is binding. If you find adjacent work, open a new issue instead of expanding the change.
- Follow the ticket's **Safety** section and `AGENTS.md`: disposable PostgreSQL only (port 5433 test container), scratch worlds (`test/fixtures/worlds/tiny` or `THRESHOLD_WORLDS_DIR`), no migrations on the development database (list new migrations in `docs/local-gameplay.md`), no gameplay systems without approval, no `acquire-world` without approval.
- Add tests with the change; verify UI work in a real browser at desktop and narrow widths and say what you did not test.
- Small, reviewable commits. No commit, push, PR, deploy or provisioning unless the designer asked for it in this conversation. Do not enable automation that does so.

## 5. Definition of done

- Every acceptance criterion in the ticket is met and you can say how you checked each one.
- `make check` passes (state the result honestly; if something failed or was skipped, say so).
- Docs touched by the change are updated (`docs/handoff.md` "Resume here" for notable state; `docs/implementation-status.md` for guarantees).
- The PR (when asked for) uses the template, says `Closes #N`, lists dependencies, and reports verification and gaps.
- Move the card to **Review**; the designer moves it to **Done** on merge.

## 6. When something is wrong with the ticket

- Ambiguous, wrong, or blocked by something not listed: comment on the issue with the specific question, add `blocked` or `needs-decision`, move the card to Backlog, and report to the designer. Do not rewrite acceptance criteria to match what you built.
- A new decision is needed: open an issue from the **Decision** template, link it from the blocked ticket.
- A bug found on the way: open a `type:bug` issue; fix it only if it blocks the ticket.

## 7. Labels

`type:*` (feature, bug, research, infrastructure, documentation), `area:*` (atlas, studio, story, accounts, deployment, assets, publishing), and coordination labels `ready`, `blocked`, `needs-decision`, `priority:high`. Milestones M0 to M8 are the large deliverables.

## 8. Rules that do not change

Everything under "Standing instructions" in `AGENTS.md` applies: protected data, no push or deploy unprompted, no new gameplay systems, no environmental notes or spawn change, no cost-incurring cloud action without explicit approval.
