# Phoenix release

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
