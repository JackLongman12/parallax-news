// Parallax News edge worker (Cloudflare Workers, free plan).
//
//   GET  /feed         -> latest crawler feed (JSON). Served from a copy kept
//                         in KV, so it keeps working while GitHub is down
//                         (the feed just gets older until GitHub is back).
//   GET  /og?url=...   -> { image } : preview image of an article page,
//                         cached for a day, so phones don't fetch pages
//   POST /crash        -> anonymous crash report from the app (see crash())
//   GET  /crashes[?id=...] (Authorization: Bearer ADMIN_TOKEN) -> crash reports
//   GET  /health       -> JSON status; HTTP 503 if the feed is older than
//                         30 min (point an uptime monitor at it)
//   cron (every 5 min) -> copies a new feed from GitHub into KV, and if the
//                         crawler has stalled (no new feed for 12 min)
//                         restarts it (needs the GH_TOKEN secret).
//
// Deployed as its OWN worker ("parallax-news"), so it never touches any
// other worker on the account. KV binding: STORE.

const FEED_TTL = 120; // seconds at the edge
const OG_TTL = 86400;
const STALE_RESTART = 12 * 60; // seconds without a new feed -> restart crawler
const STALE_UNHEALTHY = 30 * 60;
const GITHUB_FEED = "https://github.com/JackLongman12/parallax-news/releases/download/feed/feed.json.gz";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(body, status = 200, maxAge = 60) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": `public, max-age=${maxAge}`, ...CORS },
  });
}

/** Only public http(s) URLs; no IP literals, no localhost. */
function safeUrl(raw) {
  let u;
  try {
    u = new URL(raw);
  } catch {
    return null;
  }
  if (u.protocol !== "https:" && u.protocol !== "http:") return null;
  const h = u.hostname.toLowerCase();
  if (!h.includes(".") || h === "localhost" || h.endsWith(".local") || h.endsWith(".internal")) return null;
  if (/^[\d.]+$/.test(h) || h.includes(":")) return null; // IP literals
  if (raw.length > 2000) return null;
  return u;
}

// ---- Feed ----

function feedResponse(gzBody, age) {
  return new Response(gzBody.pipeThrough(new DecompressionStream("gzip")), {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": `public, max-age=${FEED_TTL}`,
      "X-Feed-Age": String(age ?? -1),
      ...CORS,
    },
  });
}

async function feed(request, env, ctx) {
  const cache = caches.default;
  const key = new Request("https://parallax-cache/feed");
  const hit = await cache.match(key);
  if (hit) return hit;
  let res = null;
  let kv = null;
  // 1. The copy in KV (refreshed by the cron).
  if (env.STORE) {
    try {
      kv = await env.STORE.getWithMetadata("feed:gz", { type: "stream" });
    } catch {
      kv = null;
    }
  }
  const age = kv?.metadata?.seen ? Math.round(Date.now() / 1000 - kv.metadata.seen) : null;
  if (kv?.value && age !== null && age < STALE_RESTART) {
    res = feedResponse(kv.value, age);
  } else {
    // 2. KV copy missing or stale (e.g. KV writes failing): GitHub directly,
    //    and only if GitHub fails too, the old KV copy.
    try {
      const r = await fetch(env.FEED_URL || GITHUB_FEED, { redirect: "follow", cf: { cacheTtl: FEED_TTL } });
      if (r.ok) {
        if (kv?.value) await kv.value.cancel();
        res = feedResponse(r.body, null);
      }
    } catch {
      res = null;
    }
    if (!res && kv?.value) res = feedResponse(kv.value, age);
    if (!res) return json({ error: "feed unavailable" }, 502, 30);
  }
  ctx.waitUntil(cache.put(key, res.clone()));
  return res;
}

async function feedMeta(env) {
  try {
    const { value, metadata } = await env.STORE.getWithMetadata("feed:gz", { type: "stream" });
    if (value) await value.cancel();
    return metadata || {};
  } catch {
    return {};
  }
}

/** Cron: copy a changed feed from GitHub into KV (one write per new feed). */
async function syncFeed(env) {
  const meta = await feedMeta(env);
  const r = await fetch(env.FEED_URL || GITHUB_FEED, { redirect: "follow" });
  if (!r.ok) return meta;
  const buf = await r.arrayBuffer();
  const sig = r.headers.get("etag") || r.headers.get("last-modified") || String(buf.byteLength);
  if (sig === meta.sig) return meta;
  // Sanity check: a gzip file that isn't tiny (never replace a good copy
  // with an error page or a broken upload).
  const b = new Uint8Array(buf);
  if (buf.byteLength < 10_000 || b[0] !== 0x1f || b[1] !== 0x8b) return meta;
  const next = { sig, seen: Math.round(Date.now() / 1000), size: buf.byteLength };
  await env.STORE.put("feed:gz", buf, { metadata: next });
  return next;
}

async function health(env) {
  const meta = env.STORE ? await feedMeta(env) : {};
  const age = meta.seen ? Math.round(Date.now() / 1000 - meta.seen) : null;
  const ok = age !== null && age < STALE_UNHEALTHY;
  return json({ ok, feedAgeSeconds: age, feedBytes: meta.size ?? null }, ok ? 200 : 503, 0);
}

// ---- Preview images ----

const META = /<meta\s[^>]*>/gi;
const PROP = /(?:property|name)\s*=\s*["']([^"']+)["']/i;
const CONTENT = /content\s*=\s*["']([^"']+)["']/i;
const GENERIC = /(logo|placeholder|default|fallback|blank|spacer|avatar|favicon|social[-_]?share)/i;

async function og(request, env, ctx) {
  const target = safeUrl(new URL(request.url).searchParams.get("url") || "");
  if (!target) return json({ error: "bad url" }, 400);
  const cache = caches.default;
  const key = new Request("https://parallax-cache/og/" + encodeURIComponent(target.toString()));
  const hit = await cache.match(key);
  if (hit) return hit;

  let image = null;
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 6000);
    const r = await fetch(target.toString(), {
      redirect: "follow",
      signal: ctrl.signal,
      headers: { "User-Agent": "Mozilla/5.0 (compatible; ParallaxNews/1.0)" },
    });
    clearTimeout(timer);
    if (r.ok && (r.headers.get("content-type") || "").includes("html")) {
      // Read at most ~96 KB: the meta tags live in <head>.
      const reader = r.body.getReader();
      let text = "";
      const dec = new TextDecoder();
      while (text.length < 98304) {
        const { done, value } = await reader.read();
        if (done) break;
        text += dec.decode(value, { stream: true });
      }
      reader.cancel().catch(() => {});
      let ogImg = null, tw = null;
      for (const tag of text.match(META) || []) {
        const p = PROP.exec(tag);
        const c = CONTENT.exec(tag);
        if (!p || !c) continue;
        const prop = p[1].toLowerCase();
        if (["og:image", "og:image:secure_url", "og:image:url"].includes(prop)) ogImg = ogImg || c[1];
        if (["twitter:image", "twitter:image:src"].includes(prop)) tw = tw || c[1];
      }
      const rawImg = ogImg || tw;
      if (rawImg) {
        const abs = new URL(rawImg.replace(/&amp;/g, "&"), target);
        if (abs.protocol === "http:") abs.protocol = "https:";
        const name = abs.pathname.split("/").pop() || "";
        if (abs.protocol === "https:" && safeUrl(abs.toString()) && !GENERIC.test(name)) image = abs.toString();
      }
    }
  } catch {
    image = null;
  }
  const res = json({ image }, 200, OG_TTL);
  ctx.waitUntil(cache.put(key, res.clone()));
  return res;
}

// ---- Crash reports ----
// The app sends: app version, Android version, error text and stack trace.
// No user data. Reports are grouped by a fingerprint of the error and its
// top frames and kept 30 days. IP addresses are never stored: a hashed,
// daily-salted counter in the edge cache limits each phone to 20 a day.

const CRASH_TTL = 30 * 86400;
const clip = (v, n) => (typeof v === "string" ? v.slice(0, n) : "");

async function sha(text) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map((x) => x.toString(16).padStart(2, "0")).join("").slice(0, 24);
}

async function crash(request, env, ctx) {
  if (!env.STORE) return json({ error: "not configured" }, 503, 0);
  if (Number(request.headers.get("content-length") || 0) > 16_000) return json({ error: "too large" }, 413, 0);
  let r;
  try {
    r = JSON.parse((await request.text()).slice(0, 16_000));
  } catch {
    return json({ error: "bad json" }, 400, 0);
  }
  const err = clip(r.error, 600);
  const stack = clip(r.stack, 4000);
  if (!err) return json({ error: "missing error" }, 400, 0);

  const day = new Date().toISOString().slice(0, 10);
  const who = await sha((request.headers.get("cf-connecting-ip") || "") + day + (env.SALT || "parallax"));
  const cache = caches.default;
  const rk = new Request(`https://parallax-cache/crash-rate/${who}`);
  const n = Number((await (await cache.match(rk))?.text()) || 0);
  if (n >= 20) return json({ ok: true, dropped: true }, 200, 0);
  ctx.waitUntil(cache.put(rk, new Response(String(n + 1), { headers: { "Cache-Control": "max-age=86400" } })));

  // Cap new crash writes per hour (per Cloudflare location) so a flood of
  // reports can't use up the free plan's 1,000 daily KV writes that the
  // feed copy also needs.
  const hk = new Request(`https://parallax-cache/crash-hour/${new Date().toISOString().slice(0, 13)}`);
  const writes = Number((await (await cache.match(hk))?.text()) || 0);
  if (writes >= 25) return json({ ok: true, dropped: true }, 200, 0);

  const frames = stack.split("\n").filter((l) => l.trim()).slice(0, 5).join("\n");
  const fp = await sha(err.split("\n")[0].replace(/\d+/g, "#") + "\n" + frames);
  const key = `crash:${fp}`;
  const now = Math.round(Date.now() / 1000);
  const old = await env.STORE.get(key, { type: "json" });
  // Same crash again within the hour: skip the write (the free plan allows
  // 1,000 KV writes a day).
  if (old && now - old.last < 3600) return json({ ok: true, id: fp }, 200, 0);
  const version = clip(r.version, 30);
  const rec = {
    first: old?.first || now,
    last: now,
    count: (old?.count || 0) + 1,
    version,
    versions: [...new Set([...(old?.versions || []), version])].slice(-10),
    os: clip(r.os, 60),
    fatal: !!r.fatal,
    error: err,
    stack,
  };
  ctx.waitUntil(cache.put(hk, new Response(String(writes + 1), { headers: { "Cache-Control": "max-age=3600" } })));
  await env.STORE.put(key, JSON.stringify(rec), {
    expirationTtl: CRASH_TTL,
    metadata: { last: now, count: rec.count, version, error: err.slice(0, 160) },
  });
  return json({ ok: true, id: fp }, 200, 0);
}

function sameSecret(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function crashes(request, env) {
  const url = new URL(request.url);
  // Token in a header, not the URL (URLs end up in logs).
  const auth = (request.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!env.ADMIN_TOKEN || !sameSecret(auth, env.ADMIN_TOKEN)) return json({ error: "forbidden" }, 403, 0);
  const id = url.searchParams.get("id");
  if (id) return json((await env.STORE.get(`crash:${id}`, { type: "json" })) || { error: "not found" }, 200, 0);
  const list = await env.STORE.list({ prefix: "crash:", limit: 1000 });
  const rows = list.keys
    .map((k) => ({ id: k.name.slice(6), ...(k.metadata || {}) }))
    .sort((a, b) => (b.last || 0) - (a.last || 0));
  return json({ count: rows.length, crashes: rows }, 200, 0);
}

export default {
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
    const path = new URL(request.url).pathname;
    if (request.method === "POST" && path === "/crash") return crash(request, env, ctx);
    if (request.method !== "GET") return json({ error: "method not allowed" }, 405);
    if (path === "/feed") return feed(request, env, ctx);
    if (path === "/og") return og(request, env, ctx);
    if (path === "/crashes") return crashes(request, env);
    if (path === "/health") return health(env);
    return json({ error: "not found" }, 404);
  },

  async scheduled(event, env, ctx) {
    ctx.waitUntil(
      (async () => {
        const meta = env.STORE ? await syncFeed(env) : {};
        // Watchdog: restart the crawler only if it has stalled.
        const age = meta.seen ? Date.now() / 1000 - meta.seen : Infinity;
        if (!env.GH_TOKEN || age < STALE_RESTART) return;
        const repo = env.GH_REPO || "JackLongman12/parallax-news";
        await fetch(`https://api.github.com/repos/${repo}/actions/workflows/crawler.yml/dispatches`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${env.GH_TOKEN}`,
            Accept: "application/vnd.github+json",
            "User-Agent": "parallax-news-worker",
          },
          body: JSON.stringify({ ref: "main" }),
        });
      })(),
    );
  },
};
