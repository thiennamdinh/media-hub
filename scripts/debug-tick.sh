#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${CONTAINER_RUNTIME:-podman}"
CONFIG_DIR="${MEDIA_HUB_CONFIG_DIR:-$HOME/.config/media-hub}"
DATA_DIR="${MEDIA_HUB_DATA_DIR:-$HOME/.local/share/media-hub}"
IMAGE_PREFIX="${MEDIA_HUB_IMAGE_PREFIX:-media-hub}"
RUN_ID="${RUN_ID:-$(date -u +%Y-%m-%dT%H-%M-%SZ)}"
RUN_DIR="$DATA_DIR/runs/$RUN_ID"
mkdir -p "$RUN_DIR"

config_for() {
  local name="$1"
  if [[ -f "$CONFIG_DIR/$name.yaml" ]]; then
    printf '%s\n' "$CONFIG_DIR/$name.yaml"
  elif [[ -f "$ROOT_DIR/config/$name.local.yaml" ]]; then
    printf '%s\n' "$ROOT_DIR/config/$name.local.yaml"
  else
    printf '%s\n' "$ROOT_DIR/config/$name.example.yaml"
  fi
}

run_worker() {
  local source_type="$1"
  local image="$2"
  local config="$3"
  local env_args=()

  case "$source_type" in
    bluesky)
      for name in BLUESKY_SERVICE BLUESKY_IDENTIFIER BLUESKY_APP_PASSWORD; do
        if [[ -n "${!name:-}" ]]; then
          env_args+=(--env "$name")
        fi
      done
      ;;
    mastodon)
      while IFS='=' read -r name _; do
        if [[ "$name" == MASTODON_* ]]; then
          env_args+=(--env "$name")
        fi
      done < <(env)
      ;;
  esac

  echo "[$(date -u +%FT%TZ)] fetching $source_type" | tee -a "$RUN_DIR/manifest.log" >&2
  "$RUNTIME" run --rm --log-driver=none \
    "${env_args[@]}" \
    -v "$config:/config/config.yaml:ro,z" \
    "$image" fetch --config /config/config.yaml \
    2> >(tee "$RUN_DIR/$source_type.log" >&2) \
    | tee "$RUN_DIR/$source_type.jsonl" \
    | "$ROOT_DIR/scripts/ingest.sh" --source "$source_type" -
}

run_worker rss "$IMAGE_PREFIX-rss" "$(config_for rss)"
run_worker bluesky "$IMAGE_PREFIX-bluesky" "$(config_for bluesky)"
run_worker mastodon "$IMAGE_PREFIX-mastodon" "$(config_for mastodon)"
run_worker polymarket "$IMAGE_PREFIX-polymarket" "$(config_for polymarket)"

echo "debug run retained at $RUN_DIR" >&2
