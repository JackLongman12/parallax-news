#!/usr/bin/env python3
"""Parallax News crawler (runs on GitHub Actions every ~30 minutes).

1. Fetches hundreds of feeds in parallel: Google News for ~40 country
   editions x 9 sections, every RSS feed in the catalog, and crawler/feeds.txt.
2. Groups headlines about the same event into stories.
3. EXPANDS the biggest stories with targeted Google News + Bing searches, so
   major stories carry 20+ outlets.
4. Labels a topic, finds a real news photo (feed media or the article page's
   og:image), and attaches outlet ratings from the catalog.
5. Writes feed.json.gz (+ state.json.gz cache) for the app to download.

Only the Python standard library is used. Headlines, links and preview
images only (no article bodies) - same as any news reader.
"""
from __future__ import annotations

import gzip
import hashlib
import html
import json
import math
import pathlib
import re
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from email.utils import parsedate_to_datetime

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "crawler/out"
UA = "Mozilla/5.0 (compatible; ParallaxNewsCrawler/1.0; open-source news reader)"
NOW = time.time()
MAX_AGE_H = 36
WORKERS = 48

# ---------------------------------------------------------------- feeds ---
EDITIONS = [
    ("en-US", "US", "en"), ("en-GB", "GB", "en"), ("en-CA", "CA", "en"), ("en-AU", "AU", "en"),
    ("en-IN", "IN", "en"), ("en-IE", "IE", "en"), ("en-NZ", "NZ", "en"), ("en-ZA", "ZA", "en"),
    ("en-NG", "NG", "en"), ("en-KE", "KE", "en"), ("en-SG", "SG", "en"), ("en-PH", "PH", "en"),
    ("en-PK", "PK", "en"), ("en-MY", "MY", "en"), ("en-GH", "GH", "en"), ("en-UG", "UG", "en"),
    ("es-419", "MX", "es-419"), ("es-419", "AR", "es-419"), ("es-419", "CO", "es-419"), ("es", "ES", "es"),
    ("pt-BR", "BR", "pt-419"), ("pt-PT", "PT", "pt-150"), ("fr", "FR", "fr"), ("de", "DE", "de"),
    ("it", "IT", "it"), ("nl", "NL", "nl"), ("pl", "PL", "pl"), ("sv", "SE", "sv"), ("uk", "UA", "uk"),
    ("tr", "TR", "tr"), ("ar", "EG", "ar"), ("he", "IL", "he"), ("ja", "JP", "ja"), ("ko", "KR", "ko"),
    ("zh-TW", "TW", "zh-Hant"), ("id", "ID", "id"), ("vi", "VN", "vi"), ("th", "TH", "th"),
]
SECTIONS = [None, "WORLD", "NATION", "BUSINESS", "TECHNOLOGY", "SCIENCE", "HEALTH", "SPORTS", "ENTERTAINMENT"]
SECTION_CAT = {
    "WORLD": "world", "NATION": "politics", "BUSINESS": "business", "TECHNOLOGY": "technology",
    "SCIENCE": "science", "HEALTH": "health", "SPORTS": "sports", "ENTERTAINMENT": "entertainment",
}


def gn_url(hl, gl, lang, section=None):
    q = f"hl={hl}&gl={gl}&ceid={gl}:{lang}"
    if section:
        return f"https://news.google.com/rss/headlines/section/topic/{section}?{q}"
    return f"https://news.google.com/rss?{q}"


def load_catalog():
    data = json.loads((ROOT / "assets/sources.json").read_text(encoding="utf-8"))["sources"]
    return {s["d"].lower(): s for s in data}


def feed_list(catalog):
    feeds = []
    for hl, gl, lang in EDITIONS:
        for sec in SECTIONS:
            feeds.append((gn_url(hl, gl, lang, sec), "google", SECTION_CAT.get(sec), gl))
    for s in catalog.values():
        if s.get("rss"):
            topics = s.get("t") or []
            feeds.append((s["rss"], "rss", topics[0] if topics else None, s.get("c")))
    extra = ROOT / "crawler/feeds.txt"
    if extra.exists():
        for line in extra.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("|")
            feeds.append((parts[0].strip(), "rss", parts[1].strip() if len(parts) > 1 and parts[1].strip() else None,
                          parts[2].strip() if len(parts) > 2 else None))
    return feeds


# --------------------------------------------------------------- fetching ---
def fetch(url, limit=4 * 1024 * 1024, timeout=12):
    if not url.startswith("https://") and not url.startswith("http://"):
        return None
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = r.read(limit)
            if r.headers.get("Content-Encoding") == "gzip":
                data = gzip.decompress(data)
            return data
    except Exception:
        return None


def domain_of(url):
    try:
        host = urllib.parse.urlparse(url).hostname or ""
    except ValueError:
        return ""
    host = host.lower()
    for p in ("www.", "m.", "amp.", "mobile."):
        if host.startswith(p):
            return host[len(p):]
    return host


TAG = re.compile(r"<[^>]+>")
WS = re.compile(r"\s+")


def clean(s):
    s = TAG.sub(" ", s or "")
    s = html.unescape(s)
    s = TAG.sub(" ", s)
    s = re.sub(r"[\u0000-\u0008\u000B\u000C\u000E-\u001F​-‏‪-‮⁦-⁩﻿]", "", s)
    return WS.sub(" ", s).strip()


def local(tag):
    return tag.rsplit("}", 1)[-1]


def parse_date(s):
    if not s:
        return None
    s = s.strip()
    try:
        return parsedate_to_datetime(s).timestamp()
    except Exception:
        pass
    try:
        from datetime import datetime
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def parse_feed(data, provider, hint, gl):
    try:
        root = ET.fromstring(data)
    except Exception:
        return []
    items = [e for e in root.iter() if local(e.tag) in ("item", "entry")]
    out = []
    for it in items[:120]:
        title = link = date = src_name = src_url = image = None
        best_w = -1
        desc = ""
        for c in list(it):
            n = local(c.tag)
            if n == "title":
                title = clean(c.text)
            elif n == "link":
                href = c.get("href")
                if href and c.get("rel") in (None, "alternate"):
                    link = link or href
                elif (c.text or "").strip():
                    link = link or c.text.strip()
            elif n in ("pubDate", "published", "updated", "date"):
                date = date or parse_date(c.text)
            elif n == "source":
                src_name = clean(c.text)
                src_url = c.get("url")
            elif n in ("description", "summary"):
                desc = clean(c.text)[:300]
            elif n in ("thumbnail", "content", "enclosure", "group"):
                cands = [c] + list(c)
                for m in cands:
                    u = m.get("url")
                    typ = m.get("type") or m.get("medium") or "image"
                    if u and u.startswith("https://") and typ.startswith("image"):
                        w = int(m.get("width") or (300 if local(m.tag) == "thumbnail" else 700))
                        if w > best_w:
                            best_w, image = w, u
            elif n == "Image" and (c.text or "").startswith("https://"):
                image = c.text.strip()
                best_w = 1000
        if not title or not link:
            continue
        if provider == "bing":
            q = urllib.parse.parse_qs(urllib.parse.urlparse(link).query)
            if q.get("url"):
                link = q["url"][0]
        dom = domain_of(src_url) if src_url else domain_of(link)
        if provider == "google" and src_name and title.endswith(" - " + src_name):
            title = title[: -len(src_name) - 3].strip()
        if not dom:
            continue
        out.append({
            "t": title, "u": link, "s": src_name or dom, "d": dom, "p": date, "i": image if best_w >= 250 else None,
            "h": hint, "g": gl, "v": provider, "n": desc if provider != "google" else "",
        })
    return out


def fetch_feed(spec):
    url, provider, hint, gl = spec
    data = fetch(url)
    return parse_feed(data, provider, hint, gl) if data else []


# --------------------------------------------------------------- filters ---
SPAM = re.compile(
    r"(acquires? (new )?(stake|position|[\d,]+ shares)|(sells|buys|purchases) [\d,]+ shares|"
    r"(increases|decreases|raises|trims|lifts|cuts) (its )?(stake|position|holdings) in|"
    r"price target (raised|lowered|cut|increased)|(stock|shares) (price )?(down|up) [\d.]+%|"
    r"short interest|options volume|horoscope|lottery results|crossword|wordle|sponsored)", re.I)
FARMS = {
    "marketbeat.com", "americanbankingnews.com", "tickerreport.com", "etfdailynews.com", "defenseworld.net",
    "thelincolnianonline.com", "themarketsdaily.com", "thecerbatgem.com", "theenterpriseleader.com",
    "modernreaders.com", "wkrb13.com", "zolmax.com", "dailypolitical.com", "thestockobserver.com",
}


def junk(a):
    if a["d"] in FARMS or len(a["t"]) < 15 or SPAM.search(a["t"]):
        return True
    if a["p"] and NOW - a["p"] > MAX_AGE_H * 3600:
        return True
    return False


# ------------------------------------------------------------- clustering ---
STOP = set("""the and for with that this from are was were has have had will would could should into over after
before about says said say new its his her their they you not but than then what when where who why how all can
out more most some just also amid via per off one two now year years day days week live update updates news report
reports video watch photos here top get gets make makes les des une pour dans sur por para con las los del una und
der die das mit von den ist dei della che""".split())
SPLIT = re.compile(r"[^\w]+", re.U)


def stem(w):
    if len(w) > 5 and w.endswith("ies"):
        return w[:-3] + "y"
    if len(w) > 4 and w.endswith("es"):
        return w[:-2]
    if len(w) > 3 and w.endswith("s") and not w.endswith("ss"):
        return w[:-1]
    return w


def tokens(text):
    return {stem(w) for w in SPLIT.split(text.lower()) if len(w) > 2 and w not in STOP and not w.isdigit()}


def sim(a, b):
    i = len(a & b)
    if not i:
        return 0.0
    return 0.5 * i / (len(a) + len(b) - i) + 0.5 * i / min(len(a), len(b))


def cluster(articles, threshold=0.40):
    clusters, index = [], {}
    articles.sort(key=lambda a: -(a["p"] or 0))
    for a in articles:
        tk = tokens(a["t"])
        if len(tk) < 2:
            continue
        a["_tk"] = tk
        cand = {}
        for t in tk:
            for ci in index.get(t, ()):
                cand[ci] = cand.get(ci, 0) + 1
        best, best_s = -1, 0.0
        for ci, inter in cand.items():
            if inter < 2:
                continue
            s = sim(tk, clusters[ci]["tk"])
            if s > best_s:
                best, best_s = ci, s
        if best >= 0 and best_s >= threshold:
            c = clusters[best]
            c["a"].append(a)
            if len(c["a"]) <= 5:
                for t in tk:
                    if t not in c["tk"]:
                        c["tk"].add(t)
                        index.setdefault(t, []).append(best)
        else:
            ci = len(clusters)
            clusters.append({"a": [a], "tk": set(tk)})
            for t in tk:
                index.setdefault(t, []).append(ci)
    return clusters


def outlets(c):
    return {a["d"] for a in c["a"]}


# -------------------------------------------------------------- expansion ---
def expansion_queries(c):
    lead = max(c["a"], key=lambda a: len(a["_tk"]))
    words = [w for w in SPLIT.split(lead["t"]) if len(w) >= 4 and w.lower() not in STOP][:7]
    q = " ".join(words)
    return q if len(words) >= 3 else None


def expand(c):
    q = expansion_queries(c)
    if not q:
        return []
    enc = urllib.parse.quote_plus(q)
    found = []
    for url, prov in (
        (f"https://news.google.com/rss/search?q={enc}+when:2d&hl=en-US&gl=US&ceid=US:en", "google"),
        (f"https://www.bing.com/news/search?q={enc}&format=rss", "bing"),
    ):
        data = fetch(url)
        if data:
            found.extend(parse_feed(data, prov, None, None))
    out = []
    for a in found:
        if junk(a):
            continue
        tk = tokens(a["t"])
        if sim(tk, c["tk"]) >= 0.34:
            a["_tk"] = tk
            out.append(a)
    return out


# ------------------------------------------------------------------ images ---
META = re.compile(r"<meta\s[^>]*>", re.I)
PROP = re.compile(r"""(?:property|name)\s*=\s*["']([^"']+)["']""", re.I)
CONTENT = re.compile(r"""content\s*=\s*["']([^"']+)["']""", re.I)
GENERIC = re.compile(r"(logo|placeholder|default|fallback|blank|spacer|avatar|favicon|social[-_]?share)", re.I)


def og_image(url):
    data = fetch(url, limit=96 * 1024, timeout=8)
    if not data:
        return None
    text = data.decode("utf-8", "ignore")
    og = tw = None
    for m in META.finditer(text):
        tag = m.group(0)
        p = PROP.search(tag)
        cnt = CONTENT.search(tag)
        if not p or not cnt:
            continue
        prop = p.group(1).lower()
        if prop in ("og:image", "og:image:secure_url", "og:image:url"):
            og = og or cnt.group(1)
        elif prop in ("twitter:image", "twitter:image:src"):
            tw = tw or cnt.group(1)
    raw = og or tw
    if not raw:
        return None
    img = urllib.parse.urljoin(url, html.unescape(raw.strip()))
    if img.startswith("http://"):
        img = "https://" + img[7:]
    if not img.startswith("https://") or GENERIC.search(img.rsplit("/", 1)[-1]):
        return None
    return img


# ---------------------------------------------------------------- topics ---
LEXICON = {
    "ai": ["artificial intelligence", " ai ", "openai", "chatgpt", "anthropic", "llm", "machine learning", "deepmind", "chatbot"],
    "technology": ["apple", "google", "microsoft", "iphone", "android", "samsung", "software", "chip", "cyber", "smartphone", "tech"],
    "space": ["nasa", "spacex", "rocket", "orbit", "astronaut", "mars", "satellite", "telescope"],
    "science": ["scientist", "study finds", "research", "physics", "species", "fossil", "quantum"],
    "health": ["health", "hospital", "vaccine", "cancer", "disease", "virus", "outbreak", "medical", "drug"],
    "sports": ["football", "soccer", "nba", "nfl", "cricket", "tennis", "golf", "olympic", "league", "championship", "world cup", "f1"],
    "entertainment": ["film", "movie", "box office", "netflix", "album", "singer", "actor", "celebrity", "oscar"],
    "finance": ["stock", "nasdaq", "dow ", "bitcoin", "crypto", "interest rate", "fed ", "central bank", "inflation"],
    "business": ["company", "ceo", "earnings", "profit", "merger", "acquisition", "layoffs", "tariff", "economy"],
    "politics": ["election", "parliament", "senate", "congress", "president", "prime minister", "minister", "campaign", "lawmakers"],
    "world": ["war", "ukraine", "gaza", "israel", "russia", "united nations", "nato", "ceasefire", "summit"],
    "environment": ["climate", "emission", "wildfire", "flood", "drought", "heatwave", "hurricane", "storm"],
    "crime": ["police", "arrest", "court", "trial", "murder", "shooting", "sentenced", "lawsuit"],
    "energy": ["oil price", "opec", "natural gas", "solar", "nuclear plant", "power grid"],
}


def topic_of(c):
    votes = {}
    for a in c["a"]:
        if a.get("h"):
            votes[a["h"]] = votes.get(a["h"], 0) + 2
    text = " " + " ".join(a["t"].lower() for a in c["a"][:6]) + " "
    for cat, words in LEXICON.items():
        hits = sum(1 for w in words if w in text)
        if hits:
            votes[cat] = votes.get(cat, 0) + hits
    return max(votes, key=votes.get) if votes else "general"


# ------------------------------------------------------------------- main ---
def main():
    OUT.mkdir(parents=True, exist_ok=True)
    catalog = load_catalog()
    state_path = OUT / "state.json.gz"
    state = {"og": {}}
    if state_path.exists():
        try:
            state = json.loads(gzip.decompress(state_path.read_bytes()))
        except Exception:
            pass
    og_cache = state.setdefault("og", {})

    feeds = feed_list(catalog)
    t0 = time.time()
    with ThreadPoolExecutor(WORKERS) as ex:
        results = list(ex.map(fetch_feed, feeds))
    raw = [a for r in results for a in r]
    print(f"fetched {len(feeds)} feeds -> {len(raw)} items in {time.time() - t0:.0f}s", flush=True)

    seen, articles = set(), []
    for a in raw:
        if a["u"] in seen or junk(a):
            continue
        seen.add(a["u"])
        articles.append(a)
    clusters = cluster(articles)
    clusters.sort(key=lambda c: -len(outlets(c)))
    print(f"{len(articles)} articles -> {len(clusters)} stories", flush=True)

    # Expand the biggest stories with targeted searches (more outlets each).
    top = [c for c in clusters[:400] if len(outlets(c)) >= 2]
    t0 = time.time()
    with ThreadPoolExecutor(24) as ex:
        extra = list(ex.map(expand, top))
    for c, more in zip(top, extra):
        have = {a["u"] for a in c["a"]}
        for a in more:
            if a["u"] not in have:
                have.add(a["u"])
                c["a"].append(a)
    print(f"expanded {len(top)} stories in {time.time() - t0:.0f}s", flush=True)

    clusters = [c for c in clusters if len(outlets(c)) >= 2 or any(x["v"] == "rss" for x in c["a"])]
    clusters.sort(key=lambda c: -(math.log2(1 + len(outlets(c))) * 2 + max((a["p"] or 0) for a in c["a"]) / 86400))
    clusters = clusters[:700]

    # Real photos: feed media first, else og:image of the article pages
    # (Google links are wrappers, so use publisher / Bing URLs).
    def pick_image(c):
        for a in c["a"]:
            if a.get("i"):
                return a["i"]
        cands = [a["u"] for a in c["a"] if a["v"] != "google"][:3]
        if not cands:
            # Google links are wrappers: find the same article on Bing to get
            # a real page URL (and Bing's own thumbnail as a backup).
            lead = c["a"][0]
            data = fetch("https://www.bing.com/news/search?q=" + urllib.parse.quote_plus(lead["t"]) + "&format=rss")
            for b in (parse_feed(data, "bing", None, None) if data else [])[:4]:
                if sim(tokens(b["t"]), c["tk"]) >= 0.45:
                    cands.append(b["u"])
                    if b.get("i"):
                        c.setdefault("_thumb", b["i"])
        for u in cands:
            if u in og_cache:
                if og_cache[u]:
                    return og_cache[u]
                continue
            img = og_image(u)
            og_cache[u] = img
            if img:
                return img
        return c.get("_thumb")

    t0 = time.time()
    with ThreadPoolExecutor(32) as ex:
        images = list(ex.map(pick_image, clusters))
    print(f"images: {sum(1 for i in images if i)}/{len(clusters)} in {time.time() - t0:.0f}s", flush=True)

    used_images = set()
    stories = []
    for c, img in zip(clusters, images):
        arts = []
        doms = set()
        for a in sorted(c["a"], key=lambda a: -(a["p"] or 0)):
            if a["d"] in doms:
                continue
            doms.add(a["d"])
            arts.append({k: a[k] for k in ("t", "u", "s", "d", "p", "i", "v", "n") if a.get(k)})
            if len(arts) >= 60:
                break
        if img in used_images:
            img = None
        if img:
            used_images.add(img)
        lead = arts[0]
        sid = hashlib.sha1(("|".join(sorted(a["u"] for a in arts[:3]))).encode()).hexdigest()[:16]
        stories.append({
            "id": sid,
            "c": topic_of(c),
            "img": img,
            "g": sorted({a.get("g") for a in c["a"] if a.get("g")}),
            "a": arts,
            "t": lead["t"],
        })

    feed = {"v": 1, "at": int(NOW), "n": len(stories), "stories": stories}
    blob = gzip.compress(json.dumps(feed, separators=(",", ":"), ensure_ascii=False).encode("utf-8"), 9)
    (OUT / "feed.json.gz").write_bytes(blob)
    # Keep the og cache bounded.
    if len(og_cache) > 20000:
        og_cache = dict(list(og_cache.items())[-15000:])
    state["og"] = og_cache
    state_path.write_bytes(gzip.compress(json.dumps(state).encode("utf-8")))
    avg = sum(len(s["a"]) for s in stories) / max(1, len(stories))
    big = sum(1 for s in stories if len(s["a"]) >= 20)
    print(f"wrote {len(stories)} stories, {len(blob) // 1024} KB gz, avg {avg:.1f} outlets/story, {big} with 20+", flush=True)


if __name__ == "__main__":
    sys.exit(main())
