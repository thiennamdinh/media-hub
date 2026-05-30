# Bluesky worker

Fetches configured Bluesky searches, actors, and feeds and emits `social_post` JSONL records to stdout.

```bash
node dist/index.js fetch --config /config/bluesky.yaml
```

Container dependencies:

- `@atproto/api`
- `yaml`

The worker defaults to public unauthenticated reads via `https://public.api.bsky.app`. Optional auth can be provided later with:

```text
BLUESKY_IDENTIFIER
BLUESKY_APP_PASSWORD
```
