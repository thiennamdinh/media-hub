# RSS worker

Fetches configured RSS/Atom feeds and emits `feed_item` JSONL records to stdout.

```bash
media-hub-rss fetch --config /config/rss.yaml
```

Dependencies are installed inside the worker container:

- `feedparser`
- `httpx`
- `PyYAML`

The worker performs source-specific normalization, including basic URL canonicalization and feed timestamp parsing.
