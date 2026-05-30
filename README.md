# media-hub

Local-first news/signal hub for RSS/document sources, Bluesky social signal, and Polymarket probability signal.

The v0 architecture is intentionally simple:

```text
shell control scripts
  -> short-lived worker containers
  -> JSONL on stdout
  -> shell/jq/sqlite3 ingest
  -> SQLite records table
```

There is no daemon or central service. Workers know source-specific details; ingest only stores normalized records.

## Components

- `workers/rss` — Python RSS worker using `feedparser`, `httpx`, and `PyYAML`.
- `workers/bluesky` — TypeScript Bluesky worker using `@atproto/api`.
- `workers/polymarket` — Python Polymarket worker using public HTTP APIs.
- `scripts/*.sh` — build, tick, ingest, and query helpers.
- `db/schema.sql` — SQLite schema.
- `config/*.example.yaml` — example non-secret worker configs.

## Worker contract

Workers emit newline-delimited JSON to stdout and logs/errors to stderr.

Required fields:

```json
{
  "schema_version": 1,
  "source": "hacker-news",
  "source_type": "rss",
  "record_type": "feed_item",
  "observed_at": "2026-05-29T00:00:00Z"
}
```

Optional common fields:

```json
{
  "title": "Example title",
  "url": "https://example.com/article",
  "canonical_url": "https://example.com/article",
  "published_at": "2026-05-28T23:00:00Z",
  "external_id": "source-specific-id"
}
```

## Setup

Create local configs from examples:

```bash
mkdir -p config
cp config/rss.example.yaml config/rss.local.yaml
cp config/bluesky.example.yaml config/bluesky.local.yaml
cp config/polymarket.example.yaml config/polymarket.local.yaml
```

Initialize SQLite:

```bash
./scripts/init-db.sh
```

Build worker images with Podman:

```bash
./scripts/build.sh
```

Run one normal tick:

```bash
./scripts/tick.sh
```

Run one debug tick, retaining JSONL/logs under `data/runs/<timestamp>/`:

```bash
./scripts/debug-tick.sh
```

Inspect data:

```bash
./scripts/items.sh --limit 20
./scripts/search.sh "cybersecurity"
```

## Runtime requirements

Host tools:

- `bash`
- `jq`
- `sqlite3`
- `podman` or `docker`

Set `CONTAINER_RUNTIME=docker` to use Docker instead of Podman. The scripts use Podman-compatible `:z` volume labels for Fedora/SELinux.

## Data and config

- SQLite defaults to `data/media-hub.sqlite`.
- `data/` is ignored by git.
- `config/*.local.yaml` is ignored by git.
- Example configs are safe to commit.
