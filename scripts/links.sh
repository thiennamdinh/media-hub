#!/usr/bin/env bash
set -euo pipefail

# Cross-source URL view: group records by canonical_url and show which sources
# mentioned each link. The canonical_url join is what lets RSS, Bluesky, and
# Polymarket records converge on the same underlying story.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${MEDIA_HUB_DATA_DIR:-$HOME/.local/share/media-hub}"
DB_PATH="${MEDIA_HUB_DB:-$DATA_DIR/media-hub.sqlite}"
LIMIT=25
SINCE=""
MIN_SOURCES=2
MENTIONED_BY=""

usage() {
  cat >&2 <<'EOF'
Usage: scripts/links.sh [options]

Show links (canonical_url) ranked by how many distinct sources mention them.

Options:
  --since TIMESTAMP|24h|7d   Only consider records observed since this time
  --min-sources N            Require at least N distinct sources (default: 2)
  --mentioned-by A,B,...     Require a mention from each listed source/source_type
                             (matches source name, source_type, or source prefix)
  --limit N                  Max rows (default: 25)
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
    --since) SINCE="$(since_to_iso "${2:-}")"; shift 2 ;;
    --min-sources) MIN_SOURCES="${2:-}"; shift 2 ;;
    --mentioned-by) MENTIONED_BY="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

WHERE="canonical_url IS NOT NULL"
if [[ -n "$SINCE" ]]; then
  WHERE="$WHERE AND observed_at >= '$(sql_escape "$SINCE")'"
fi

# A token matches a row if it equals the source, the source_type, or is a prefix
# of the source (e.g. "bluesky" matches "bluesky-actor:jay.bsky.team").
source_match() {
  local token; token="$(sql_escape "$1")"
  printf "(source = '%s' OR json_extract(raw_json, '\$.source_type') = '%s' OR source LIKE '%s%%')" \
    "$token" "$token" "$token"
}

HAVING="COUNT(DISTINCT source) >= $(sql_escape "$MIN_SOURCES")"
if [[ -n "$MENTIONED_BY" ]]; then
  IFS=',' read -ra TOKENS <<< "$MENTIONED_BY"
  for token in "${TOKENS[@]}"; do
    token="$(echo "$token" | xargs)"  # trim whitespace
    [[ -z "$token" ]] && continue
    HAVING="$HAVING AND SUM(CASE WHEN $(source_match "$token") THEN 1 ELSE 0 END) > 0"
  done
fi

sqlite3 -header -column "$DB_PATH" \
  "SELECT
     COUNT(DISTINCT source) AS sources,
     COUNT(*)               AS mentions,
     GROUP_CONCAT(DISTINCT source) AS by_sources,
     MAX(observed_at)       AS last_seen,
     COALESCE(MAX(title), canonical_url) AS title,
     canonical_url          AS url
   FROM records
   WHERE $WHERE
   GROUP BY canonical_url
   HAVING $HAVING
   ORDER BY sources DESC, mentions DESC, last_seen DESC
   LIMIT $LIMIT;"
