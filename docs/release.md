# Phoenix release

## Container image

Build from the repository root:

```sh
docker build -t threshold:local .
```

The multi-stage Dockerfile pins Elixir, OTP and Bun to `.tool-versions` and
uses Debian Bookworm for both build and runtime. Only the compiled release
reaches the runtime image; Bun, Python and the source checkout are absent.
The process runs as `threshold` (UID/GID 10001). `.dockerignore` allowlists
build inputs and excludes all world data, local caches, secrets and crash dumps.
Podman also uses this file when no `.containerignore` exists.
Run `sh scripts/check-container-context.sh` to verify the actual ignore matcher
against synthetic world, cache, environment-file and crash-dump sentinels.
This check never copies the repository's world data into a probe image.

No sample world is bundled. Supply a prepared worlds directory at runtime,
readable by UID 10001. On SELinux hosts, use `:ro,Z` for a dedicated scratch
mount so the container can read it; this relabels that directory. For local
verification, use a scratch tiny fixture copy
as described below, never the designer's Madison directory. The container
binds to `0.0.0.0` internally; publish a loopback-only host port for local use.
Keep runtime credentials in an untracked, access-restricted env file containing
`SECRET_KEY_BASE` and `THRESHOLD_DATABASE_URL`; never pass them as build arguments.

```sh
# Database must already exist. Apply pending migrations explicitly, not on boot.
docker run --rm --env-file /path/to/runtime.env threshold:local \
  /app/bin/threshold eval 'Threshold.Release.migrate()'
docker run --rm --env-file /path/to/runtime.env \
  -p 127.0.0.1:4000:4000 \
  -v /path/to/scratch-worlds:/worlds:ro threshold:local
```

For disposable PostgreSQL at `127.0.0.1:5433` on Linux, use `--network host`
instead of `-p`, set `PHX_BIND_ADDRESS=127.0.0.1` and choose an unused `PORT`
in the env file. This reaches the host's isolated test service directly.
Use a dedicated scratch database ending in `_test` and drop it afterward.
An empty or invalid worlds mount makes `/readyz` report unavailable; the
landing page alone is not a readiness check. No container command starts
PostgreSQL or performs automatic migrations.

Verify runtime contents and identity with:

```sh
docker run --rm --entrypoint sh threshold:local -c \
  'id; find /app -print; command -v bun || true; command -v python3 || true'
```

Build twice and compare sorted `/app` listings to check repeatable packaging.
This is a contents check, not a claim of byte-identical image digests: build
timestamps and Debian package repository updates can change layer bytes.

## Standalone release

Build with `make assets` and `MIX_ENV=prod mix release`. The release is at
`_build/prod/rel/threshold`; copy that directory to a host with the same OS and
architecture. It includes the Erlang runtime and compiled application, so Mix,
Elixir and the source checkout are not needed at runtime.

Production requires non-empty `SECRET_KEY_BASE` (generate with `mix phx.gen.secret`)
and `THRESHOLD_DATABASE_URL`. Startup reports all absent required variables together.
The database must already exist. The landing page is at `/`, the world editor at
`/editor`, and the player map at `/play`. Production settings are read at startup:

| Variable | Default | Purpose |
| --- | --- | --- |
| `PHX_SERVER` | `false` | Start HTTP for `true` or `1`; disable for `false` or `0` |
| `PHX_HOST` | `localhost` | Host used in generated URLs |
| `PORT` | `4000` | HTTP port, integer from 1 to 65535 |
| `PHX_BIND_ADDRESS` | `127.0.0.1` | Explicit IPv4 or IPv6 listening address |
| `POOL_SIZE` | `5` | Positive integer database connection pool size |
| `THRESHOLD_WORLDS_DIR` | Release's `priv/worlds` | Absolute directory containing world subdirectories |

The loopback default keeps the local editor private. Set `PHX_BIND_ADDRESS=0.0.0.0`
only when an approved private hosting setup needs it. TLS and access controls are
separate staging work. Setting `PHX_HOST` does not change the listening address.
Development and test configuration retain their existing optional database behavior.

Run pending migrations before starting HTTP:

```sh
bin/threshold eval "Threshold.Release.migrate()"
PHX_SERVER=true bin/threshold start
```

`migrate/0` loads the application configuration and uses Ecto's migrator without
starting the endpoint. Repeated calls apply only pending migrations. It does not
create a database and does not alter migration definitions.

For local release verification use only the disposable PostgreSQL on port 5433
and a scratch copy of `test/fixtures/worlds/tiny`. The current default world name
is `madison`; copy the tiny fixture into a directory named `madison` under the
scratch worlds root and point `THRESHOLD_WORLDS_DIR` there. This changes no world
loading semantics and publishes none of the designer's Madison data.

The bare tiny fixture has no default spawn. For a playable smoke check, prepare
synthetic places, a connection and a spawn in the scratch copy as the
`PlayLiveTest` and `EffectiveGraphTest` setups do. Do not change the real world.
