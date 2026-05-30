#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${MEDIA_HUB_DATA_DIR:-$HOME/.local/share/media-hub}"
DB_PATH="${MEDIA_HUB_DB:-$DATA_DIR/media-hub.sqlite}"
SCHEMA_PATH="${MEDIA_HUB_SCHEMA:-$ROOT_DIR/db/schema.sql}"

mkdir -p "$(dirname "$DB_PATH")"
sqlite3 "$DB_PATH" < "$SCHEMA_PATH"
echo "Initialized $DB_PATH" >&2
