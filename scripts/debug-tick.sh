#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${CONTAINER_RUNTIME:-podman}"
RUN_ID="${RUN_ID:-$(date -u +%Y-%m-%dT%H-%M-%SZ)}"
RUN_DIR="$ROOT_DIR/data/runs/$RUN_ID"
mkdir -p "$RUN_DIR"

config_for() {
  local name="$1"
  if [[ -f "$ROOT_DIR/config/$name.local.yaml" ]]; then
    printf '%s\n' "$ROOT_DIR/config/$name.local.yaml"
  else
    printf '%s\n' "$ROOT_DIR/config/$name.example.yaml"
  fi
}

run_worker() {
  local source_type="$1"
  local image="$2"
  local config="$3"
  echo "[$(date -u +%FT%TZ)] fetching $source_type" | tee -a "$RUN_DIR/manifest.log" >&2
  "$RUNTIME" run --rm \
    -v "$config:/config/config.yaml:ro,z" \
    "$image" fetch --config /config/config.yaml \
    2> >(tee "$RUN_DIR/$source_type.log" >&2) \
    | tee "$RUN_DIR/$source_type.jsonl" \
    | "$ROOT_DIR/scripts/ingest.sh" --source "$source_type" -
}

run_worker rss media-hub-rss "$(config_for rss)"
run_worker bluesky media-hub-bluesky "$(config_for bluesky)"
run_worker polymarket media-hub-polymarket "$(config_for polymarket)"

echo "debug run retained at $RUN_DIR" >&2
