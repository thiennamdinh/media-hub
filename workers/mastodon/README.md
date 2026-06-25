# Mastodon worker

Fetches configured Mastodon/ActivityPub accounts, hashtag timelines, and public timelines and emits `social_post` JSONL records to stdout.

```bash
media-hub-mastodon fetch --config /config/mastodon.yaml
```

The worker is read-only. It defaults to public unauthenticated API reads. Optional per-instance access tokens can be supplied by setting `token_env` on an instance in config and exporting that environment variable on the host/container.

Mastodon discovery is instance-mediated: account fetches use the account's home instance by default, while hashtag and public timelines use the configured instance's view of the fediverse. Treat instances as curated signal sources, not global search backends.
