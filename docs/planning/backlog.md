# Backlog priorities (updated October 13, 2026)

Work is tracked in [GitHub Issues](https://github.com/jackwillis/threshold/issues) and the [Threshold Backlog board](https://github.com/users/jackwillis/projects/3); the board and the issue milestones are the source of truth for what exists, its status and its milestone (see the numbering note in [next-milestones.md](next-milestones.md)). This file only holds the ordering below. Every issue has context, scope, acceptance criteria, out of scope, dependencies, verification, safety and references. Labels: `type:*`, `area:*`, `ready`, `blocked`, `needs-decision`, `priority:high`.

`ready` means defined and unblocked, **not** authorized: the designer still says go. Implementation never touches the protected local data listed in `AGENTS.md`.

## Lightweight RICE

Score = Reach x Impact x Confidence / Effort. These are quick judgments to order the queue, not measurements; revisit when facts change.

- **Reach** 1 to 3: 1 touches one area, 2 several, 3 unblocks or affects most later work or most players.
- **Impact** 1 to 3: 1 nice to have, 2 clearly valuable, 3 essential to a milestone goal.
- **Confidence** 0.5, 0.8 or 1: how sure we are the scope and approach are right (0.5 means an open design question).
- **Effort** in rough working sessions (0.5, 1, 2, 3).

| Order | Issue | R | I | C | E | Score |
|---|---|---|---|---|---|---|
| 1 | #8 Guest identity | 3 | 3 | 0.8 | 2 | 3.6 |
| 1 | #9 Users and challenges | 3 | 3 | 0.8 | 2 | 3.6 |
| 3 | #7 CI container smoke | 2 | 2 | 0.8 | 1 | 3.2 |
| 4 | #5 Compose smoke | 3 | 3 | 0.8 | 3 | 2.4 |
| 4 | #10 Email code | 3 | 3 | 0.8 | 3 | 2.4 |
| 6 | #22 Case projection | 3 | 3 | 0.5 | 2 | 2.25 |
| 7 | #19 Focus area | 3 | 2 | 0.6 | 2 | 1.8 |
| 8 | #21 Markers, #11 Magic link, #14 Roles, #15 Bootstrap, #16 Deploy workflow, #17 Backups | 2 | 2 to 3 | 0.8 | 2 to 3 | 1.6 |
| 9 | #12 Account ownership, #23 Journal panel, #24 Introduction | 3 | 2 to 3 | 0.5 | 2 to 3 | 1.5 |
| 10 | #20 Responsive controls | 3 | 2 | 0.6 | 3 | 1.2 |
| 11 | #13 Guest claim | 2 | 2 | 0.5 | 2 | 1.0 |

Tickets created after this scoring (#39, #41, #43 to #50, #56, #58, #62, #69 to #71) are not scored; score them when they become candidates. Decision issues are not scored; do each just before the issue it blocks. Finished tickets are removed from this table.

Two parallel tracks: infrastructure (#5, #7, then #17) and player experience (#19 and #21; #22 now that #27 is decided).
