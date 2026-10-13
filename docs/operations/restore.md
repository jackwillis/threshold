# Restore drill outline

This outline feeds backup/restore ticket #17 and deployment ticket #16. It is not an implemented backup service, restore script, retention policy or permission to operate a live environment. The designer approves recovery objectives, destinations and any eventual cutover. See [staging architecture](../architecture/staging.md), [credential inventory](secrets.md) and [rollback guidance](deploy-rollback.md).

## Capture a coherent recovery set

Record a backup ID/time, PostgreSQL version and schema migration versions, compatible release SHA/digest, published world/asset manifest, dump/object checksums, encryption key reference and backup locations. Keep secret values and credentials out of the record. Initially use PostgreSQL-aware logical dumps, not a live volume file copy. Record any roles/extensions needed to restore into a newly created database.

Today's durable application state includes `player_progress`, `player_discoveries`, `completed_interactions` and `schema_migrations`. When draft identities, audit records or uploaded assets are implemented, include their database metadata and referenced immutable media versions in the same recovery contract. Git releases alone cannot recover unpublished work. Freeze or otherwise coordinate database and object-storage capture so referenced asset versions remain available.

Keep an encrypted off-VPS copy and at least one copy outside OVHcloud; plan a second encrypted copy at the designer's eventual independent backup destination. The impaired OVH dedicated server is not home backup storage. Set retention and data-loss/downtime targets explicitly in #17. Verify backup freshness and failure notification; a successful backup process exit is insufficient evidence.

## Drill in isolation

1. Select a specific backup and compatible release/world set. Confirm the operator can independently retrieve both encrypted data and the recovery key without relying on the lost VPS. Record start time and agreed recovery targets.
2. Create a new disposable PostgreSQL database on the test container at port 5433 and a separate scratch world/assets directory. Never restore over the development database, an existing staging database, the sole backup or `priv/worlds/madison`. Use a `_test` database suffix for test-mode runs under the current runtime guard.
3. Verify checksums and decrypt privately. Restore into the empty disposable target with the approved PostgreSQL tools. Check restoration errors, schema versions, required constraints/indexes and referential integrity; do not silently discard errors. Preserve the original dump.
4. Restore the matching immutable world/asset files and any future draft-object versions into isolated storage. Verify asset hashes/references and database metadata together. Do not regenerate geography or substitute a newer world for the recorded one.
5. Boot the compatible release with the disposable target supplied as `THRESHOLD_DATABASE_URL` in production mode and `THRESHOLD_WORLDS_DIR` pointing at the scratch root. Apply further migrations only when the drill explicitly tests an approved upgrade path; first prove the backed-up schema can be recovered.
6. Check `/healthz`, `/readyz`, `/` and `/play`; exercise LiveView connection/reconnection in a browser. Verify a synthetic known player's location, turn, visited history, discoveries and completed choices; make one valid one-hop move and reload to prove restored writes persist. For future drafts/assets verify saved revisions and referenced media availability as well.
7. Record backup ID, restored schema/artifact versions, row-count/integrity checks, functional results, elapsed recovery time, newest recovered timestamp, failures and remediation issues. Compare measured data loss and recovery time with the designer's targets. A bare health response or row count is not a successful drill.
8. Stop the drill release, drop only its disposable database and delete only its scratch files after retaining sanitized evidence. Leave the shared test container running. Repeat after backup/encryption/storage/schema changes and on the cadence approved in #17.

## Actual recovery (later, separately authorized)

Restore to a separate target and validate before switching service. Quiesce writers and explain which post-backup writes would be lost; retain the failed database and latest backup for investigation. The designer approves the exact database/world/asset pairing and cutover. Record how to return to the previous target if verification fails. Rotation of a lost session-signing key can affect guest save access, so include key custody and identity recovery in the later account/backup policies rather than assuming a database restore alone restores browser identity.
