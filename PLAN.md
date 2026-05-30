# Media Hub Plan

Working name: **media-hub**. The initial product is a personal news/signal hub that collects RSS/document sources, Bluesky social signal, and Polymarket probability signal into a local queryable store for Pi and CLI workflows.

## Goals

- Build a local-first intelligence feed for topics I care about.
- Keep source adapters isolated enough that dependencies do not fight each other.
- Prefer short-lived batch workers over always-on services at first.
- Make worker output portable and inspectable via JSONL on stdout.
- Stream worker output into SQLite as the canonical durable store.
- Expose useful CLI queries first; Pi extension/tools can come later.

## Non-goals for MVP

- No distributed microservice system yet.
- No persistent queue/Redis/Postgres unless SQLite becomes limiting.
- No fully automated ranking/summarization pipeline on day one.
- No broad firehose ingestion from every possible source.
- No complex UI initially.

## Mental model

```text
source workers -> JSONL on stdout -> hub ingest -> SQLite -> CLI/Pi queries
```

Source workers are short-lived container commands. They emit newline-delimited JSON to stdout and logs/errors to stderr. The control layer streams worker stdout directly into the hub ingest command; saving JSONL files is optional debug/replay behavior, not the normal durable store.

Normal mode:

```bash
podman run --rm media-hub-rss fetch \
  | media-hub ingest --source rss -

podman run --rm media-hub-bluesky fetch \
  | media-hub ingest --source bluesky -

podman run --rm media-hub-polymarket fetch \
  | media-hub ingest --source polymarket -
```

Debug/replay mode may tee worker output into a run directory:

```bash
podman run --rm media-hub-rss fetch \
  | tee data/runs/$RUN_ID/rss.jsonl \
  | media-hub ingest --source rss -
```

SQLite is the canonical durable store. JSONL is the worker interchange format and may be retained temporarily for debugging.

The first orchestration layer should be plain shell scripts, not compose.

## Source categories

### 1. RSS / document sources

Catchall for traditional documents and feed-like sources:

- Hacker News RSS
- Slashdot RSS
- blogs
- arXiv feeds
- security advisories
- newsletters/Substack feeds where available

Two stages:

1. Fetch feed items.
2. Optionally fetch/extract the linked article text.

Keep feed mentions separate from fetched documents because multiple sources can point at the same URL.

### 2. Bluesky / social sources

Social/discussion signal:

- selected feeds
- selected lists
- trusted actors
- keyword searches

Main value is not raw posts, but early discussion, link discovery, and who is talking about what.

### 3. Polymarket / probability sources

Quantitative belief signal:

- market question
- probability / price
- volume/liquidity
- movement over time
- topic/category

Treat markets as signals attached to stories/topics, not as normal documents.

## Initial data model sketch

Use a normalized event/item envelope in JSONL so every worker can emit records independently.

### Common envelope

Every worker emits newline-delimited JSON records. The ingest layer only depends on this minimal envelope.

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

Optional-but-standard fields:

```json
{
  "title": "Example title",
  "url": "https://example.com/article",
  "canonical_url": "https://example.com/article",
  "published_at": "2026-05-28T23:00:00Z",
  "external_id": "source-specific-id"
}
```

Source-specific fields can live alongside the envelope fields. For example: `feed_url`, `summary`, `comments_url`, `author_handle`, `probability`, `volume`, etc.

The ingest script maps only these fields into SQLite columns:

```text
source        <- .source
record_type   <- .record_type
canonical_url <- .canonical_url // null
observed_at   <- .observed_at
title         <- .title // null
raw_json      <- full object
```

Workers own source-specific parsing and normalization; ingest is deliberately dumb.

### Feed item

```json
{
  "record_type": "feed_item",
  "title": "Article title",
  "url": "https://example.com/article",
  "canonical_url": "https://example.com/article",
  "feed_url": "https://news.ycombinator.com/rss",
  "feed_name": "Hacker News",
  "published_at": "2026-05-29T00:00:00Z",
  "summary": "Feed summary",
  "comments_url": "https://news.ycombinator.com/item?id=...",
  "guid": "..."
}
```

### Document

```json
{
  "record_type": "document",
  "url": "https://example.com/article",
  "canonical_url": "https://example.com/article",
  "title": "Article title",
  "author": "Author",
  "site_name": "Example",
  "published_at": "2026-05-29T00:00:00Z",
  "text": "Extracted readable article text"
}
```

### Social post

```json
{
  "record_type": "social_post",
  "network": "bluesky",
  "post_uri": "at://...",
  "author_handle": "example.bsky.social",
  "text": "Post text",
  "links": ["https://example.com/article"],
  "posted_at": "2026-05-29T00:00:00Z",
  "like_count": 0,
  "repost_count": 0,
  "reply_count": 0
}
```

### Probability signal

```json
{
  "record_type": "probability_signal",
  "platform": "polymarket",
  "market_id": "...",
  "question": "Will X happen by Y?",
  "url": "https://polymarket.com/event/...",
  "topic": "geopolitics",
  "probability": 0.42,
  "previous_probability": 0.38,
  "volume": 12345,
  "liquidity": 6789,
  "observed_at": "2026-05-29T00:00:00Z"
}
```

## SQLite schema sketch

Start with one flexible table:

```sql
CREATE TABLE records (
  id INTEGER PRIMARY KEY,
  source TEXT NOT NULL,
  record_type TEXT NOT NULL,
  canonical_url TEXT,
  observed_at TEXT,
  title TEXT,
  raw_json TEXT NOT NULL,
  inserted_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_records_source ON records(source);
CREATE INDEX idx_records_type ON records(record_type);
CREATE INDEX idx_records_url ON records(canonical_url);
CREATE INDEX idx_records_observed_at ON records(observed_at);
```

Rationale:

- flexible while worker formats evolve
- easy to ingest with shell + `jq` + `sqlite3`
- still exposes common query fields
- preserves full source record as JSON

Later, if needed, add specialized tables or views:

```text
feed_items
documents
social_posts
probability_signals
url_mentions
stories
story_items
summaries
topics
embeddings
```

Important early design: workers should emit `canonical_url` when a record is URL-related so RSS, Bluesky, and HN mentions can join on the same document/story. The ingest script should not implement source-specific canonicalization logic.

## Repo shape proposal

```text
media-hub/
  PLAN.md
  README.md
  justfile
  config/
    feeds.example.yaml
    bluesky.example.yaml
    polymarket.example.yaml
  schemas/
    common.schema.json
    feed-item.schema.json
    document.schema.json
    social-post.schema.json
    probability-signal.schema.json
  db/
    schema.sql
  scripts/
    tick.sh
    ingest.sh
  workers/
    rss/
      README.md
      pyproject.toml
      media_hub_rss/
    bluesky/
      README.md
    polymarket/
      README.md
  data/
    .gitkeep
    # local SQLite/runs ignored by git
```

Language choice is intentionally open and per-component.

- The control plane should start as plain shell scripts.
- Ingest/query starts as shell + `jq` + `sqlite3`.
- Workers can use whichever language/library fits the source best.
- Add Python/TypeScript only when a specific component needs it.

Use JSONL on stdout as the worker boundary so implementation choices can differ. Workers are responsible for source-specific parsing, normalization, and canonicalization. The control/ingest layer should stay mostly data-agnostic: read JSONL records, extract a few common envelope fields, and insert the full record into SQLite. Retained JSONL files are optional debug/replay artifacts.

## MVP sequence

### Phase 0: Repo skeleton

- Add README, plan, gitignore, shell scripts.
- Define JSONL schemas at a lightweight/documentation level.
- Add SQLite schema with one flexible `records` table.
- Add shell/`jq`/`sqlite3` ingest prototype.

### Phase 1: RSS worker + ingest

- Configure a few RSS feeds:
  - Hacker News official RSS
  - Slashdot
  - maybe 2–3 blogs/news feeds
- Fetch feed items as JSONL on stdout.
- Stream feed items into SQLite.
- Add basic shell commands/scripts:
  - `scripts/ingest.sh --source rss -`
  - `scripts/items.sh --since 24h`
  - `scripts/search.sh QUERY`

### Phase 2: Article extraction

- Fetch linked pages for selected feed items.
- Extract readable text.
- Store `documents` separately from `feed_items`.
- Add URL canonicalization/deduplication.

### Phase 3: Bluesky worker

- Fetch from selected public feeds/lists/actors/searches.
- Extract links from posts.
- Store posts and URL mentions.
- Join social mentions to existing documents by canonical URL.

### Phase 4: Polymarket worker

- Fetch configured markets/topics.
- Store market snapshots as probability signals.
- Track probability movement over time.
- Join markets to stories/topics manually at first, automatically later.

### Phase 5: Digest/query layer

- Add commands like:
  - `media-hub digest --since 24h`
  - `media-hub links --mentioned-by bluesky,hacker-news`
  - `media-hub markets --moved --since 24h`
- Optional LLM/Pi summarization later.

## Open questions

1. Should the initial worker output schema be strict JSON Schema or just documented JSONL examples?
2. Where should local data live by default?
   - repo-local `data/`
   - `~/.local/share/media-hub/`
3. How aggressive should article fetching be?
   - all feed links
   - only selected feeds
   - only links above a score/comment threshold
4. How should topics be represented initially?
   - manual config tags per source
   - keyword rules
   - later LLM classification

## Decisions so far

- Control plane v0: plain shell script orchestration.
- No dedicated hub service. The system is a control script plus worker containers plus SQLite.
- Ingest/query implementation is undecided; start with shell + `jq` + `sqlite3` if sufficient, and only add Python if complexity warrants it.
- Workers: containerized short-lived fetchers.
- Worker contract: JSONL to stdout, logs/errors to stderr.
- Persistence: stream worker output into SQLite; SQLite is canonical durable storage.
- Optional debug mode: tee worker JSONL into `data/runs/<run-id>/` for replay/inspection.

## Near-term decision to make

Next decision: decide the first worker to implement, likely RSS.
