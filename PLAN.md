# Media Hub Plan

Working name: **media-hub**. Despite the name, the initial product is a personal news/signal hub that collects RSS/document sources, Bluesky social signal, and Polymarket probability signal into a local queryable store for Pi and CLI workflows.

## Goals

- Build a local-first intelligence feed for topics I care about.
- Keep source adapters isolated enough that dependencies do not fight each other.
- Prefer short-lived batch workers over always-on services at first.
- Make outputs portable and inspectable via JSONL.
- Store normalized data in SQLite initially.
- Expose useful CLI queries first; Pi extension/tools can come later.

## Non-goals for MVP

- No distributed microservice system yet.
- No persistent queue/Redis/Postgres unless SQLite becomes limiting.
- No fully automated ranking/summarization pipeline on day one.
- No broad firehose ingestion from every possible source.
- No complex UI initially.

## Mental model

```text
source workers -> JSONL artifacts -> hub ingest -> SQLite -> CLI/Pi queries
```

Source workers are short-lived commands:

```bash
media-hub-rss fetch --config config/feeds.yaml --out data/inbox/rss.jsonl
media-hub-bluesky fetch --config config/bluesky.yaml --out data/inbox/bluesky.jsonl
media-hub-polymarket fetch --config config/polymarket.yaml --out data/inbox/polymarket.jsonl
media-hub ingest data/inbox/*.jsonl
media-hub digest --since 24h --topic cybersecurity
```

Containers may be used for workers with annoying dependencies, but the first orchestration layer should be `just`/shell commands, not compose.

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

```json
{
  "schema_version": 1,
  "record_type": "feed_item | document | social_post | probability_signal",
  "source": "hacker-news-rss",
  "source_type": "rss | bluesky | polymarket",
  "fetched_at": "2026-05-29T00:00:00Z",
  "raw": {}
}
```

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

Start simple:

```text
sources
feed_items
documents
social_posts
probability_signals
url_mentions
```

Later:

```text
stories
story_items
summaries
topics
embeddings
```

Important early design: canonicalize URLs so RSS, Bluesky, and HN mentions can join on the same document/story.

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
  hub/
    schema.sql
    ingest.py
    cli.py
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
```

Language choice is still open. A pragmatic default:

- Python for hub + RSS/article extraction because `trafilatura` is good.
- Node/TypeScript for Bluesky if the AT Protocol SDK is useful.
- Python or TypeScript for Polymarket depending on API/library comfort.

Use JSONL as the boundary so language choices can differ.

## MVP sequence

### Phase 0: Repo skeleton

- Add README, plan, gitignore, justfile.
- Define JSONL schemas at a lightweight/documentation level.
- Add SQLite schema.

### Phase 1: RSS worker + ingest

- Configure a few RSS feeds:
  - Hacker News official RSS
  - Slashdot
  - maybe 2–3 blogs/news feeds
- Fetch feed items to JSONL.
- Ingest feed items into SQLite.
- Add basic CLI:
  - `media-hub ingest ...`
  - `media-hub items --since 24h`
  - `media-hub search QUERY`

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

1. Should the hub CLI be Python, TypeScript, or something else?
2. Should the initial worker output schema be strict JSON Schema or just documented JSONL examples?
3. Where should local data live by default?
   - repo-local `data/`
   - `~/.local/share/media-hub/`
4. How aggressive should article fetching be?
   - all feed links
   - only selected feeds
   - only links above a score/comment threshold
5. How should topics be represented initially?
   - manual config tags per source
   - keyword rules
   - later LLM classification
6. Should containers be implemented immediately, or after the first local worker works?

## Near-term decision to make

Before implementation, decide the initial stack:

```text
Option A: Python-first
  hub + rss worker in Python; add TS only when Bluesky arrives.

Option B: TypeScript-first
  hub + workers in TS; use Readability/jsdom for article extraction.

Option C: Polyglot from day one
  hub in Python, Bluesky in TS, Polymarket TBD, all joined by JSONL.
```

My current lean: **Option A** for fastest useful MVP, with JSONL boundaries preserving future polyglot/container flexibility.
