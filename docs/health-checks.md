> **Status: Current.** Implemented release health-check contract and verification commands.

# Release health checks

`GET /healthz` returns `200 {"status":"ok"}` when the HTTP process serves requests.
It never connects to PostgreSQL or loads a world. `GET /readyz` returns
`200 {"status":"ready"}` only when the configured database can answer a query,
all packaged migrations have been applied, the gameplay tables exist, and the
configured default world loads through the same graph mode as `/play`, including
its interaction document. Neither endpoint requires a session or returns world
content, filesystem paths, credentials or internal errors.

Readiness failures return HTTP 503 with `status: "not_ready"` and one short reason:
`database_unavailable`, `migrations_pending`, or `world_unavailable`. A readiness
probe does not run migrations or write world data. SQL probes have a one-second query timeout and fail immediately when no pool
connection is available. An optional editor-only run without PostgreSQL
is live but not ready for persisted gameplay.

For a local release smoke test, use only a disposable database and scratch worlds:

```sh
curl --fail --silent http://127.0.0.1:4000/healthz
curl --fail --silent http://127.0.0.1:4000/readyz
```

Verify both return 200 after migrations. Restart the release with the database
URL pointing to an unavailable local port: `/healthz` must still return 200 and
`/readyz` must return 503 with `database_unavailable`. Restore the URL and confirm
readiness recovers. In an isolated disposable database, missing migration records
or gameplay tables must produce `migrations_pending`; a missing or malformed
scratch world must produce `world_unavailable`. Do not stop a shared test container
or alter the development database for this check.

For editor checks, use `/editor?world=tiny`; `/` is the landing page and
root URLs with query parameters also show the landing page without redirecting.

HTTP readiness does not prove a reverse proxy passes WebSocket upgrades. For the
LiveView smoke check, open `/play` in a browser against the release or staging URL.
In the Network panel, confirm `/live/websocket` upgrades with HTTP 101, and the
Phoenix channel joins successfully (a `phx_reply` with `status: "ok"`), rather than
repeated disconnects. Confirm a movement action updates the turn without a page
reload, then reload and verify persisted progress. Repeat through the actual
proxy once staging is provisioned; a direct localhost check cannot verify its
TLS or upgrade headers. Use a fixture/scratch world and disposable saves locally.
