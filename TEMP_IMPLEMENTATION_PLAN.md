# Temporary Staged Implementation Plan

This is a working checklist for the initial one-shot scaffold. It is intentionally temporary and can be deleted once the repo has a stable README/plan.

## Stage 1: Repository skeleton

- [x] Add `.gitignore` for local data/config artifacts.
- [x] Add `README.md` with architecture and quickstart.
- [x] Add `config/*.example.yaml` for RSS, Bluesky, and Polymarket.
- [x] Add JSON schema documentation for the common worker record envelope.

## Stage 2: SQLite + shell ingest/query scripts

- [x] Add `db/schema.sql` with the flexible `records` table.
- [x] Add `scripts/init-db.sh`.
- [x] Add `scripts/ingest.sh` using `jq` + `sqlite3`.
- [x] Add `scripts/items.sh` and `scripts/search.sh` for basic inspection.

## Stage 3: Control scripts

- [x] Add `scripts/build.sh` for Podman/Docker-compatible image builds.
- [x] Add `scripts/tick.sh` to stream all worker outputs directly into ingest.
- [x] Add `scripts/debug-tick.sh` to tee worker outputs/logs into `data/runs/<run-id>/`.

## Stage 4: Worker containers

- [x] Add RSS worker: Python + `feedparser` + `httpx` + `PyYAML`.
- [x] Add Bluesky worker: TypeScript + `@atproto/api` + `yaml`.
- [x] Add Polymarket worker: Python + `httpx` + `PyYAML`.
- [x] Ensure all workers emit JSONL to stdout and logs/errors to stderr.

## Stage 5: Checks run

- [x] Shell syntax: `bash -n scripts/*.sh`.
- [x] Python syntax: `python3 -m py_compile ...`.
- [x] Bluesky TypeScript build: `npm run build`.
- [x] Container builds: `./scripts/build.sh`.
- [x] RSS worker fetch sample via Podman.
- [x] Bluesky worker empty-config sample via Podman.
- [x] Polymarket explicit-market sample via Podman.
- [x] SQLite init/ingest/items/search scripts.
- [x] End-to-end `scripts/tick.sh` with example configs.
- [x] End-to-end `scripts/debug-tick.sh` with retained debug artifacts.

## Notes

- `sqlite3` was installed after initial scaffold and ingest/query scripts now run.
- Bluesky public search may return `Forbidden` without auth depending on AppView; example config leaves searches commented out.
- Polymarket broad search/category behavior is not reliable enough for a default example; example config starts with explicit markets commented out.
