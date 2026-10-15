> **Status: Current.** Approved private staging direction. Later #29 selects fixture-only staging; no provisioning/deployment authorization.

# Threshold — Private OVHcloud Staging Architecture

**Status:** Approved direction, 2026-10-12. No provisioning or deployment authorized by this document.

## Objective

Host a **private, browser-accessible staging environment** for the designer and a small number of invited editors, independently of the existing OVHcloud 32 GB dedicated server (currently impaired). Staging is **not** a public production launch. The dedicated server may someday host production but is not a staging dependency.

## Hosting choice

A small **OVHcloud VPS** (evaluate an approximately 2-vCore, 4-GB-RAM plan at order time), running a supported Debian or Ubuntu release. Use a multi-stage **Phoenix OTP release Dockerfile**, **Docker Compose** for `web`, `postgres`, and `caddy`, **GHCR** for immutable images, and **GitHub Actions** for CI and manually authorized staging deploys. The runtime must not require a source checkout. PostgreSQL binds only to the private Compose network and uses a persistent volume. Configure health checks and reverse-proxy WebSocket support.

Prefer **manual VPS provisioning initially**, with reproducible bootstrap scripts/cloud-init where actually supported. OpenTofu and the official OVHcloud provider are future options once additional machines justify state management; they are not required for the first server. No custom VM image, Kubernetes, BEAM cluster, Kamal or Redis.

Provisioning, bootstrap, application image building, deploy, migration, and backup/restore are **independent operations**. Separate OVH API credentials from GHCR/deploy permissions and application secrets. Do not let an ordinary image deployment provision servers.

Use HTTPS. An additional private access layer (e.g. Tailscale/VPN or authenticated reverse-proxy gate) is recommended until staff authentication is fully verified. Protect Studio at the HTTP, LiveView, event, and domain-operation levels.

## Identity

**Guest-first gameplay:** starting a walk must not require registration. The server creates an opaque guest identity backed by an appropriately protected cookie, while progress, discoveries, interactions and later achievements remain server-side in PostgreSQL. Explain that losing guest browser identity may lose access to the save.

Verified users log in with **emailed one-time numeric codes or magic links** (both methods supported), with short-lived, single-use credentials, rate limiting, failed-attempt caps, resend cooldown, secure session rotation, no enumeration and no sensitive logging. A magic-link GET must not consume credentials automatically when email scanners prefetch URLs. Returning account holders resume progress on another device.

**Roles:** ordinary player, editor, owner; guest is authentication state. **No moderator role or tooling for now.** Editors submit and edit authorized drafts; owners control staff invitations and permissions. Public signup never grants authoring privileges. Email-only privileged login is an approved initial convenience with recognized risk; require recent reauthentication for sensitive actions and revisit MFA before a public launch.

Guest-to-account claiming must preserve saved-progress primary keys and discovery/completion relationships. Do not overwrite or merge existing account progress silently; obtain a separately approved collision policy. Current development progress and database are protected.

## Deployment

1. PR validation: Elixir and frontend tests, world schema/reference checks, deterministic geography/material checks, container smoke test.
2. Merge: publish a SHA-tagged container to GHCR and record digest.
3. **Manual staging release:** select immutable digest, serialize deploy, verify recent backup, run migration exactly once, update Compose, check application and LiveView readiness, record deployed SHA.
4. Document application-image rollback versus database-migration rollback; backward-compatible migrations preferred.

Do not automatically redeploy on every commit initially. Production is a later environment with separate data, credentials and authorization.

## World content

Distinguish **local designer world**, **approved staging release world**, and **mutable Studio drafts**. Published world data is a Git-reviewed coherent snapshot packaged with/referenced by the release; mutable drafts must never overwrite immutable runtime files. Geography generation should happen locally or in CI, not routinely on the tiny VPS.

The designer's local uncommitted diamond boundary, `generated` symlink and generations are **not disposable**. A first container smoke test may use a clearly labeled fixture world. Publishing Madison requires explicit approval of a coherent committed source/generation set—never silently substitute an old boundary.

## Backups

Staging needs independent, tested recovery before ongoing collaboration: PostgreSQL-aware dumps initially (WAL/PITR later if recovery-point goals require), encryption with a tool such as Restic, an independent off-VPS/object-storage copy, and a second encrypted copy pulled by the designer's eventual backup destination. The existing OVH dedicated server is **not** a machine located at home. At least one copy should be outside OVHcloud to avoid provider/account concentration.

Back up unpublished drafts, identities, progress, audit state and uploaded assets as well as the database. Source-controlled releases alone are insufficient. Document key custody, retention, monitoring/alerts, and run a restore test into disposable PostgreSQL. A backup command exiting zero does not demonstrate recoverability. OVH snapshots are supplemental.

## First deliverable, not deployment

Inspect current Phoenix release/Compose/Actions/DB/session implementation. Build a production-style image and run it locally with disposable PostgreSQL and a scratch world; capture an architecture audit, required secret names, deploy/rollback and restore checklists, screenshots or smoke logs. No VPS order, push, or deploy without a new instruction.
