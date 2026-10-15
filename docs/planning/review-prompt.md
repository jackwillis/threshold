> **Status: Current.** Reusable independent PR review prompt; substitute the intended PR numbers.

# Reviewer prompt

Paste into Claude Code (or any reviewer with `gh` and repo access). Replace `PR_NUMBERS`. For a batch run, list every PR from the Codex report.

```
Review pull request(s) PR_NUMBERS in jackwillis/threshold as the independent
reviewer. Read AGENTS.md and the "Reviewing" section of
docs/planning/agent-workflow.md first. You are read-only: do not push, edit
the branch, merge, or change labels other than `blocked`/`needs-decision`.

For each PR:
1. `gh pr view N --json title,body,files,closingIssuesReferences` and
   `gh pr diff N`. Read the linked issue and its acceptance criteria. Judge the
   diff, not the PR description. Read surrounding code where the diff touches it.
2. Check out the branch in a throwaway worktree (not the main working tree) and
   run `make check` against a scratch database. Report the real result.
3. Check, and cite file and line for each finding:
   - every acceptance criterion is met, and a test would fail if it were not;
   - correctness, concurrency, persistence; migrations are additive and not
     applied to the development database;
   - security and authorization (sessions, input, secrets, logging);
   - UI: keyboard, focus, live announcements, narrow widths, reduced motion;
     say "unverified" if no browser check was possible;
   - protected data untouched: priv/worlds/madison/authored.json,
     boundary.geojson, the `generated` symlink, generations, development DB;
   - scope: nothing outside the issue's Scope; no new gameplay system; no
     needless abstraction; Out of scope respected;
   - PR hygiene: "Closes #N", honest verification notes.
4. Post ONE comment on the PR. Comments post from the designer's GitHub
   account, so the first line is `Reviewer: Claude Code` (or the reviewer's
   name), and the second line is exactly one of:
   **Approve** (ready for the designer),
   **Request changes** (numbered findings, most severe first, each with file:line
   and the concrete fix wanted), or
   **Escalate** (the product or architecture question; link or open a decision issue).
   Separate must-fix findings from optional suggestions. Include the `make check` result.

Finish with a table: PR, verdict, must-fix count, anything the designer must decide.
Do not approve work you could not verify; say what you could not check.
```

## After the review

- Codex addresses "Request changes", pushes, and the reviewer re-checks only what changed.
- The designer merges. No one else merges.
- Prune agent-opened issues: `gh issue list --label needs-triage`.
