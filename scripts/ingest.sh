#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/ingest.sh [--source SOURCE] [--db DB_PATH] [FILE|-]

Reads JSONL records from FILE or stdin and inserts them into SQLite.
Workers should provide source/source_type/record_type/observed_at; --source is only a fallback.
EOF
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${MEDIA_HUB_DATA_DIR:-$HOME/.local/share/media-hub}"
DB_PATH="${MEDIA_HUB_DB:-$DATA_DIR/media-hub.sqlite}"
SCHEMA_PATH="${MEDIA_HUB_SCHEMA:-$ROOT_DIR/db/schema.sql}"
SOURCE_FALLBACK=""
INPUT="-"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE_FALLBACK="${2:-}"; shift 2 ;;
    --db)
      DB_PATH="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    -)
      INPUT="-"; shift ;;
    *)
      INPUT="$1"; shift ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "error: sqlite3 is required" >&2
  exit 1
fi

mkdir -p "$(dirname "$DB_PATH")"
sqlite3 "$DB_PATH" < "$SCHEMA_PATH"

TMP_SQL="$(mktemp)"
trap 'rm -f "$TMP_SQL"' EXIT

JQ_FILTER="$(cat <<'JQ'
  def sqlstr:
    if . == null then "NULL"
    else "\u0027" + (tostring | gsub("\u0027"; "\u0027\u0027")) + "\u0027"
    end;

  select(type == "object")
  | . as $raw
  | ($raw.source // $source_fallback) as $source
  | ($raw.record_type // empty) as $record_type
  | ($raw.observed_at // $raw.published_at // empty) as $observed_at
  | ($raw.canonical_url // null) as $canonical_url
  | ($raw.external_id // null) as $external_id
  | select(($source | length) > 0 and ($record_type | length) > 0 and ($observed_at | length) > 0)
  | "INSERT INTO records (source, record_type, canonical_url, observed_at, title, raw_json) SELECT " +
    ($source | sqlstr) + ", " +
    ($record_type | sqlstr) + ", " +
    ($canonical_url | sqlstr) + ", " +
    ($observed_at | sqlstr) + ", " +
    ($raw.title // null | sqlstr) + ", " +
    ($raw | tojson | sqlstr) +
    " WHERE " + ($record_type | sqlstr) + " = 'probability_signal' OR NOT EXISTS (" +
    "SELECT 1 FROM records WHERE source = " + ($source | sqlstr) +
    " AND record_type = " + ($record_type | sqlstr) +
    " AND (" +
      "(" + ($external_id | sqlstr) + " IS NOT NULL AND json_extract(raw_json, '$.external_id') = " + ($external_id | sqlstr) + ")" +
      " OR (" + ($external_id | sqlstr) + " IS NULL AND " + ($canonical_url | sqlstr) + " IS NOT NULL AND canonical_url = " + ($canonical_url | sqlstr) + ")" +
    "));"
JQ
)"
{
  echo "BEGIN;"
  if [[ "$INPUT" == "-" ]]; then
    jq -rc --arg source_fallback "$SOURCE_FALLBACK" "$JQ_FILTER"
  else
    jq -rc --arg source_fallback "$SOURCE_FALLBACK" "$JQ_FILTER" "$INPUT"
  fi
  echo "COMMIT;"
} > "$TMP_SQL"

sql_escape() { printf "%s" "$1" | sed "s/'/''/g"; }

ATTEMPTED_COUNT="$(grep -c '^INSERT INTO records' "$TMP_SQL" || true)"
RUN_SOURCE="${SOURCE_FALLBACK:-unknown}"
RUN_ID="$(sqlite3 "$DB_PATH" \
  "INSERT INTO ingest_runs (source) VALUES ('$(sql_escape "$RUN_SOURCE")'); SELECT last_insert_rowid();")"
BEFORE_COUNT="$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM records;")"

if sqlite3 "$DB_PATH" < "$TMP_SQL"; then
  AFTER_COUNT="$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM records;")"
  RECORD_COUNT=$((AFTER_COUNT - BEFORE_COUNT))
  sqlite3 "$DB_PATH" \
    "UPDATE ingest_runs SET finished_at = CURRENT_TIMESTAMP, records_inserted = $RECORD_COUNT, status = 'ok', message = 'attempted $ATTEMPTED_COUNT' WHERE id = $RUN_ID;"
  echo "[$(date -u +%FT%TZ)] ingested $RECORD_COUNT/$ATTEMPTED_COUNT records from $RUN_SOURCE (run $RUN_ID)" >&2
else
  status=$?
  sqlite3 "$DB_PATH" \
    "UPDATE ingest_runs SET finished_at = CURRENT_TIMESTAMP, status = 'error', message = 'sqlite import failed' WHERE id = $RUN_ID;"
  echo "[$(date -u +%FT%TZ)] ingest failed for $RUN_SOURCE (run $RUN_ID)" >&2
  exit "$status"
fi
