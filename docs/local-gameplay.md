# Local gameplay setup

Use Docker Compose for PostgreSQL and run Phoenix, Bun and the GIS pipeline on the host. Native PostgreSQL works too: the application only needs a connection URL. The editor does not require PostgreSQL.

## Compose database

Install Docker with Compose, then from the repository root:

```bash
docker compose up -d --wait postgres
export THRESHOLD_DATABASE_URL=postgres://threshold:threshold_local@localhost:5432/threshold_game
mix ecto.migrate
make assets
make run
```

Open <http://localhost:4000/play>. In the editor, open **Spawn points**, choose **Choose a point on the map**, click a blue playable point, and choose **Mark as spawn point**. The first mark becomes the default. Mark additional points and use **Use as default spawn** or **Make default** to choose the starting point; **Remove spawn mark** removes a mark. Save when finished. Gold rings identify marked points on the editor map. To make an authored place inspectable, select it, choose **Nearby at playable location**, and save. These changes are deliberate designer actions; no spawn is guessed automatically.

Compose publishes PostgreSQL on loopback only. The `postgres_data` named volume preserves saves when containers stop or are recreated. `docker compose stop` stops the database without removing it. The default password is for this local setup. You can override `THRESHOLD_POSTGRES_PASSWORD`, `THRESHOLD_POSTGRES_PORT`, or `THRESHOLD_POSTGRES_TEST_PORT` in a local `.env` file; update your connection URLs accordingly. Compose reads `.env`, while Phoenix reads the exported URL.

The official PostgreSQL 18 image stores its versioned data below `/var/lib/postgresql`, which is where the named volume is mounted. The major version is pinned to 18; patch updates follow that image tag. See the [official PostgreSQL image documentation](https://hub.docker.com/_/postgres) and [Compose health checks](https://docs.docker.com/compose/how-tos/startup-order).

## Applying new migrations to your development database

Code that adds tables needs the migration applied to the database your `make run` uses, or the features that read them fail. Agent sessions work only against disposable databases (the test container on port 5433 and scratch databases created and dropped there) and never migrate your development database; that is your step:

```bash
export THRESHOLD_DATABASE_URL=postgres://threshold:threshold_local@localhost:5432/threshold_game
mix ecto.migrate
```

Pending: `20261010000000_create_interaction_progress` (the `player_discoveries` and `completed_interactions` tables, from the interactions work). Until it is applied, a world with an `interactions.json` (Madison now has one, *The Quiet Hour*) shows "Investigations are unavailable: the database needs the latest migration" in the panel, while movement and **New walk** keep working; no investigation can be played. The migration is additive and keeps your saves.

## Full checks with PostgreSQL

The test service runs on a separate port with a disposable filesystem. It never shares the player save volume.

```bash
docker compose --profile test up -d --wait postgres-test
THRESHOLD_TEST_DATABASE_URL=postgres://threshold:threshold_local@localhost:5433/threshold_test make check
```

Tests apply migrations automatically and isolate each test using Ecto SQL Sandbox. Without `THRESHOLD_TEST_DATABASE_URL`, database tests are explicitly excluded. The development URL is never used for tests, and the test database name must end in `_test`.

## Production mode on this computer

With the database URL exported and PostgreSQL running:

```bash
make assets
MIX_ENV=prod mix ecto.migrate
SECRET_KEY_BASE="$(mix phx.gen.secret)" MIX_ENV=prod mix phx.server
```

This serves on loopback at <http://localhost:4000>. Set `PORT` to use another port. Preserve your secret across runs if you want existing browser sessions to remain valid. This command runs production mode locally; it does not deploy the application.

## Verification limits

Movement, saves and browser restoration were verified using an isolated PostgreSQL 18.6 instance and a scratch Madison world. Docker is not installed in the agent's current environment, so the Compose container startup itself has not been exercised here. Reduced-motion animation handling is implemented but has not been separately tested in the browser.
