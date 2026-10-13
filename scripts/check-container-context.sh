#!/bin/sh
# Exercise Docker/Podman's real ignore matcher using only synthetic data.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scratch=$(mktemp -d)
image="threshold-context-check:$$"
cleanup() {
  docker image rm "$image" >/dev/null 2>&1 || true
  rm -rf "$scratch"
}
trap cleanup EXIT HUP INT TERM
cp "$repo/.dockerignore" "$scratch/.dockerignore"
mkdir -p "$scratch/assets/node_modules" "$scratch/deps" "$scratch/_build" \
  "$scratch/.venv" "$scratch/tmp" "$scratch/.git" \
  "$scratch/priv/worlds/madison/generated" \
  "$scratch/priv/worlds/madison/generations/fake"
for file in assets/build.ts assets/.env assets/node_modules/sentinel deps/sentinel \
  _build/sentinel .venv/sentinel tmp/sentinel .git/sentinel erl_crash.dump \
  priv/worlds/madison/authored.json priv/worlds/madison/boundary.geojson \
  priv/worlds/madison/generated/sentinel \
  priv/worlds/madison/generations/fake/sentinel; do
  printf 'synthetic sentinel\n' > "$scratch/$file"
done
base=$(awk '/ AS runtime$/ {print $2}' "$repo/Dockerfile")
printf 'FROM %s\n' "$base" > "$scratch/Dockerfile"
cat >> "$scratch/Dockerfile" <<'EOF'
COPY . /context
RUN test -f /context/assets/build.ts && \
    test ! -e /context/priv/worlds && \
    test ! -e /context/.git && test ! -e /context/deps && \
    test ! -e /context/_build && test ! -e /context/.venv && \
    test ! -e /context/tmp && test ! -e /context/assets/node_modules && \
    test ! -e /context/assets/.env && test ! -e /context/erl_crash.dump
EOF
docker build -t "$image" "$scratch"
