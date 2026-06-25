#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${CONTAINER_RUNTIME:-podman}"
IMAGE_PREFIX="${MEDIA_HUB_IMAGE_PREFIX:-media-hub}"

if ! command -v "$RUNTIME" >/dev/null 2>&1; then
  echo "error: container runtime '$RUNTIME' not found" >&2
  exit 1
fi

"$RUNTIME" build -t "$IMAGE_PREFIX-rss" "$ROOT_DIR/workers/rss"
"$RUNTIME" build -t "$IMAGE_PREFIX-bluesky" "$ROOT_DIR/workers/bluesky"
"$RUNTIME" build -t "$IMAGE_PREFIX-mastodon" "$ROOT_DIR/workers/mastodon"
"$RUNTIME" build -t "$IMAGE_PREFIX-polymarket" "$ROOT_DIR/workers/polymarket"
