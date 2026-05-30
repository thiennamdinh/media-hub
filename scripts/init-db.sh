#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="${MEDIA_HUB_DB:-$ROOT_DIR/data/media-hub.sqlite}"
SCHEMA_PATH="$ROOT_DIR/db/schema.sql"

mkdir -p "$(dirname "$DB_PATH")"
sqlite3 "$DB_PATH" < "$SCHEMA_PATH"
echo "Initialized $DB_PATH" >&2
