#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${MEDIA_HUB_DATA_DIR:-$HOME/.local/share/media-hub}"
DB_PATH="${MEDIA_HUB_DB:-$DATA_DIR/media-hub.sqlite}"
LIMIT=25
SOURCE=""
TYPE=""
SINCE=""

usage() {
  echo "Usage: scripts/items.sh [--limit N] [--source SOURCE] [--type RECORD_TYPE] [--since TIMESTAMP|24h|7d]" >&2
}

sql_escape() { printf "%s" "$1" | sed "s/'/''/g"; }

since_to_iso() {
  local value="$1"
  if [[ "$value" =~ ^([0-9]+)h$ ]]; then
    date -u -d "-${BASH_REMATCH[1]} hours" +%FT%TZ
  elif [[ "$value" =~ ^([0-9]+)d$ ]]; then
    date -u -d "-${BASH_REMATCH[1]} days" +%FT%TZ
  else
    printf '%s\n' "$value"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) DB_PATH="${2:-}"; shift 2 ;;
    --limit) LIMIT="${2:-}"; shift 2 ;;
    --source) SOURCE="${2:-}"; shift 2 ;;
    --type) TYPE="${2:-}"; shift 2 ;;
    --since) SINCE="$(since_to_iso "${2:-}")"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

WHERE="1=1"
if [[ -n "$SOURCE" ]]; then
  WHERE="$WHERE AND source = '$(sql_escape "$SOURCE")'"
fi
if [[ -n "$TYPE" ]]; then
  WHERE="$WHERE AND record_type = '$(sql_escape "$TYPE")'"
fi
if [[ -n "$SINCE" ]]; then
  WHERE="$WHERE AND observed_at >= '$(sql_escape "$SINCE")'"
fi

sqlite3 -header -column "$DB_PATH" \
  "SELECT id, observed_at, source, record_type, COALESCE(title, canonical_url, '') AS item FROM records WHERE $WHERE ORDER BY observed_at DESC, id DESC LIMIT $LIMIT;"
