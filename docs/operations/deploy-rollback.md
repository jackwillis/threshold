# Manual staging deploy and rollback checklist

This operator checklist describes the approved private staging direction. Docker/GHCR/Compose, proxy/access controls and deploy automation are future tickets; no scripts or live deployment are supplied here. The designer alone authorizes deployment. The current standalone release contract is in [release.md](../release.md); credential custody is in [secrets.md](secrets.md).

## Before selecting a release

- Obtain the designer's approval for the staging target and exact reviewed revision. Serialize deployment and migration so two operators/jobs cannot race.
- Record previous and candidate Git SHA, immutable image digest (once images exist), build platform, migration versions, and coherent published world/asset manifest. Retain the previous artifact and its world dependencies. Never substitute the local uncommitted Madison boundary or snapshots.
- Confirm all release checks passed. Rehearse candidate startup/migrations using a scratch world and disposable PostgreSQL on port 5433. Require an explicit compatibility review for saved world revisions and schema changes.
- Confirm a recent encrypted backup of the database and any mutable drafts/assets, an independent off-VPS copy, accessible recovery keys, and a completed restore drill. Agree the allowable data-loss window and downtime with the designer; do not invent targets.
- Review each pending migration's effects, reversibility and compatibility with both images. Plan a recovery route before destructive changes. Record whether a reverse migration would delete data.
- Verify application settings by name against the inventory, database role privileges, private network/access restrictions, TLS/proxy configuration and WebSocket forwarding once implemented. Provisioning credentials must be absent from ordinary deploy jobs.

## Deploy (only after separate authorization)

1. Put the approved service into the agreed maintenance/quiescence state if migrations or content compatibility require it. Preserve existing database/asset storage; never replace volumes as an image update.
2. Fetch and verify the selected immutable artifact and matching world/asset manifest; use its exact digest, not a mutable tag. Load application credentials privately and record names only.
3. Run pending migrations exactly once with the candidate release: `bin/threshold eval "Threshold.Release.migrate()"`. The database must already exist. The command is idempotent but still needs operator serialization; do not start HTTP with a partially migrated schema.
4. Start the selected release with `PHX_SERVER=true` and the approved bind/proxy configuration. Replace only the application service in the future Compose setup, retaining persistent storage.
5. Check `/healthz` returns HTTP 200 for liveness and `/readyz` returns HTTP 200 for database/schema/world readiness. A 503 is a failed rollout; record the sanitized reason and stop promotion. Liveness alone cannot establish readiness.
6. Check `/`, `/editor` and `/play`, a real browser LiveView connection and reconnect, approved one-hop movement and persisted progress with a dedicated smoke identity, and editor access restrictions. Do not use the designer's save or publish world edits during smoke checks.
7. Record deployed SHA/digest, world manifest, applied migration versions, time, operator, backup reference and verification results. Resume service and watch errors/readiness. Keep the previous artifact for rollback.

## Rollback matrix

| Situation | Application action | Database/content action |
| --- | --- | --- |
| Failed candidate, no migration applied and unchanged compatible world | Stop candidate; start previous immutable artifact | Keep existing database; select matching retained world manifest; verify readiness and saves |
| Additive migration explicitly verified compatible with previous image | Start previous image after compatibility confirmation | Keep the migrated schema; **image rollback does not imply migration rollback** |
| Backward-incompatible schema or incompatible world revision | Keep service quiescent; do not blindly start previous image | Designer chooses a forward fix or coherent backup restore into a separate target; review loss of writes after backup and saved-world compatibility |
| Explicitly approved reverse migration | Use an image that can operate on resulting schema | Run only a reviewed reverse operation after backup/drill; structural reversibility is not data recovery |
| Data corruption or uncertain schema state | Stop writes and retain evidence privately | Follow [restore.md](restore.md), restore/verify separately, then authorize cutover; never overwrite the only surviving database |

## Shipped migration reversibility

As of this document, both migrations implement Ecto `change/0`, whose table/index/constraint creation can be structurally reversed:

| Version / migration | Effect of reversal | Operational recommendation |
| --- | --- | --- |
| `20261009000000` / `CreatePlayerProgress` | Drops `player_progress`, its unique index and turn constraint; loses saved location/turn/visited progress. Dependent interaction tables prevent treating it as an isolated downgrade | Do not reverse as routine image rollback; preserve schema and progress |
| `20261010000000` / `CreateInteractionProgress` | Drops `player_discoveries` and `completed_interactions` and their indexes; loses discoveries, choices and completion history | Keep additive tables for a compatible previous image; restore is required to recover dropped rows |

`Threshold.Release` currently exposes `migrate/0`, not a rollback function. This checklist does not supply an ad hoc rollback command. Future migrations must document whether they are reversible, whether reversal destroys data, and which image versions tolerate the resulting schema. Never run migrations against the designer's development database during agent verification.
