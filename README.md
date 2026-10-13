# Threshold

Threshold is a single-player mystery game set in Madison, Wisconsin. Explore a Classic Atlas map, walk one connection at a time, investigate places, and record discoveries. Phoenix LiveView and TypeScript/MapLibre power the game and its local world-authoring editor; a Python/OSMnx pipeline builds the geography.

The editor (`/editor`) and player map (`/play`) work locally, with PostgreSQL-saved progress and four visual seasons. The first authored mystery, *The Quiet Hour*, has automated content checks and scratch-world browser playtests. Studio V2, the Field Journal, and radio gameplay are planned. [Implementation status](docs/implementation-status.md) describes the features and verification limits.

## Quick start

Use Bash, Git, Make, Docker with Compose, and the versions in [.tool-versions](.tool-versions): Elixir 1.19.6 / OTP 26.2.5.21, Python 3.12 (including `venv`), and Bun 1.4.2. Install the Erlang/Elixir build prerequisites for your platform. Bun's usual `~/.bun/bin` location is added to PATH by Make. Initial setup downloads dependencies.

This quick start uses a disposable PostgreSQL service on loopback port 5433 and a scratch copy of the tiny synthetic world. It does not play the Madison mystery or edit its files. In a new Bash shell:

```bash
git clone https://github.com/jackwillis/threshold.git
cd threshold

# Choose a local password; if the test service already exists, use its password.
read -rsp 'Disposable PostgreSQL password: ' THRESHOLD_POSTGRES_PASSWORD
printf '\n'
export THRESHOLD_POSTGRES_PASSWORD
docker compose --profile test up -d --wait postgres-test
# The demo walk gets its own database so saved progress cannot disturb `make check`.
docker compose --profile test exec -T postgres-test \
  sh -c 'createdb -U threshold threshold_test_demo 2>/dev/null || true'
export THRESHOLD_DATABASE_URL="$(python3.12 - <<'PYURL'
import os
from urllib.parse import quote
password = quote(os.environ["THRESHOLD_POSTGRES_PASSWORD"], safe="")
print(f"postgres://threshold:{password}@localhost:5433/threshold_test_demo")
PYURL
)"

export THRESHOLD_WORLDS_DIR="$(mktemp -d)"
cp -R test/fixtures/worlds/tiny "$THRESHOLD_WORLDS_DIR/tiny"
# Give only the scratch fixture a starting point on its generated graph.
python3.12 - <<'PYWORLD'
import json, os
from pathlib import Path
path = Path(os.environ["THRESHOLD_WORLDS_DIR"]) / "tiny" / "authored.json"
world = json.loads(path.read_text())
world["spawns"] = [{"id": "spawn:demo", "location": "pn:1", "default": True}]
path.write_text(json.dumps(world) + "\n")
PYWORLD

make setup
mix ecto.migrate
make run
```

Open [the scratch player map](http://localhost:4000/play?world=tiny&graph=generated). Choose the numbered destination to walk the fixture's connection. This small world has no story content. The [scratch editor](http://localhost:4000/editor?world=tiny) is available too.

Stop Phoenix with Ctrl-C. From the same shell, run the full gate:

```bash
# Tests use their own fixture copies, not the scratch world's edited spawn, and
# their own database, not the demo one.
unset THRESHOLD_WORLDS_DIR
export THRESHOLD_TEST_DATABASE_URL="${THRESHOLD_DATABASE_URL%/threshold_test_demo}/threshold_test"
make check
```

When you are done, drop the demo database (disposable data only; never run this against another database):

```bash
docker compose --profile test exec -T postgres-test dropdb -U threshold --if-exists threshold_test_demo
```

`make check` runs Elixir compilation/format/tests, ruff, TypeScript checks, Bun tests/material checks, Python tests, and world validation plus a byte-identical offline rebuild. Without `THRESHOLD_TEST_DATABASE_URL`, database tests are excluded. The test database name must be `threshold_test`, `threshold_test_<suffix>` (for example one per parallel session) or end in `_test`; do not point it at a player-save database. The demo database `threshold_test_demo` also passes this check but holds the walk you just played, so the gate uses `threshold_test`. Stop the test service with `docker compose --profile test stop postgres-test` when no other session is using it. Its data is disposable, not a persistent game save.

For a persistent local game and deliberate Madison authoring, follow [local gameplay setup](docs/local-gameplay.md). [Release configuration](docs/release.md) and [health checks](docs/health-checks.md) cover the existing production runtime; hosted staging remains planned.

## Repository map

| Path | Contents |
| --- | --- |
| `lib/threshold/` | World validation/loading, authored edits, movement, interactions, saved sessions |
| `lib/threshold_web/` | Phoenix editor, `/play`, and `/atlas` prototype |
| `assets/` | TypeScript mapping hooks, cartography, bundled frontend assets |
| `gis/` | Python geographic import, build, validation, and tests |
| `priv/worlds/` | Pinned source geography, generated snapshots, authored worlds |
| `test/fixtures/worlds/` | Synthetic worlds for isolated verification |
| `docs/` | Design, architecture, operations, and planning references |

Useful commands: `make assets` rebuilds the frontend; `make test` runs Elixir and Python tests; `make fmt` formats Elixir and Python. `make build-world` and `make build-playable` rebuild geography offline, while `make acquire-world` downloads a new snapshot and requires designer approval. See [Makefile](Makefile) for targets.

## Documentation and contributing

Read [current design](docs/current-design.md), [implementation status](docs/implementation-status.md), and the [handoff](docs/handoff.md). The [documentation index](docs/README.md) preserves the detailed memo links and points to the [architecture](docs/architecture/ux-v2.md) and [planning](docs/planning/next-milestones.md) references.

Work is tracked in [GitHub Issues](https://github.com/jackwillis/threshold/issues) and [milestones](https://github.com/jackwillis/threshold/milestones). Follow [AGENTS.md](AGENTS.md) and the [agent workflow](docs/planning/agent-workflow.md): a Ready label needs designer authorization; implement on an issue branch, run `make check`, open a reviewed PR, and let the designer merge.

Keep source snapshots, generated geography, and authored data separate. Never hand-edit generated files or overwrite `priv/worlds/madison/authored.json`, the playable boundary, the `generated` symlink, or generation snapshots. Agents use scratch worlds and disposable PostgreSQL only; they never migrate or write the development database. New gameplay systems, environmental notes, and default-spawn changes need explicit designer approval. Do not push `main`, merge, or deploy.
