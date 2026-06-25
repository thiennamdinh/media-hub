from __future__ import annotations

import argparse
import html
import json
import os
import re
import sys
from datetime import datetime, timezone
from html.parser import HTMLParser
from typing import Any
from urllib.parse import parse_qsl, quote, urlencode, urlsplit, urlunsplit

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


class ContentExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in {"br", "p", "div", "li"}:
            self.parts.append(" ")
        if tag == "a":
            attr_map = dict(attrs)
            href = attr_map.get("href")
            classes = set((attr_map.get("class") or "").split())
            rels = set((attr_map.get("rel") or "").split())
            # Mastodon renders hashtags and mentions as links in status content;
            # keep outbound/article links, not federation UI links used as text markup.
            if href and not ({"mention", "hashtag"} & classes) and "tag" not in rels:
                self.links.append(href)

    def handle_data(self, data: str) -> None:
        self.parts.append(data)

    def text(self) -> str:
        return re.sub(r"\s+", " ", "".join(self.parts)).strip()


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def canonicalize_url(url: str | None) -> str | None:
    if not url:
        return None
    try:
        parts = urlsplit(html.unescape(url.strip()))
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
    except Exception:
        return url


def load_config(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise SystemExit("config must be a YAML mapping")
    return data


def emit(record: dict[str, Any]) -> None:
    print(json.dumps(record, ensure_ascii=False, separators=(",", ":")), flush=True)


def compact(record: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in record.items() if v is not None and v != [] and v != {}}


def instance_key(value: str) -> str:
    value = value.strip()
    if value.startswith("http://") or value.startswith("https://"):
        return (urlsplit(value).netloc or value).lower()
    return value.lower().rstrip("/")


def base_url(value: str) -> str:
    value = value.strip().rstrip("/")
    if not value.startswith(("http://", "https://")):
        value = f"https://{value}"
    return value


def acct_domain(acct: str) -> str | None:
    acct = acct.strip().lstrip("@")
    if "@" not in acct:
        return None
    return acct.rsplit("@", 1)[1].lower()


def full_acct(account: dict[str, Any], instance_host: str) -> str | None:
    acct = account.get("acct") or account.get("username")
    if not isinstance(acct, str) or not acct:
        return None
    if "@" in acct:
        return acct.lstrip("@")
    return f"{acct}@{instance_host}"


def parse_content(content: str | None) -> tuple[str | None, list[str]]:
    if not content:
        return None, []
    parser = ContentExtractor()
    parser.feed(content)
    text = parser.text()
    links = [canonicalize_url(link) for link in parser.links]
    return text or None, [link for link in dict.fromkeys(links) if link]


def links_from_status(status: dict[str, Any]) -> list[str]:
    _, content_links = parse_content(status.get("content"))
    links: list[str] = list(content_links)
    card = status.get("card")
    if isinstance(card, dict) and card.get("url"):
        links.append(canonicalize_url(card.get("url")))
    return [link for link in dict.fromkeys(links) if link]


def normalize_status(status: dict[str, Any], *, source: str, source_tags: list[str], observed_at: str, instance: str) -> dict[str, Any]:
    target = status.get("reblog") if isinstance(status.get("reblog"), dict) else status
    is_reblog = target is not status
    account = status.get("account") if isinstance(status.get("account"), dict) else {}
    target_account = target.get("account") if isinstance(target.get("account"), dict) else {}
    text, _ = parse_content(target.get("content"))
    links = links_from_status(target)
    status_url = status.get("url") or target.get("url") or status.get("uri") or target.get("uri")
    post_tags = [tag.get("name") for tag in target.get("tags") or [] if isinstance(tag, dict) and tag.get("name")]
    external_id = status.get("uri") or f"{instance}:{status.get('id')}"

    return compact(
        {
            "schema_version": 1,
            "source": source,
            "source_type": "mastodon",
            "record_type": "social_post",
            "observed_at": observed_at,
            "title": text[:120] if text else target.get("spoiler_text") or status_url,
            "url": status_url,
            "canonical_url": links[0] if len(links) == 1 else None,
            "published_at": status.get("created_at") or target.get("created_at"),
            "external_id": external_id,
            "network": "mastodon",
            "instance": instance,
            "post_uri": status.get("uri"),
            "target_post_uri": target.get("uri") if is_reblog else None,
            "status_id": status.get("id"),
            "target_status_id": target.get("id") if is_reblog else None,
            "author_handle": full_acct(account, instance),
            "author_id": account.get("id"),
            "author_url": account.get("url"),
            "target_author_handle": full_acct(target_account, instance) if is_reblog else None,
            "target_author_id": target_account.get("id") if is_reblog else None,
            "target_author_url": target_account.get("url") if is_reblog else None,
            "text": text,
            "spoiler_text": target.get("spoiler_text") or None,
            "links": links,
            "language": target.get("language") or status.get("language"),
            "visibility": target.get("visibility") or status.get("visibility"),
            "sensitive": target.get("sensitive") or status.get("sensitive"),
            "is_reblog": is_reblog,
            "is_reply": bool(target.get("in_reply_to_id")),
            "reply_count": target.get("replies_count"),
            "repost_count": target.get("reblogs_count"),
            "like_count": target.get("favourites_count"),
            "post_tags": post_tags,
            "tags": source_tags,
        }
    )


class MastodonClient:
    def __init__(self, timeout: float) -> None:
        self.timeout = timeout
        self.clients: dict[str, httpx.Client] = {}

    def close(self) -> None:
        for client in self.clients.values():
            client.close()

    def client_for(self, instance: str, token_env: str | None = None) -> httpx.Client:
        root = base_url(instance)
        token = os.environ.get(token_env) if token_env else None
        key = f"{root}|{token_env or ''}"
        if key not in self.clients:
            headers = {
                "Accept": "application/json",
                "User-Agent": "media-hub-mastodon/0.1 (+https://github.com/thiennamdinh/media-hub)",
            }
            if token:
                headers["Authorization"] = f"Bearer {token}"
            self.clients[key] = httpx.Client(base_url=root, timeout=self.timeout, follow_redirects=True, headers=headers)
        return self.clients[key]

    def get(self, instance: str, path: str, *, token_env: str | None = None, params: dict[str, Any] | None = None) -> Any:
        response = self.client_for(instance, token_env).get(path, params=params)
        response.raise_for_status()
        return response.json()


def instance_map(config: dict[str, Any]) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    for item in config.get("instances") or []:
        if not isinstance(item, dict):
            continue
        value = item.get("base_url") or item.get("instance") or item.get("name")
        if not value:
            continue
        entry = dict(item)
        entry["base_url"] = base_url(str(value))
        out[instance_key(str(item.get("name") or value))] = entry
        out[instance_key(str(value))] = entry
    return out


def resolve_instance(value: str | None, instances: dict[str, dict[str, Any]]) -> tuple[str, str | None]:
    if not value:
        raise ValueError("instance is required")
    entry = instances.get(instance_key(value))
    if entry:
        return entry["base_url"], entry.get("token_env")
    return base_url(value), None


def fetch_accounts(config: dict[str, Any], masto: MastodonClient, observed_at: str, instances: dict[str, dict[str, Any]], fail_fast: bool) -> None:
    for account_item in config.get("accounts") or []:
        if not isinstance(account_item, dict):
            continue
        acct = str(account_item.get("acct") or account_item.get("handle") or "").strip().lstrip("@")
        if not acct:
            continue
        instance_value = account_item.get("instance") or acct_domain(acct)
        if not instance_value:
            print(f"skipping account without instance: {acct}", file=sys.stderr)
            continue
        tags = account_item.get("tags") if isinstance(account_item.get("tags"), list) else []
        limit = int(account_item.get("limit") or 20)
        exclude_replies = bool(account_item.get("exclude_replies", True))
        exclude_reblogs = bool(account_item.get("exclude_reblogs", False))
        try:
            instance, token_env = resolve_instance(str(instance_value), instances)
            host = instance_key(instance)
            print(f"fetching Mastodon account: {acct} via {host}", file=sys.stderr)
            lookup = masto.get(instance, "/api/v1/accounts/lookup", token_env=token_env, params={"acct": acct})
            account_id = lookup.get("id")
            if not account_id:
                print(f"no account id returned for {acct} on {host}", file=sys.stderr)
                continue
            statuses = masto.get(
                instance,
                f"/api/v1/accounts/{account_id}/statuses",
                token_env=token_env,
                params={"limit": limit, "exclude_replies": str(exclude_replies).lower(), "exclude_reblogs": str(exclude_reblogs).lower()},
            )
            source = f"mastodon-account:{acct}"
            for status in statuses if isinstance(statuses, list) else []:
                if isinstance(status, dict):
                    emit(normalize_status(status, source=source, source_tags=tags, observed_at=observed_at, instance=host))
        except Exception as exc:
            print(f"error fetching Mastodon account {acct}: {exc}", file=sys.stderr)
            if fail_fast:
                raise


def fetch_tags(config: dict[str, Any], masto: MastodonClient, observed_at: str, instances: dict[str, dict[str, Any]], fail_fast: bool) -> None:
    for tag_item in config.get("tags") or []:
        if not isinstance(tag_item, dict):
            continue
        tag = str(tag_item.get("tag") or tag_item.get("name") or "").strip().lstrip("#")
        instance_value = tag_item.get("instance")
        if not tag or not instance_value:
            continue
        source_tags = tag_item.get("tags") if isinstance(tag_item.get("tags"), list) else []
        limit = int(tag_item.get("limit") or 20)
        local = bool(tag_item.get("local", False))
        only_media = bool(tag_item.get("only_media", False))
        try:
            instance, token_env = resolve_instance(str(instance_value), instances)
            host = instance_key(instance)
            print(f"fetching Mastodon tag: #{tag} via {host}", file=sys.stderr)
            statuses = masto.get(
                instance,
                f"/api/v1/timelines/tag/{quote(tag)}",
                token_env=token_env,
                params={"limit": limit, "local": str(local).lower(), "only_media": str(only_media).lower()},
            )
            source = f"mastodon-tag:{host}:#{tag}"
            for status in statuses if isinstance(statuses, list) else []:
                if isinstance(status, dict):
                    emit(normalize_status(status, source=source, source_tags=source_tags, observed_at=observed_at, instance=host))
        except Exception as exc:
            print(f"error fetching Mastodon tag #{tag} on {instance_value}: {exc}", file=sys.stderr)
            if fail_fast:
                raise


def fetch_timelines(config: dict[str, Any], masto: MastodonClient, observed_at: str, instances: dict[str, dict[str, Any]], fail_fast: bool) -> None:
    for timeline in config.get("timelines") or config.get("public_timelines") or []:
        if not isinstance(timeline, dict) or not timeline.get("instance"):
            continue
        if timeline.get("enabled") is False:
            continue
        source_tags = timeline.get("tags") if isinstance(timeline.get("tags"), list) else []
        limit = int(timeline.get("limit") or 20)
        local = bool(timeline.get("local", True))
        remote = bool(timeline.get("remote", False))
        only_media = bool(timeline.get("only_media", False))
        try:
            instance, token_env = resolve_instance(str(timeline["instance"]), instances)
            host = instance_key(instance)
            print(f"fetching Mastodon {'local' if local else 'federated'} timeline: {host}", file=sys.stderr)
            statuses = masto.get(
                instance,
                "/api/v1/timelines/public",
                token_env=token_env,
                params={"limit": limit, "local": str(local).lower(), "remote": str(remote).lower(), "only_media": str(only_media).lower()},
            )
            source = timeline.get("source") or f"mastodon-timeline:{host}:{'local' if local else 'federated'}"
            for status in statuses if isinstance(statuses, list) else []:
                if isinstance(status, dict):
                    emit(normalize_status(status, source=source, source_tags=source_tags, observed_at=observed_at, instance=host))
        except Exception as exc:
            print(f"error fetching Mastodon timeline {timeline.get('instance')}: {exc}", file=sys.stderr)
            if fail_fast:
                raise


def cmd_fetch(args: argparse.Namespace) -> int:
    config = load_config(args.config)
    observed_at = now_iso()
    instances = instance_map(config)
    masto = MastodonClient(timeout=args.timeout)
    try:
        fetch_accounts(config, masto, observed_at, instances, args.fail_fast)
        fetch_tags(config, masto, observed_at, instances, args.fail_fast)
        fetch_timelines(config, masto, observed_at, instances, args.fail_fast)
    finally:
        masto.close()
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="media-hub-mastodon")
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
