# Keep Elixir, OTP and Bun aligned with .tool-versions; use the same Debian
# release in builder and runtime so the bundled ERTS has compatible libraries.
FROM docker.io/oven/bun:1.4.2 AS bun
FROM docker.io/hexpm/elixir:1.19.6-erlang-26.2.5.21-debian-bookworm-20261005-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends build-essential ca-certificates git \
    && rm -rf /var/lib/apt/lists/*
COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun
ENV MIX_ENV=prod NODE_ENV=production
WORKDIR /build
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
COPY config/config.exs config/prod.exs config/
RUN mix deps.get --only prod && mix deps.compile
COPY assets assets
RUN cd assets && bun install --frozen-lockfile
COPY lib lib
# Explicit allowlist: world data never enters a build stage or the release.
COPY priv/static priv/static
COPY priv/repo priv/repo
RUN cd assets && bun run build
COPY config/runtime.exs config/runtime.exs
RUN mix compile && mix release

FROM docker.io/library/debian:bookworm-20261005-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates libstdc++6 libncurses6 libtinfo6 libssl3 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 threshold \
    && useradd --uid 10001 --gid threshold --create-home threshold
WORKDIR /app
COPY --from=build --chown=threshold:threshold /build/_build/prod/rel/threshold ./
ENV LANG=C.UTF-8 PHX_SERVER=true PHX_BIND_ADDRESS=0.0.0.0 \
    PORT=4000 THRESHOLD_WORLDS_DIR=/worlds ERL_CRASH_DUMP=/tmp/erl_crash.dump
USER threshold
EXPOSE 4000
CMD ["/app/bin/threshold", "start"]
