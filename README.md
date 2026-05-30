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

## Development setup

Create repo-local configs from examples:

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

Run one debug tick, retaining JSONL/logs under `~/.local/share/media-hub/runs/<timestamp>/` by default:

```bash
./scripts/debug-tick.sh
```

Inspect data:

```bash
./scripts/items.sh --limit 20
./scripts/search.sh "cybersecurity"
```

## Local install

Install runtime scripts to `~/.local`, copy configs to `~/.config/media-hub`, initialize `~/.local/share/media-hub/media-hub.sqlite`, and build local worker images:

```bash
./scripts/install.sh
```

Installed commands:

```bash
media-hub-tick
media-hub-debug-tick
media-hub-items --limit 20
media-hub-search "cybersecurity"
```

The installed runtime is independent of the development checkout, so cron/systemd can point at:

```bash
~/.local/bin/media-hub-tick
```

Use `./scripts/install.sh --no-build` to install scripts/config without rebuilding images.

Install and enable an hourly systemd user timer:

```bash
./scripts/install.sh --install-systemd
```

Customize the schedule:

```bash
./scripts/install.sh --install-systemd --on-calendar 'hourly'
./scripts/install.sh --install-systemd --on-calendar '*:0/30'
```

Useful systemd commands:

```bash
systemctl --user status media-hub.timer
systemctl --user list-timers media-hub.timer
journalctl --user -u media-hub.service
```

## Runtime requirements

Host tools:

- `bash`
- `jq`
- `sqlite3`
- `podman` or `docker`

Set `CONTAINER_RUNTIME=docker` to use Docker instead of Podman. The scripts use Podman-compatible `:z` volume labels for Fedora/SELinux.

## Data and config

Development fallbacks:

- `config/*.local.yaml` is ignored by git.
- Example configs are safe to commit.

Installed defaults:

- Config: `~/.config/media-hub/*.yaml`
- SQLite: `~/.local/share/media-hub/media-hub.sqlite`
- Debug runs: `~/.local/share/media-hub/runs/`

Environment overrides:

- `MEDIA_HUB_CONFIG_DIR`
- `MEDIA_HUB_DATA_DIR`
- `MEDIA_HUB_DB`
- `MEDIA_HUB_IMAGE_PREFIX`

## GitHub-hosted images

GitHub Actions publishes worker images to GitHub Container Registry on pushes to `main`:

```text
ghcr.io/thiennamdinh/media-hub-rss:latest
ghcr.io/thiennamdinh/media-hub-bluesky:latest
ghcr.io/thiennamdinh/media-hub-polymarket:latest
```

For local development, `scripts/install.sh` builds local images named:

```text
media-hub-rss
media-hub-bluesky
media-hub-polymarket
```

To run against GHCR-published images instead, set:

```bash
export MEDIA_HUB_IMAGE_PREFIX=ghcr.io/thiennamdinh/media-hub
```

Then `media-hub-tick` will use:

```text
ghcr.io/thiennamdinh/media-hub-rss
ghcr.io/thiennamdinh/media-hub-bluesky
ghcr.io/thiennamdinh/media-hub-polymarket
```
