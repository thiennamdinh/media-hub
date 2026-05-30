from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import feedparser
import httpx
import yaml

TRACKING_PARAMS = {
    "fbclid",
    "gclid",
    "igshid",
    "mc_cid",
    "mc_eid",
    "mkt_tok",
    "utm_campaign",
    "utm_content",
    "utm_medium",
    "utm_source",
    "utm_term",
}


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def iso_from_feed_time(value: Any) -> str | None:
    if not value:
        return None
    if isinstance(value, str):
        try:
            dt = parsedate_to_datetime(value)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        except Exception:
            return value
    return None


def canonicalize_url(url: str | None) -> str | None:
    if not url:
        return None
    parts = urlsplit(url.strip())
    scheme = (parts.scheme or "https").lower()
    netloc = parts.netloc.lower()
    query = urlencode(
        [(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True) if k.lower() not in TRACKING_PARAMS],
        doseq=True,
    )
    path = parts.path or "/"
    if path != "/":
        path = path.rstrip("/")
    return urlunsplit((scheme, netloc, path, query, ""))


def load_config(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise SystemExit("config must be a YAML mapping")
    return data


def emit(record: dict[str, Any]) -> None:
    print(json.dumps(record, ensure_ascii=False, separators=(",", ":")), flush=True)


def fetch_feed(client: httpx.Client, feed: dict[str, Any]) -> None:
    feed_url = feed["url"]
    feed_name = feed.get("name") or feed_url
    source = feed.get("source") or feed_name.lower().replace(" ", "-")
    tags = feed.get("tags") or []

    print(f"fetching feed {feed_name} ({feed_url})", file=sys.stderr)
    response = client.get(feed_url)
    response.raise_for_status()
    parsed = feedparser.parse(response.content)
    observed_at = now_iso()

    for entry in parsed.entries:
        url = entry.get("link")
        title = entry.get("title")
        published_at = iso_from_feed_time(entry.get("published") or entry.get("updated"))
        record = {
            "schema_version": 1,
            "source": source,
            "source_type": "rss",
            "record_type": "feed_item",
            "observed_at": observed_at,
            "title": title,
            "url": url,
            "canonical_url": canonicalize_url(url),
            "published_at": published_at,
            "external_id": entry.get("id") or entry.get("guid") or url,
            "feed_name": feed_name,
            "feed_url": feed_url,
            "summary": entry.get("summary"),
            "comments_url": entry.get("comments"),
            "tags": tags,
        }
        emit({k: v for k, v in record.items() if v is not None})


def cmd_fetch(args: argparse.Namespace) -> int:
    config = load_config(args.config)
    feeds = config.get("feeds") or []
    if not isinstance(feeds, list):
        raise SystemExit("config field 'feeds' must be a list")

    with httpx.Client(timeout=args.timeout, follow_redirects=True, headers={"User-Agent": "media-hub-rss/0.1"}) as client:
        for feed in feeds:
            if not isinstance(feed, dict) or not feed.get("url"):
                print("skipping invalid feed entry", file=sys.stderr)
                continue
            try:
                fetch_feed(client, feed)
            except Exception as exc:
                print(f"error fetching {feed.get('name') or feed.get('url')}: {exc}", file=sys.stderr)
                if args.fail_fast:
                    raise
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="media-hub-rss")
    sub = parser.add_subparsers(dest="command", required=True)

    fetch = sub.add_parser("fetch")
    fetch.add_argument("--config", required=True)
    fetch.add_argument("--timeout", type=float, default=20.0)
    fetch.add_argument("--fail-fast", action="store_true")
    fetch.set_defaults(func=cmd_fetch)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
