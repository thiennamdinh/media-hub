import { AtpAgent } from "@atproto/api";
import fs from "node:fs";
import { parse } from "yaml";

const SERVICE = process.env.BLUESKY_SERVICE ?? "https://public.api.bsky.app";

function nowIso(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

function canonicalizeUrl(url: string | undefined): string | undefined {
  if (!url) return undefined;
  try {
    const u = new URL(url.trim());
    u.hash = "";
    u.hostname = u.hostname.toLowerCase();
    for (const key of [...u.searchParams.keys()]) {
      const lower = key.toLowerCase();
      if (lower.startsWith("utm_") || ["fbclid", "gclid", "igshid", "mc_cid", "mc_eid"].includes(lower)) {
        u.searchParams.delete(key);
      }
    }
    if (u.pathname !== "/") u.pathname = u.pathname.replace(/\/+$/, "");
    return u.toString();
  } catch {
    return url;
  }
}

function linksFromPost(post: any): string[] {
  const out = new Set<string>();
  const facets = post?.record?.facets ?? [];
  for (const facet of facets) {
    for (const feature of facet.features ?? []) {
      if (feature?.$type === "app.bsky.richtext.facet#link" && feature.uri) out.add(feature.uri);
    }
  }
  const embed = post?.embed;
  if (embed?.external?.uri) out.add(embed.external.uri);
  return [...out];
}

function sanitizeString(value: string): string {
  let out = "";
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code >= 0xd800 && code <= 0xdbff) {
      const next = value.charCodeAt(i + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        out += value[i] + value[i + 1];
        i++;
      } else {
        out += "�";
      }
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      out += "�";
    } else {
      out += value[i];
    }
  }
  return out;
}

function sanitizeJson(value: unknown): unknown {
  if (typeof value === "string") return sanitizeString(value);
  if (Array.isArray(value)) return value.map(sanitizeJson);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, sanitizeJson(v)]));
  }
  return value;
}

function emit(record: Record<string, unknown>) {
  console.log(JSON.stringify(sanitizeJson(record)));
}

function normalizePost(post: any, source: string, tags: string[], observedAt: string) {
  const text = typeof post?.record?.text === "string" ? post.record.text : undefined;
  const links = linksFromPost(post);
  return {
    schema_version: 1,
    source,
    source_type: "bluesky",
    record_type: "social_post",
    observed_at: observedAt,
    title: text ? text.slice(0, 120) : undefined,
    url: post?.uri ? `https://bsky.app/profile/${post?.author?.handle}/post/${post.uri.split("/").pop()}` : undefined,
    canonical_url: links.length === 1 ? canonicalizeUrl(links[0]) : undefined,
    published_at: post?.record?.createdAt ?? post?.indexedAt,
    external_id: post?.uri,
    network: "bluesky",
    post_uri: post?.uri,
    cid: post?.cid,
    author_handle: post?.author?.handle,
    author_did: post?.author?.did,
    text,
    links: links.map(canonicalizeUrl),
    like_count: post?.likeCount,
    repost_count: post?.repostCount,
    reply_count: post?.replyCount,
    quote_count: post?.quoteCount,
    tags,
  };
}

function compact<T extends Record<string, unknown>>(record: T): T {
  for (const key of Object.keys(record)) {
    if (record[key] === undefined || record[key] === null) delete record[key];
  }
  return record;
}

async function maybeLogin(agent: AtpAgent) {
  const identifier = process.env.BLUESKY_IDENTIFIER;
  const password = process.env.BLUESKY_APP_PASSWORD;
  if (identifier && password) {
    await agent.login({ identifier, password });
  }
}

async function fetchSearches(agent: AtpAgent, config: any, observedAt: string) {
  for (const search of config.searches ?? []) {
    if (!search?.query) continue;
    const limit = Number(search.limit ?? 25);
    const tags = Array.isArray(search.tags) ? search.tags : [];
    console.error(`searching Bluesky: ${search.query}`);
    try {
      const res = await agent.app.bsky.feed.searchPosts({ q: search.query, limit });
      for (const post of res.data.posts ?? []) {
        emit(compact(normalizePost(post, `bluesky-search:${search.query}`, tags, observedAt)));
      }
    } catch (err: any) {
      console.error(`error searching Bluesky ${search.query}: ${err?.message ?? String(err)}`);
    }
  }
}

async function fetchActors(agent: AtpAgent, config: any, observedAt: string) {
  for (const actor of config.actors ?? []) {
    if (!actor?.handle) continue;
    const limit = Number(actor.limit ?? 25);
    const tags = Array.isArray(actor.tags) ? actor.tags : [];
    console.error(`fetching Bluesky actor: ${actor.handle}`);
    try {
      const res = await agent.app.bsky.feed.getAuthorFeed({ actor: actor.handle, limit, filter: actor.filter ?? "posts_no_replies" });
      for (const item of res.data.feed ?? []) {
        emit(compact(normalizePost(item.post, `bluesky-actor:${actor.handle}`, tags, observedAt)));
      }
    } catch (err: any) {
      console.error(`error fetching Bluesky actor ${actor.handle}: ${err?.message ?? String(err)}`);
    }
  }
}

async function fetchLists(agent: AtpAgent, config: any, observedAt: string) {
  for (const list of config.lists ?? []) {
    if (!list?.uri) continue;
    const limit = Number(list.limit ?? 25);
    const source = list.name ? `bluesky-list:${list.name}` : `bluesky-list:${list.uri}`;
    const tags = Array.isArray(list.tags) ? list.tags : [];
    console.error(`fetching Bluesky list: ${list.name ?? list.uri}`);
    try {
      const res = await agent.app.bsky.feed.getListFeed({ list: list.uri, limit });
      for (const item of res.data.feed ?? []) {
        emit(compact(normalizePost(item.post, source, tags, observedAt)));
      }
    } catch (err: any) {
      console.error(`error fetching Bluesky list ${list.name ?? list.uri}: ${err?.message ?? String(err)}`);
    }
  }
}

async function fetchFeeds(agent: AtpAgent, config: any, observedAt: string) {
  for (const feed of config.feeds ?? []) {
    if (!feed?.uri) continue;
    const limit = Number(feed.limit ?? 25);
    const source = feed.name ? `bluesky-feed:${feed.name}` : `bluesky-feed:${feed.uri}`;
    const tags = Array.isArray(feed.tags) ? feed.tags : [];
    console.error(`fetching Bluesky feed: ${feed.name ?? feed.uri}`);
    try {
      const res = await agent.app.bsky.feed.getFeed({ feed: feed.uri, limit });
      for (const item of res.data.feed ?? []) {
        emit(compact(normalizePost(item.post, source, tags, observedAt)));
      }
    } catch (err: any) {
      console.error(`error fetching Bluesky feed ${feed.name ?? feed.uri}: ${err?.message ?? String(err)}`);
    }
  }
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  if (command !== "fetch") {
    console.error("Usage: media-hub-bluesky fetch --config /config/config.yaml");
    process.exit(command === "--help" || command === "-h" ? 0 : 1);
  }
  const configIndex = args.indexOf("--config");
  if (configIndex < 0 || !args[configIndex + 1]) {
    console.error("error: --config is required");
    process.exit(1);
  }
  const config = parse(fs.readFileSync(args[configIndex + 1], "utf8")) ?? {};
  const observedAt = nowIso();
  const agent = new AtpAgent({ service: SERVICE });
  await maybeLogin(agent);
  await fetchSearches(agent, config, observedAt);
  await fetchActors(agent, config, observedAt);
  await fetchLists(agent, config, observedAt);
  await fetchFeeds(agent, config, observedAt);
}

main().catch((err) => {
  console.error(err?.stack ?? String(err));
  process.exit(1);
});
