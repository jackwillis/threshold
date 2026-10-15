# Threshold — Collaborative Authoring, Assets, and Git Publishing

**Status:** Approved product direction, 2026-10-12; GitHub App and binary pipelines are **future milestones**, not immediate build authorization.

## The publishing contract

**Studio Save Draft → Submit GitHub PR → Review and Merge → Periodic Release.**

A few editors should author through hosted Studio in their browsers, without cloning the repo. GitHub handles review/version history and GitHub Actions deploys manually selected approved revisions. Merging a PR does **not** automatically make a draft visible to ordinary players or require immediate publication.

The designer and other invited editors may each have GitHub accounts, but Studio's ordinary identity remains Threshold's verified email login. A GitHub account is useful for code review, not required for editing or playing.

## Draft persistence and conflict safety

Use PostgreSQL for draft metadata and durable unpublished JSON revisions, with explicit owner, base published revision, saved revision, changed objects and validation state. Independently saved drafts are not shared mutable runtime files. Start with optimistic concurrency at document level; show conflict rather than silently overwriting a newer change. Object-level merges or collaborative cursors are optional later.

Current `Authored.save` and `WorldFile` protections and the interaction validator are the single authoritative implementation path. Before integrated authoring, ensure edits to `authored.json` and `interactions.json` remain cross-file consistent. Deleting a place cannot silently orphan its scenes; scene effects must refer to declared discoveries. No separate JavaScript interpretation of rule validity.

**Decision (#30, 2026-10-14):** drafts are full JSON snapshots with document-level optimistic concurrency. The unit of concurrency is one world file (for example `authored.json` or `interactions.json`); a draft records the base revision (content hash) it was taken from, and saving against a changed file is rejected so the editor must rebase or discard. Snapshots use the deterministic serialization of `Authored` (sorted keys, collections ordered by id), so a PR diff is the file's own diff. Structured change lists are not adopted; the unit can narrow to a scene or interaction later without changing stored drafts.

Studio should eventually include Map, Story, **Assets**, Playtest, and secondary World Data. Draft playtesting uses real gameplay logic with isolated save/identity and cannot affect normal progress, canonical world, or another editor's work.

## Asset pipeline

**OVHcloud S3-compatible Object Storage is recommended, not mandatory for the first container milestone.** Never rely on a replaceable VPS disk as the only copy of uploaded art. Do not run an S3 server on the tiny VPS.

Upload source images, textures, audio and later GLB models to private draft object storage. Store owner, MIME, byte size, SHA-256, asset ID, version ID, location, verification state and attribution/rights metadata in PostgreSQL. Prefer presigned upload for large files. Enforce size/type quotas; verify file contents, not extension; scan/sanitize risky formats; process previews in restricted, resource-bounded workers. Do not serve unpublished assets as public URLs.

A stable logical asset ID is useful in Studio; **published world content must pin an immutable version/content digest**. Never depend on a mutable 'latest' object for released story content.

### Approved hybrid: S3 drafts → Git LFS at PR submission

When an editor submits approved binaries, a publishing worker:

1. Validates and freezes the exact referenced draft asset versions and hashes.
2. Downloads/streams them from S3 into an **isolated temporary Git workspace**, never the live Phoenix checkout.
3. Promotes only explicitly selected assets to Git LFS (e.g. accepted GLB, images or source art as policy determines), with reviewed `.gitattributes`.
4. Creates a content-only branch and commits story/world JSON, asset references and LFS pointers.
5. Pushes LFS objects and Git branch, then opens a PR with a human-readable content/asset summary and previews.
6. Retains private draft binaries until publication/retention policy permits cleanup.

Git LFS consumes separate storage/bandwidth and rejected PRs may still incur object storage. Limit submission sizes. Source `.blend` files need not automatically enter LFS if only approved `.glb` exports are released. CI must fetch LFS binaries explicitly and verify their hashes, referenced IDs and rights metadata before building releases.

Use a narrowly scoped GitHub App eventually: contents/PR permissions limited to this repository, path validation limited to world and asset-manifest paths, no workflow edits or CI/deployment secrets. A repository GitHub App's API permissions alone do not enforce *file-path* restrictions—Studio's server and branch protection must do that. PR submission must never modify arbitrary application code or `.github/workflows`.

## Release pipeline

The authoritative published snapshot is a reviewed Git commit and matching pinned LFS assets. GitHub Actions validates schema, cross-file references, source/generation consistency, media digests and sizes. An operator selects a merged revision for a **manual periodic release**, builds/uses an immutable image or content bundle, and deploys it to staging. Production is deferred.

Do not require full GitHub integration to support first editor collaboration. Start with conflict-safe drafts and manual export/PR; automate proposal creation only after the safe basic workflow works.

## Backup and recovery

Database backups cover draft and asset metadata; object-storage backups cover draft binaries. Both are needed for coherent restore. Preserve published Git/LFS artifacts and release manifests; keep releases addressable by digest and retain LFS objects while used by maintained releases. Test restoring metadata together with referenced media.

## Target acceptance

Two editors can independently save, playtest and propose scene and asset changes without clobbering each other; a reviewer can see exactly what changed; only reviewed content enters a release. Ordinary players never see unpublished narrative or art.
