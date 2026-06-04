from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from typing import Any

import httpx
import yaml

GAMMA_BASE = "https://gamma-api.polymarket.com"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_config(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise SystemExit("config must be a YAML mapping")
    return data


def emit(record: dict[str, Any]) -> None:
    print(json.dumps(record, ensure_ascii=False, separators=(",", ":")), flush=True)


def first_float(*values: Any) -> float | None:
    for value in values:
        if value is None:
            continue
        if isinstance(value, list) and value:
            value = value[0]
        try:
            return float(value)
        except Exception:
            continue
    return None


def market_url(market: dict[str, Any]) -> str | None:
    slug = market.get("slug")
    if not slug:
        return market.get("url")

    events = market.get("events")
    if isinstance(events, list) and events:
        event = events[0]
        if isinstance(event, dict) and event.get("slug"):
            return f"https://polymarket.com/event/{event['slug']}/{slug}"

    return f"https://polymarket.com/event/{slug}"


def normalize_market(market: dict[str, Any], *, tags: list[str] | None = None, observed_at: str) -> dict[str, Any]:
    question = market.get("question") or market.get("title") or market.get("description")
    url = market_url(market)
    market_id = str(market.get("id") or market.get("conditionId") or market.get("slug") or question)
    probability = first_float(
        market.get("probability"),
        market.get("lastTradePrice"),
        market.get("bestAsk"),
        market.get("outcomePrices"),
    )
    return {
        "schema_version": 1,
        "source": "polymarket",
        "source_type": "polymarket",
        "record_type": "probability_signal",
        "observed_at": observed_at,
        "title": question,
        "url": url,
        "canonical_url": url,
        "external_id": market_id,
        "market_id": market_id,
        "slug": market.get("slug"),
        "question": question,
        "probability": probability,
        "volume": first_float(market.get("volume"), market.get("volumeNum")),
        "liquidity": first_float(market.get("liquidity"), market.get("liquidityNum")),
        "end_date": market.get("endDate") or market.get("end_date_iso"),
        "tags": tags or [],
    }


def get_markets(client: httpx.Client, params: dict[str, Any]) -> list[dict[str, Any]]:
    response = client.get(f"{GAMMA_BASE}/markets", params=params)
    response.raise_for_status()
    data = response.json()
    if isinstance(data, list):
        return [x for x in data if isinstance(x, dict)]
    if isinstance(data, dict):
        candidates = data.get("markets") or data.get("data") or []
        if isinstance(candidates, list):
            return [x for x in candidates if isinstance(x, dict)]
    return []


def cmd_fetch(args: argparse.Namespace) -> int:
    config = load_config(args.config)
    observed_at = now_iso()
    with httpx.Client(timeout=args.timeout, follow_redirects=True, headers={"User-Agent": "media-hub-polymarket/0.1"}) as client:
        for item in config.get("markets") or []:
            if not isinstance(item, dict):
                continue
            tags = item.get("tags") or []
            params: dict[str, Any] = {"limit": 1}
            if item.get("slug"):
                params["slug"] = item["slug"]
            elif item.get("id"):
                params["id"] = item["id"]
            else:
                continue
            try:
                for market in get_markets(client, params):
                    emit({k: v for k, v in normalize_market(market, tags=tags, observed_at=observed_at).items() if v is not None})
            except Exception as exc:
                print(f"error fetching market {item}: {exc}", file=sys.stderr)
                if args.fail_fast:
                    raise

        for top in config.get("top_markets") or []:
            if not isinstance(top, dict):
                continue
            tags = top.get("tags") or []
            metric = top.get("metric") or "volumeNum"
            limit = int(top.get("limit") or args.limit)
            params = {
                "active": str(top.get("active", True)).lower(),
                "closed": str(top.get("closed", False)).lower(),
                "order": metric,
                "ascending": str(top.get("ascending", False)).lower(),
                "limit": limit,
            }
            try:
                for market in get_markets(client, params):
                    emit({k: v for k, v in normalize_market(market, tags=tags, observed_at=observed_at).items() if v is not None})
            except Exception as exc:
                print(f"error fetching top markets by {metric}: {exc}", file=sys.stderr)
                if args.fail_fast:
                    raise

        for search in config.get("searches") or []:
            if not isinstance(search, dict) or not search.get("query"):
                continue
            tags = search.get("tags") or []
            params = {"search": search["query"], "limit": int(search.get("limit") or args.limit)}
            try:
                for market in get_markets(client, params):
                    emit({k: v for k, v in normalize_market(market, tags=tags, observed_at=observed_at).items() if v is not None})
            except Exception as exc:
                print(f"error searching markets {search.get('query')}: {exc}", file=sys.stderr)
                if args.fail_fast:
                    raise

        for category in config.get("categories") or []:
            params = {"category": category, "limit": args.limit}
            try:
                for market in get_markets(client, params):
                    emit({k: v for k, v in normalize_market(market, tags=[str(category)], observed_at=observed_at).items() if v is not None})
            except Exception as exc:
                print(f"error fetching category {category}: {exc}", file=sys.stderr)
                if args.fail_fast:
                    raise
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="media-hub-polymarket")
    sub = parser.add_subparsers(dest="command", required=True)

    fetch = sub.add_parser("fetch")
    fetch.add_argument("--config", required=True)
    fetch.add_argument("--timeout", type=float, default=20.0)
    fetch.add_argument("--limit", type=int, default=25)
    fetch.add_argument("--fail-fast", action="store_true")
    fetch.set_defaults(func=cmd_fetch)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
