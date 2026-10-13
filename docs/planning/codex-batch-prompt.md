# Codex batch prompt (time-boxed, parallel)

Paste into Codex to work several independent `ready` tickets at once. Edit the ticket list and time box each time; the designer's "go" is the list.

```
You have authorization to work tickets #34, #2, #3, #25 and #18 in
jackwillis/threshold, for about one hour. Read AGENTS.md and
docs/planning/agent-workflow.md first and follow them for each ticket.

- Spawn one subagent per ticket. Each uses its own git worktree off origin/main,
  its own branch issue-N-slug, and its own scratch PostgreSQL database
  (create threshold_test_N on the test container at port 5433, drop it when done)
  so parallel `make check` runs do not interfere.
- You may push issue branches and open PRs for these five tickets only. Never
  push main, merge, deploy, or touch priv/worlds/madison working-tree files.
- If a ticket is blocked, ambiguous or needs a decision, comment on the issue,
  add `blocked` or `needs-decision`, and move on.
- Do not start #4, #5, #6, #7, #35 or #36 yet; they wait on these merging.
- Stop at about one hour or when all five PRs are open. Then report, per
  ticket: PR number, acceptance criteria checked and how, what was not tested.

Discovered work: when you find adjacent work, follow-ups, bugs or missing
tickets, open a new GitHub issue for each (task template, a clear title,
acceptance criteria, `needs-triage` label, link to the ticket you found it in).
Do not start those issues. Duplicates are fine; Claude will prune them later.
You may open an extra PR only if it is needed to finish one of the five
authorized tickets (for example, splitting a large ticket into two PRs). Anything
outside the five tickets becomes an issue, not a PR. Never open a PR for a
gameplay system, environmental notes, the default spawn, world data,
migrations on the development database, or anything marked blocked or
needs-decision.
```

## Choosing a batch

- Only `ready` tickets whose dependencies are closed and whose files do not overlap.
- Tickets that depend on unmerged work wait for the merge; do not stack PRs.
- Review each PR with Claude Code (verdict comment), then prune `needs-triage` issues: `gh issue list --label needs-triage`.
