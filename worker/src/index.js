// Parallax News edge worker (Cloudflare Workers, free plan).
//
//   GET /feed          -> latest crawler feed (JSON), cached at the edge
//   GET /og?url=...    -> { image } : preview image of an article page,
//                         cached for a day, so phones don't fetch pages
//   GET /y/<path>      -> Yahoo Finance JSON (chart, trending, screener,
//                         search only), cached 60 s and shared by all users
//   GET /fh?fn=quote|search&q=... -> Finnhub (needs FINNHUB_KEY secret)
//   GET /health        -> "ok"
//   cron (every 5 min) -> starts the GitHub crawler, because GitHub's own
//                         schedule is often delayed or skipped. Needs the
//                         GH_TOKEN secret; without it this does nothing.
//
// Deployed as its OWN worker ("parallax-news"), so it never touches any
// other worker on the account.

const FEED_TTL = 120; // seconds
const OG_TTL = 86400;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
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

async function feed(request, env, ctx) {
  const cache = caches.default;
  const key = new Request("https://parallax-cache/feed");
  const hit = await cache.match(key);
  if (hit) return hit;
  const src = env.FEED_URL || "https://github.com/JackLongman12/parallax-news/releases/download/feed/feed.json.gz";
  const r = await fetch(src, { redirect: "follow", cf: { cacheTtl: FEED_TTL } });
  if (!r.ok) return json({ error: "feed unavailable" }, 502, 30);
  const body = r.body.pipeThrough(new DecompressionStream("gzip"));
  const res = new Response(body, {
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": `public, max-age=${FEED_TTL}`, ...CORS },
  });
  ctx.waitUntil(cache.put(key, res.clone()));
  return res;
}

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

const YAHOO_PATHS = [
  /^\/v8\/finance\/chart\/[^/]{1,32}$/,
  /^\/v1\/finance\/trending\/[A-Z]{2}$/,
  /^\/v1\/finance\/screener\/predefined\/saved$/,
  /^\/v1\/finance\/search$/,
];

async function yahoo(request, ctx) {
  const url = new URL(request.url);
  const path = url.pathname.slice(2); // drop "/y"
  if (!YAHOO_PATHS.some((re) => re.test(path)) || url.search.length > 300) {
    return json({ error: "not allowed" }, 400);
  }
  const target = "https://query1.finance.yahoo.com" + path + url.search;
  const cache = caches.default;
  const key = new Request("https://parallax-cache/y" + path + url.search);
  const hit = await cache.match(key);
  if (hit) return hit;
  const r = await fetch(target, { headers: { "User-Agent": "Mozilla/5.0", Accept: "application/json" } });
  if (!r.ok) return json({ error: "upstream " + r.status }, r.status === 429 ? 429 : 502, 15);
  const body = await r.text();
  if (body.length > 2_000_000) return json({ error: "too large" }, 502);
  const res = new Response(body, {
    headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=60", ...CORS },
  });
  ctx.waitUntil(cache.put(key, res.clone()));
  return res;
}

// Finnhub (official market API, free key kept as the FINNHUB_KEY secret so
// it never ships in the open-source app). Quote and symbol search only.
async function finnhub(request, env, ctx) {
  if (!env.FINNHUB_KEY) return json({ error: "not configured" }, 503, 300);
  const url = new URL(request.url);
  const fn = url.searchParams.get("fn");
  const q = (url.searchParams.get("q") || "").trim();
  if (!["quote", "search"].includes(fn) || !q || q.length > 40 || !/^[\w .:^=&-]+$/.test(q)) {
    return json({ error: "bad request" }, 400);
  }
  const cache = caches.default;
  const key = new Request(`https://parallax-cache/fh/${fn}/${encodeURIComponent(q)}`);
  const hit = await cache.match(key);
  if (hit) return hit;
  const param = fn === "quote" ? "symbol" : "q";
  const r = await fetch(`https://finnhub.io/api/v1/${fn}?${param}=${encodeURIComponent(q)}&token=${env.FINNHUB_KEY}`);
  if (!r.ok) return json({ error: "upstream " + r.status }, r.status === 429 ? 429 : 502, 15);
  const res = new Response(await r.text(), {
    headers: { "Content-Type": "application/json", "Cache-Control": `public, max-age=${fn === "quote" ? 30 : 3600}`, ...CORS },
  });
  ctx.waitUntil(cache.put(key, res.clone()));
  return res;
}

export default {
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
    if (request.method !== "GET") return json({ error: "method not allowed" }, 405);
    const path = new URL(request.url).pathname;
    if (path === "/feed") return feed(request, env, ctx);
    if (path === "/og") return og(request, env, ctx);
    if (path.startsWith("/y/")) return yahoo(request, ctx);
    if (path === "/fh") return finnhub(request, env, ctx);
    if (path === "/health") return new Response("ok", { headers: CORS });
    return json({ error: "not found" }, 404);
  },

  async scheduled(event, env, ctx) {
    if (!env.GH_TOKEN) return;
    const repo = env.GH_REPO || "JackLongman12/parallax-news";
    ctx.waitUntil(
      fetch(`https://api.github.com/repos/${repo}/actions/workflows/crawler.yml/dispatches`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.GH_TOKEN}`,
          Accept: "application/vnd.github+json",
          "User-Agent": "parallax-news-worker",
        },
        body: JSON.stringify({ ref: "main" }),
      }),
    );
  },
};
