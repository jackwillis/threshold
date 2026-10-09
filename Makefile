# Cross-language orchestration. Elixir-only checks live in `mix precommit`.
PY := .venv/bin
export PATH := $(HOME)/.bun/bin:$(PATH)
W ?= madison

.PHONY: setup assets check-assets run test check fmt build-world validate-world determinism acquire-world

setup:
	mix setup
	test -d .venv || python3.12 -m venv .venv
	$(PY)/pip install -q -e "gis[dev]"
	cd assets && bun install --frozen-lockfile
	$(MAKE) assets

assets:
	cd assets && bun run build

run:
	mix phx.server

test:
	mix test
	$(PY)/pytest gis -q

check-assets:
	cd assets && bun run typecheck

fmt:
	mix format
	$(PY)/ruff format gis

check:
	mix precommit
	$(PY)/ruff check gis
	$(MAKE) check-assets
	$(PY)/pytest gis -q
	@if [ -f priv/worlds/$(W)/nodes.geojson ]; then $(MAKE) validate-world determinism; else echo "skip world checks: no generated $(W) geography yet"; fi

build-world:
	$(PY)/threshold-gis build $(W)

validate-world:
	$(PY)/threshold-gis validate $(W)

# Rebuild into a scratch copy and require byte-identical output.
determinism:
	rm -rf tmp/determinism && mkdir -p tmp/determinism
	cp -r priv/worlds/$(W) tmp/determinism/$(W)
	$(PY)/threshold-gis build $(W) --worlds-dir tmp/determinism
	for f in nodes edges context; do diff -q priv/worlds/$(W)/$$f.geojson tmp/determinism/$(W)/$$f.geojson; done

# The only target that touches the network.
acquire-world:
	$(PY)/threshold-gis acquire $(W)
