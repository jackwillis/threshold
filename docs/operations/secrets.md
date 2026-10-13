# Staging variables and credential custody

This is an inventory for the private staging direction, not an authorization to provision or deploy. The designer owns access grants and approves credential rotation. Store values in the chosen private credential store and protected host or CI configuration, never in Git, PRs, logs or shell history. Record custody and rotation dates without recording values here. Production, staging and disposable tests use separate credentials.

## Application runtime (implemented)

Verified against [runtime.exs](../../config/runtime.exs) after #2. Application credentials belong to the application scope; provisioning and image-deploy credentials are not passed to Phoenix. “Host environment” means the release process environment, supplied from a protected operator-managed configuration; the exact secret delivery mechanism awaits the hosting tickets.

| Name | Secret? / behavior | Owner | Lives in | Rotation or change procedure |
| --- | --- | --- | --- | --- |
| `SECRET_KEY_BASE` | Secret; non-empty required in production; signs/encrypts endpoint cookies | Designer/application operator | Private credential store and release environment | Generate a fresh key privately; coordinate replacement and restart; expect existing signed sessions to become invalid and assess guest save access before rotation |
| `THRESHOLD_DATABASE_URL` | Secret when it contains credentials; non-empty required in production; optional in development | Designer/database operator | Private credential store and release environment; distinct staging role/database | Rotate database role credential, update URL, restart/reconnect and check readiness; keep the development URL out of agent sessions |
| `THRESHOLD_TEST_DATABASE_URL` | Secret when it contains credentials; used only in test configuration | Test operator | Local disposable-test environment or CI configuration, never staging application configuration | Replace test credentials/database as needed; port 5433 only for local agent databases; current guard requires database name ending `_test` (follow-up #39 tracks numbered scratch names) |
| `THRESHOLD_WORLDS_DIR` | Not secret; optional root of world directories; expanded to an absolute path; defaults to packaged `priv/worlds` | Designer/content release operator | Release environment and reviewed release manifest | Change only to an approved coherent world snapshot; restart and verify readiness/save compatibility; never point staging at the designer's working world |
| `PHX_SERVER` | Not secret; production default `false`; accepts `true`/`1` or `false`/`0` | Application operator | Release environment | Explicitly enable for serving; restart after change. Outside production any present value enables the endpoint in this runtime file |
| `PHX_HOST` | Not secret; production URL host, default `localhost`; does not select listening interface | Application operator | Release environment and release manifest | Coordinate with proxy/DNS and generated URL checks; restart |
| `PORT` | Not secret; default `4000`; production integer range 1–65535 | Application operator | Release environment and approved proxy configuration | Coordinate proxy upstream and listening port; restart and verify health |
| `PHX_BIND_ADDRESS` | Not secret; production IPv4/IPv6 literal; default `127.0.0.1` | Application operator | Release environment and network configuration | Change only with approved private exposure/proxy rules; restart and verify interface/access restrictions |
| `POOL_SIZE` | Not secret; positive integer, production default `5`; non-production database pool stays `5` | Application/database operator | Release environment | Budget against PostgreSQL connection limits across processes and migration jobs; restart |

Missing required production variables are reported together. Build-time tools such as `MIX_ENV` select a build configuration; they are not variables read by `config/runtime.exs`. See [release instructions](../release.md) for the implemented startup contract.

## Provisioning scope (planned, separate from deployment)

Manual VPS provisioning is the initial direction. OVH API integration is optional and not implemented; do not create credentials merely because names are listed. These are proposed operator names, not application inputs.

| Name / credential | Owner | Lives in | Rotation |
| --- | --- | --- | --- |
| `OVH_ENDPOINT` (non-secret API region selector), `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`, `OVH_CONSUMER_KEY` | Designer/infrastructure operator | Private credential store and provisioning-only environment | Revoke/regenerate the affected API credential; verify narrowly scoped permissions; never give ordinary image deployment this access |
| Provisioning administrator SSH key (no application variable) | Designer/infrastructure operator | Operator key store; public key in host access configuration | Install replacement public key, verify access, then revoke the old key; retain an independently controlled recovery path |

## Image build and deploy scope (planned)

GHCR publishing and manual staging deployment are future tickets. Exact workflow secret names must be reconciled when those workflows exist. None of the names below are currently read by Phoenix.

| Name / credential | Owner | Lives in | Rotation |
| --- | --- | --- | --- |
| `GITHUB_TOKEN` (job-provided image publishing token) | Repository owner | Ephemeral GitHub Actions job environment with minimum package permissions | Expires with job; adjust workflow permissions rather than persist it on VPS |
| `GHCR_PULL_TOKEN` (only if private image pulls require it) | Repository/deploy operator | Private credential store and host registry credential configuration | Issue replacement with read-only package permission; verify pull, revoke previous token |
| `STAGING_SSH_KEY`, `STAGING_SSH_HOST_KEY` (public pinned host key), `STAGING_HOST`, `STAGING_USER` (non-secret target selectors) | Designer/deploy operator | Protected deploy environment; private key in secret store | Rotate client access independently of OVH; verify replacement; change host pin only after trusted host identity verification |

Deploy access may select an approved image and run the approved migration procedure, but must not provision servers, grant staff permissions or read provisioning credentials. Image digest, Git SHA and world manifest are non-secret release records, not credentials.

## Backup and future integrations (planned)

| Name / credential | Owner | Lives in | Rotation |
| --- | --- | --- | --- |
| `RESTIC_REPOSITORY`, `RESTIC_PASSWORD`; backend-specific access credentials selected by #17 | Designer/backup operator | Independent private credential/key store and backup-only environment | Keep recovery key custody independent of VPS; test access with replacement credentials before revocation; changing repository encryption needs the backup tool's approved key procedure |
| Future draft-object-storage credentials, email delivery credentials, GitHub App private key | Designer/respective integration operator | Separate integration-specific stores when those tickets implement exact names | Define least-privilege custody and rotation in their tickets before enabling; not requirements for today's release |

Keep at least one recoverable encrypted copy outside OVHcloud. A backup access credential and the key needed to decrypt the backup are distinct recovery dependencies. Do not rely on the impaired OVH dedicated server as home storage. See the [restore outline](restore.md).
