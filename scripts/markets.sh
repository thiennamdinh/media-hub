#!/usr/bin/env bash
set -euo pipefail

# Probability movement view over Polymarket probability_signal records.
# Compares the earliest and latest probability snapshot per market within the
# window and reports the delta.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${MEDIA_HUB_DATA_DIR:-$HOME/.local/share/media-hub}"
DB_PATH="${MEDIA_HUB_DB:-$DATA_DIR/media-hub.sqlite}"
LIMIT=25
SINCE=""
MOVED_ONLY=0
THRESHOLD=0.0

usage() {
  cat >&2 <<'EOF'
Usage: scripts/markets.sh [options]

Show Polymarket markets ranked by probability movement within a window.

Options:
  --since TIMESTAMP|24h|7d   Only consider snapshots observed since this time
  --moved                    Only show markets whose probability changed
  --threshold P              Minimum absolute probability change (e.g. 0.05)
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
    --moved) MOVED_ONLY=1; shift ;;
    --threshold) THRESHOLD="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

WHERE="record_type = 'probability_signal' AND json_extract(raw_json, '\$.probability') IS NOT NULL"
if [[ -n "$SINCE" ]]; then
  WHERE="$WHERE AND observed_at >= '$(sql_escape "$SINCE")'"
fi

HAVING="1=1"
if [[ "$MOVED_ONLY" -eq 1 ]]; then
  HAVING="ABS(last_prob - first_prob) > 0"
fi
if [[ -n "$THRESHOLD" && "$THRESHOLD" != "0.0" ]]; then
  HAVING="$HAVING AND ABS(last_prob - first_prob) >= $(sql_escape "$THRESHOLD")"
fi

sqlite3 -header -column "$DB_PATH" \
  "WITH m AS (
     SELECT
       id,
       COALESCE(json_extract(raw_json, '\$.market_id'), canonical_url, title) AS market_key,
       title,
       canonical_url,
       observed_at,
       CAST(json_extract(raw_json, '\$.probability') AS REAL) AS prob
     FROM records
     WHERE $WHERE
   ),
   agg AS (
     SELECT
       market_key,
       MAX(title)         AS title,
       MAX(canonical_url) AS url,
       COUNT(*)           AS snapshots,
       (SELECT prob FROM m i WHERE i.market_key = o.market_key ORDER BY observed_at ASC,  id ASC  LIMIT 1) AS first_prob,
       (SELECT prob FROM m i WHERE i.market_key = o.market_key ORDER BY observed_at DESC, id DESC LIMIT 1) AS last_prob
     FROM m o
     GROUP BY market_key
   )
   SELECT
     title,
     ROUND(first_prob, 3)               AS from_p,
     ROUND(last_prob, 3)                AS to_p,
     ROUND(last_prob - first_prob, 3)   AS delta,
     snapshots,
     url
   FROM agg
   WHERE $HAVING
   ORDER BY ABS(last_prob - first_prob) DESC, snapshots DESC
   LIMIT $LIMIT;"
