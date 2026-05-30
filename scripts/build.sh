#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${CONTAINER_RUNTIME:-podman}"

if ! command -v "$RUNTIME" >/dev/null 2>&1; then
  echo "error: container runtime '$RUNTIME' not found" >&2
  exit 1
fi

"$RUNTIME" build -t media-hub-rss "$ROOT_DIR/workers/rss"
"$RUNTIME" build -t media-hub-bluesky "$ROOT_DIR/workers/bluesky"
"$RUNTIME" build -t media-hub-polymarket "$ROOT_DIR/workers/polymarket"
