#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="${MEDIA_HUB_DB:-$ROOT_DIR/data/media-hub.sqlite}"
LIMIT=25

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) DB_PATH="${2:-}"; shift 2 ;;
    --limit) LIMIT="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: scripts/search.sh [--limit N] QUERY" >&2
      exit 0 ;;
    *) break ;;
  esac
done

QUERY="${*:-}"
if [[ -z "$QUERY" ]]; then
  echo "error: query required" >&2
  exit 1
fi
LIKE="%$(printf "%s" "$QUERY" | sed "s/'/''/g")%"

sqlite3 -header -column "$DB_PATH" \
  "SELECT id, observed_at, source, record_type, COALESCE(title, canonical_url, '') AS item FROM records WHERE title LIKE '$LIKE' OR canonical_url LIKE '$LIKE' OR raw_json LIKE '$LIKE' ORDER BY observed_at DESC, id DESC LIMIT $LIMIT;"
