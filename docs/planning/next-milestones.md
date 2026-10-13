# Threshold — Consolidated Next Milestones

**Status:** Roadmap proposal informed by approved product/architecture decisions; only the first bounded implementation increment below is authorized by this planning handoff.

## Approved decisions

- Field Atlas map-first redesign and contextual focus area.
- Minimal declarative cases and Field Journal direction; exact schema/ending semantics still require review.
- LiveView first for the Story editor; Preact map editor migration deferred.
- Private staging on an **independent small OVHcloud VPS**, not the existing 32 GB OVH dedicated server.
- Docker Compose / Phoenix OTP release / Caddy / PostgreSQL / GHCR / GitHub Actions.
- Passwordless **email code and magic link**, plus guest-first gameplay using server-side progress.
- Editor and owner staff capabilities only; moderator system deferred.
- PostgreSQL isolated drafts; Git-reviewed proposals; periodic manually selected releases.
- Draft binaries may live in S3-compatible storage; approved binaries may be promoted into **Git LFS in PRs**.
- Off-server encrypted backups, preferably including an independent provider and periodic restore drills.
- No public production environment yet.

## M0 — Local staging foundation (first scoped assignment)

Audit the present release, Docker, GitHub Actions, player-key/progress tables, world snapshot loading, authoring saves, and frontend asset assumptions. Implement and test **only** a local production-style release image and Compose stack using a disposable database and scratch/fixture world, plus operational secrets checklist and recovery/deploy outline. **No accounts, live VPS, GitHub App, or new gameplay system in M0.** Run `make check` and container smoke tests. Update handoff/status. Keep changes reviewable and do not push or deploy without authorization.

## M1 — Identity and authorization (separate approval)

Guest cookies backed by server-owned progress; additive ownership mapping; email OTP + link single-use challenges; account claiming with explicit collision behavior; editor/owner-only policies; invited staff. No moderators. Rate-limit, ownership isolation, LiveView-event guards, and magic-link scanner tests.

## M2 — Hosted private staging and backup verification (separate approval)

Provision small OVH VPS manually initially; bootstrap Docker and private access (Tailscale or equivalent); CI/GHCR manual deploy, Caddy HTTPS and transactional email; recoverable encrypted PostgreSQL/object/draft backups and restore test. Do not deploy the designer's uncommitted world accidentally. Provision/secret spending needs explicit owner approval.

## M3 — Field Atlas UX and story read models (may run parallel)

Simplify the player layout without changing game rules. Then finalize the cases/stages/end-condition contract using The Quiet Hour epilogue; implement Current Investigation, Field Journal and full-screen intro. Add map note/investigation indicators. Test no spoiler leakage and mobile/accessibility behavior.

## M4 — LiveView Story editor and safe drafts

Structured scene/choice/case authoring; conflict-safe interactions saving; cross-file reference guards; server-side validation; draft storage tied to current published revision; isolated playtest state. Demonstrate the two-scene authoring workflow without raw JSON.

## M5 — Asset Library and collaborative publishing

Image uploads, private S3-compatible draft storage, asset metadata/previews; later GLB validation/preview. Add isolated S3-to-LFS promotion, content-only Git branches, GitHub App PR creation, review/status display. Manual export/PR is acceptable first. Test conflicting editors, asset manifests, rejected proposals and release reproducibility.

## M6 — Periodic releases and future production

Manually select reviewed revision, validate and deploy release artifacts with referenced immutable assets. Production hosting choice, public registration, staff MFA, advanced inventory, extensive moderation, and live collaborative editing all require later decisions.

## Cross-cutting release gates

Preserve `priv/worlds/madison/authored.json`, the uncommitted diamond boundary, `generated` symlink and snapshots, development DB and saves, active worktrees. Never reset or clean the designer's workspace. Tests use disposable Postgres and scratch world copies. Validate JSON and geographic references; retain schema compatibility, no-spoiler projections, author permissions, health checks and restore capability.

The existing `docs/world-revisions-proposal.md` is **not approved for implementation** merely by this roadmap. No feature should treat an architecture memo as an instruction to modify protected local authored data.
