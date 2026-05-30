# Polymarket worker

Fetches configured Polymarket markets/searches/categories and emits `probability_signal` JSONL records to stdout.

```bash
media-hub-polymarket fetch --config /config/polymarket.yaml
```

Dependencies are installed inside the worker container:

- `httpx`
- `PyYAML`

The v0 worker uses public read-only Polymarket/Gamma HTTP APIs.
