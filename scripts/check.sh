#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "== shell syntax =="
bash -n "$ROOT_DIR"/scripts/*.sh

echo "== python syntax =="
python3 -m py_compile \
  "$ROOT_DIR"/workers/rss/media_hub_rss/cli.py \
  "$ROOT_DIR"/workers/mastodon/media_hub_mastodon/cli.py \
  "$ROOT_DIR"/workers/polymarket/media_hub_polymarket/cli.py

if [[ -d "$ROOT_DIR/workers/bluesky/node_modules" ]]; then
  echo "== bluesky typescript build =="
  (cd "$ROOT_DIR/workers/bluesky" && npm run build)
else
  echo "== bluesky typescript build skipped (node_modules missing) =="
fi

echo "== sqlite schema + ingest/query smoke =="
DB="$TMP_DIR/media-hub.sqlite"
MEDIA_HUB_DB="$DB" "$ROOT_DIR/scripts/init-db.sh" >/dev/null
cat > "$TMP_DIR/sample.jsonl" <<'JSONL'
{"schema_version":1,"source":"test","source_type":"rss","record_type":"feed_item","observed_at":"2026-05-30T00:00:00Z","title":"Example","canonical_url":"https://example.com/a","external_id":"a"}
{"schema_version":1,"source":"test","source_type":"rss","record_type":"feed_item","observed_at":"2026-05-30T01:00:00Z","title":"Example duplicate","canonical_url":"https://example.com/a","external_id":"a"}
{"schema_version":1,"source":"mastodon-account:example@mastodon.social","source_type":"mastodon","record_type":"social_post","observed_at":"2026-05-30T00:00:00Z","title":"Post","canonical_url":"https://example.com/b","external_id":"mastodon:1","network":"mastodon"}
{"schema_version":1,"source":"polymarket","source_type":"polymarket","record_type":"probability_signal","observed_at":"2026-05-30T00:00:00Z","title":"Market","canonical_url":"https://polymarket.com/event/x","market_id":"x","probability":0.4}
{"schema_version":1,"source":"polymarket","source_type":"polymarket","record_type":"probability_signal","observed_at":"2026-05-30T01:00:00Z","title":"Market","canonical_url":"https://polymarket.com/event/x","market_id":"x","probability":0.5}
JSONL
MEDIA_HUB_DB="$DB" "$ROOT_DIR/scripts/ingest.sh" --source smoke "$TMP_DIR/sample.jsonl" >/dev/null
count="$(sqlite3 "$DB" 'SELECT COUNT(*) FROM records;')"
if [[ "$count" != "4" ]]; then
  echo "error: expected 4 records after dedupe/snapshot ingest, got $count" >&2
  exit 1
fi
MEDIA_HUB_DB="$DB" "$ROOT_DIR/scripts/items.sh" --limit 2 >/dev/null
MEDIA_HUB_DB="$DB" "$ROOT_DIR/scripts/search.sh" Example --limit 1 >/dev/null
MEDIA_HUB_DB="$DB" "$ROOT_DIR/scripts/links.sh" --min-sources 1 --limit 1 >/dev/null
MEDIA_HUB_DB="$DB" "$ROOT_DIR/scripts/markets.sh" --since 7d --moved --limit 1 >/dev/null
MEDIA_HUB_DB="$DB" "$ROOT_DIR/scripts/digest.sh" --since 7d --limit 2 >/dev/null

echo "ok"
