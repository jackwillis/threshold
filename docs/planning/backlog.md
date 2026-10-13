# Backlog index and priorities (October 12, 2026)

Work is tracked in [GitHub Issues](https://github.com/jackwillis/threshold/issues), grouped by milestone (see the numbering note in [next-milestones.md](next-milestones.md)). Every issue has context, scope, acceptance criteria, out of scope, dependencies, verification, safety and references. Labels: `type:*`, `area:*`, `ready`, `blocked`, `needs-decision`, `priority:high`.

`ready` means defined and unblocked, **not** authorized: the designer still says go. Implementation never touches the protected local data listed in `AGENTS.md`.

## Milestones and issues

| Milestone | Issues |
|---|---|
| M0 Staging Foundation | #34 get CI passing (done), #2 release config (done), #3 health endpoints (done), #4 Docker image, #5 local Compose smoke, #6 operations docs (done), #7 CI container smoke, #35 CI badges, #36 README rewrite (done), #39 test database naming guard, #56 Decimal advisory, #58 verify README quick start on native Docker |
| M1 Accounts and Authorization | #8 guest identity, #9 users and challenges, #10 email code, #11 magic link, #12 account-owned saves, #13 guest claim, #14 editor/owner policy; decision #26 |
| M2 Private OVHcloud Staging | #15 bootstrap runbook, #16 GHCR and manual deploy, #17 backups and restore drill, #46 staging authorization audit; decisions #28, #29 |
| M3 Field Atlas V2 | #18 simplify panel (done), #19 focus area, #20 responsive and movement controls, #21 markers, #41 Vollkorn map typography |
| M4 Cases, Journal, Introduction | #22 case projection, #23 Current Investigation and Journal, #24 introduction; decision #27 |
| M5 Studio Story Editor | #25 cross-file consistency guard (waits on decision #51), #43 Story editor, #47 Map-to-Story links, #50 activity and validation panel |
| M6 Collaborative Authoring | #44 playtest sessions, #45 persistent drafts; decisions #30 draft storage, #31 session compatibility |
| M7 Asset Library | #48 Asset Library MVP; decision #33 |
| M8 Publishing and Releases | #49 content-only GitHub PR submission; decision #32 |

M5 to M8 implementation issues (#43 to #50) are written but stay `blocked` until their decision issues are resolved. Unmilestoned: #60 landing page at `/` (needs a decision on moving the editor to `/editor`). Decision #51 (referenced-place rename semantics) blocks #25.

## Lightweight RICE

Score = Reach x Impact x Confidence / Effort. These are quick judgments to order the queue, not measurements; revisit when facts change.

- **Reach** 1 to 3: 1 touches one area, 2 several, 3 unblocks or affects most later work or most players.
- **Impact** 1 to 3: 1 nice to have, 2 clearly valuable, 3 essential to a milestone goal.
- **Confidence** 0.5, 0.8 or 1: how sure we are the scope and approach are right (0.5 means an open design question).
- **Effort** in rough working sessions (0.5, 1, 2, 3).

| Order | Issue | R | I | C | E | Score |
|---|---|---|---|---|---|---|
| 1 | #34 Get CI passing | 3 | 3 | 1 | 1 | 9.0 |
| 2 | #3 Health endpoints | 3 | 2 | 1 | 1 | 6.0 |
| 3 | #6 Operations docs | 2 | 2 | 1 | 1 | 4.0 |
| 3 | #35 CI badges | 2 | 1 | 1 | 0.5 | 4.0 |
| 5 | #2 Release config | 3 | 3 | 0.8 | 2 | 3.6 |
| 5 | #4 Docker image | 3 | 3 | 0.8 | 2 | 3.6 |
| 5 | #8 Guest identity | 3 | 3 | 0.8 | 2 | 3.6 |
| 5 | #9 Users and challenges | 3 | 3 | 0.8 | 2 | 3.6 |
| 9 | #7 CI container smoke | 2 | 2 | 0.8 | 1 | 3.2 |
| 10 | #5 Compose smoke | 3 | 3 | 0.8 | 3 | 2.4 |
| 10 | #10 Email code | 3 | 3 | 0.8 | 3 | 2.4 |
| 10 | #18 Simplify Atlas panel | 3 | 3 | 0.8 | 3 | 2.4 |
| 13 | #22 Case projection | 3 | 3 | 0.5 | 2 | 2.25 |
| 14 | #36 README rewrite | 2 | 1 | 1 | 1 | 2.0 |
| 15 | #19 Focus area | 3 | 2 | 0.6 | 2 | 1.8 |
| 16 | #21 Markers, #25 Cross-file guard, #11 Magic link, #14 Roles, #15 Bootstrap, #16 Deploy workflow, #17 Backups | 2 | 2 to 3 | 0.8 | 2 to 3 | 1.6 |
| 17 | #12 Account ownership, #23 Journal panel, #24 Introduction | 3 | 2 to 3 | 0.5 | 2 to 3 | 1.5 |
| 20 | #20 Responsive controls | 3 | 2 | 0.6 | 3 | 1.2 |
| 21 | #13 Guest claim | 2 | 2 | 0.5 | 2 | 1.0 |

Decision issues (#26 to #33) are not scored; do each just before the issue it blocks. #27 (case semantics) is the one that gates the player-experience track, so decide it while the M0 and M3 work is under way.

Two parallel tracks: infrastructure (#34, #3, #2, #4, #5, #7) and player experience (#18, then #19 and #21; #27 then #22).
