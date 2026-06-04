#!/usr/bin/env bash
set -euo pipefail

# A "what happened" overview for a time window: ingest activity, per-source
# counts, the most cross-referenced links, and the biggest market moves.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${MEDIA_HUB_DATA_DIR:-$HOME/.local/share/media-hub}"
DB_PATH="${MEDIA_HUB_DB:-$DATA_DIR/media-hub.sqlite}"
SINCE_RAW="24h"
LIMIT=10

usage() {
  cat >&2 <<'EOF'
Usage: scripts/digest.sh [options]

Print a grouped overview of recent activity.

Options:
  --since TIMESTAMP|24h|7d   Window to summarize (default: 24h)
  --limit N                  Rows per section (default: 10)
  --db PATH                  SQLite database path
EOF
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
    --since) SINCE_RAW="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

SINCE="$(since_to_iso "$SINCE_RAW")"
SINCE_SQL="$(sql_escape "$SINCE")"

echo "media-hub digest since $SINCE ($SINCE_RAW)"
echo

echo "== records by source =="
sqlite3 -header -column "$DB_PATH" \
  "SELECT source, record_type, COUNT(*) AS n, MAX(observed_at) AS last_seen
   FROM records
   WHERE observed_at >= '$SINCE_SQL'
   GROUP BY source, record_type
   ORDER BY n DESC, source
   LIMIT $LIMIT;"
echo

echo "== most-referenced links (>= 2 sources) =="
"$ROOT_DIR/scripts/links.sh" --db "$DB_PATH" --since "$SINCE" --min-sources 2 --limit "$LIMIT"
echo

echo "== biggest market moves =="
"$ROOT_DIR/scripts/markets.sh" --db "$DB_PATH" --since "$SINCE" --moved --limit "$LIMIT"
echo

echo "== recent ingest runs =="
sqlite3 -header -column "$DB_PATH" \
  "SELECT id, source, status, records_inserted AS records, started_at, finished_at
   FROM ingest_runs
   WHERE started_at >= '$SINCE_SQL'
   ORDER BY id DESC
   LIMIT $LIMIT;"
