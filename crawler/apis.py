"""Official news APIs, used next to the RSS feeds.

Each one is switched on by its key in the environment (GitHub Actions
secrets). Without a key it is skipped, so the crawler still works with none.
Free tiers have daily limits, so the smaller ones are only called every
`every` minutes (tracked in the crawler's state file).

    GUARDIAN_KEY   open-platform.theguardian.com      5,000 calls/day
    NYT_KEY        developer.nytimes.com              500 calls/day
    NEWSDATA_KEY   newsdata.io                        200 credits/day
    GNEWS_KEY      gnews.io                           100 calls/day
    NEWSAPI_KEY    newsapi.org (dev plan, 24 h delay) 100 calls/day

Keys never reach the app or the published feed.
"""
from __future__ import annotations

import datetime
import json
import os
import time
import urllib.parse
import urllib.request
from email.utils import parsedate_to_datetime

UA = "ParallaxNewsCrawler/1.0 (open-source news reader)"
STATS: dict[str, int | str] = {}

GUARDIAN_CAT = {
    "world": "world", "us-news": "politics", "politics": "politics", "uk-news": "politics",
    "business": "business", "money": "business", "technology": "technology", "science": "science",
    "environment": "climate", "sport": "sports", "football": "sports", "culture": "entertainment",
    "film": "entertainment", "music": "entertainment", "tv-and-radio": "entertainment",
    "society": "health", "games": "gaming",
}
NYT_CAT = {
    "World": "world", "U.S.": "politics", "Business": "business", "Business Day": "business",
    "Technology": "technology", "Science": "science", "Health": "health", "Sports": "sports",
    "Climate": "climate", "Arts": "entertainment", "Movies": "entertainment",
}
NEWSDATA_CAT = {
    "world": "world", "politics": "politics", "business": "business", "technology": "technology",
    "science": "science", "health": "health", "sports": "sports", "entertainment": "entertainment",
    "environment": "climate",
}


def _get(url, headers=None):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json", **(headers or {})})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read(5_000_000))


def _ts(s):
    if not s:
        return None
    try:
        d = datetime.datetime.fromisoformat(s.strip().replace("Z", "+00:00"))
        if d.tzinfo is None:
            d = d.replace(tzinfo=datetime.timezone.utc)
        return int(d.timestamp())
    except ValueError:
        try:
            return int(parsedate_to_datetime(s).timestamp())
        except (TypeError, ValueError):
            return None


def _domain(url):
    try:
        h = urllib.parse.urlparse(url).hostname or ""
    except ValueError:
        return ""
    return h[4:] if h.startswith("www.") else h


def _art(title, url, source, published, image, cat, country, provider, desc=""):
    if not title or not url or not url.startswith("https://"):
        return None
    d = _domain(url)
    if not d:
        return None
    return {"t": title.strip(), "u": url, "s": source or d, "d": d, "p": _ts(published),
            "i": image if image and image.startswith("https://") else None,
            "h": cat, "g": country, "v": provider, "n": (desc or "")[:300]}


def guardian(key):
    out = []
    for page in (1, 2):
        j = _get("https://content.guardianapis.com/search?" + urllib.parse.urlencode({
            "api-key": key, "page-size": 50, "page": page, "order-by": "newest",
            "show-fields": "thumbnail,trailText"}))
        for r in j.get("response", {}).get("results", []):
            f = r.get("fields") or {}
            a = _art(r.get("webTitle"), r.get("webUrl"), "The Guardian", r.get("webPublicationDate"),
                     f.get("thumbnail"), GUARDIAN_CAT.get(r.get("sectionId")), "GB", "api", f.get("trailText"))
            if a:
                out.append(a)
    return out


def nyt(key):
    j = _get("https://api.nytimes.com/svc/news/v3/content/all/all.json?" + urllib.parse.urlencode(
        {"api-key": key, "limit": 100}))
    out = []
    for r in j.get("results", []):
        img = None
        for m in r.get("multimedia") or []:
            if m.get("url", "").startswith("https://") and (m.get("width") or 0) >= 400:
                img = m["url"]
        a = _art(r.get("title"), r.get("url"), "The New York Times", r.get("published_date"), img,
                 NYT_CAT.get(r.get("section")), "US", "api", r.get("abstract"))
        if a:
            out.append(a)
    return out


def newsdata(key):
    out = []
    # 4 credits per call round, 10 articles each: English world + 3 big languages.
    for params in ({"language": "en"}, {"language": "es"}, {"language": "fr"}, {"language": "de"}):
        try:
            j = _get("https://newsdata.io/api/1/latest?" + urllib.parse.urlencode({"apikey": key, **params}))
        except Exception as e:  # noqa: BLE001
            STATS["newsdata error"] = str(getattr(e, "code", type(e).__name__))
            continue
        for r in j.get("results") or []:
            cats = r.get("category") or []
            country = (r.get("country") or [None])[0]
            a = _art(r.get("title"), r.get("link"), r.get("source_name") or r.get("source_id"),
                     r.get("pubDate"), r.get("image_url"), next((NEWSDATA_CAT[c] for c in cats if c in NEWSDATA_CAT), None),
                     None if not country else str(country)[:2].upper(), "api", r.get("description"))
            if a:
                out.append(a)
    return out


def gnews(key):
    j = _get("https://gnews.io/api/v4/top-headlines?" + urllib.parse.urlencode(
        {"apikey": key, "lang": "en", "max": 10, "category": "general"}))
    out = []
    for r in j.get("articles", []):
        src = r.get("source") or {}
        a = _art(r.get("title"), r.get("url"), src.get("name"), r.get("publishedAt"), r.get("image"),
                 None, None, "api", r.get("description"))
        if a:
            out.append(a)
    return out


def newsapi(key):
    j = _get("https://newsapi.org/v2/top-headlines?" + urllib.parse.urlencode(
        {"language": "en", "pageSize": 100}), headers={"X-Api-Key": key})
    out = []
    for r in j.get("articles", []):
        src = r.get("source") or {}
        a = _art(r.get("title"), r.get("url"), src.get("name"), r.get("publishedAt"), r.get("urlToImage"),
                 None, None, "api", r.get("description"))
        if a:
            out.append(a)
    return out


# name: (env var, function, minutes between calls)
APIS = {
    "guardian": ("GUARDIAN_KEY", guardian, 5),
    "nyt": ("NYT_KEY", nyt, 5),
    "newsdata": ("NEWSDATA_KEY", newsdata, 30),
    "gnews": ("GNEWS_KEY", gnews, 20),
    "newsapi": ("NEWSAPI_KEY", newsapi, 20),
}


def fetch_all(state):
    """Articles from every API that has a key and is due. `state` is the
    crawler's persisted dict; last-call times are kept under "api"."""
    last = state.setdefault("api", {})
    cached = state.setdefault("api_items", {})
    out = []
    now = time.time()
    for name, (env, fn, every) in APIS.items():
        key = os.environ.get(env, "").strip()
        if not key:
            continue
        if now - last.get(name, 0) >= every * 60 - 30:
            try:
                items = fn(key)
                last[name] = now
                cached[name] = items[:150]
                STATS[name] = len(items)
            except Exception as e:  # noqa: BLE001 - one API failing never stops the crawl
                STATS[name] = f"error {getattr(e, 'code', type(e).__name__)}"
        else:
            STATS[name] = f"cached {len(cached.get(name, []))}"
        # Between calls, reuse the last answer so these stories don't vanish.
        out.extend(cached.get(name, []))
    for name in list(cached):
        if name not in APIS or not os.environ.get(APIS[name][0], "").strip():
            cached.pop(name)
    return out
