#!/usr/bin/env python3
"""Build assets/topics/variants.json: 14 extra curated photos per topic.

Only Wikimedia Commons images that are Public Domain or CC0, modern (no old
years / archive codes / paintings / posters / maps / logos), landscape and
large are accepted. The app downloads them once and caches them; the bundled
<topic>.jpg stays as the offline default.
"""
import json
import pathlib
import re
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/topics/variants.json"
UA = "ParallaxNews-asset-fetch/1.0 (open-source news app)"
PER_TOPIC = 14

QUERIES = {
    "general": ["newspapers", "city skyline", "news reporters microphones", "crowd street city"],
    "politics": ["parliament building", "capitol building", "voting ballot box", "parliament chamber", "politician speech podium"],
    "world": ["united nations", "flags of countries", "earth from space", "international summit leaders"],
    "business": ["office skyscrapers", "container ship", "business meeting office", "shopping mall", "factory production line"],
    "technology": ["circuit board", "data center servers", "smartphone", "laptop computer", "fiber optic cables"],
    "ai": ["humanoid robot", "industrial robot arm", "computer processor chip", "supercomputer"],
    "science": ["laboratory scientist", "microscope", "particle accelerator", "telescope observatory", "test tubes laboratory"],
    "space": ["rocket launch", "nebula", "international space station", "galaxy", "astronaut spacewalk"],
    "health": ["hospital", "stethoscope", "surgery operating room", "medical laboratory", "nurse hospital"],
    "sports": ["football stadium", "basketball game", "tennis court match", "athletics running race", "cyclists race"],
    "entertainment": ["concert stage lights", "cinema theatre", "film set camera", "music festival crowd"],
    "gaming": ["video game controller", "esports tournament", "arcade games", "gaming computer"],
    "environment": ["wind turbines", "forest", "glacier", "wildfire", "coral reef"],
    "crime": ["courtroom", "police car", "police officers", "prison"],
    "education": ["university campus", "library interior", "classroom", "students lecture hall"],
    "finance": ["stock exchange", "banknotes", "bank building", "trading floor"],
    "autos": ["electric car charging", "sports car", "highway traffic", "car factory"],
    "travel": ["airport terminal", "airplane", "beach resort", "mountain landscape", "train station"],
    "lifestyle": ["coffee cafe", "yoga", "restaurant food plate", "fashion show"],
    "local": ["town hall", "main street", "town square", "community park", "farmers market"],
    "energy": ["solar panels", "power lines", "oil refinery", "nuclear power plant", "wind farm"],
    "realEstate": ["apartment building", "suburban houses", "construction crane", "modern house"],
    "defense": ["fighter jet", "navy ship", "military helicopter", "tank military vehicle"],
    "labor": ["construction workers", "warehouse workers", "factory workers", "office workers"],
    "weather": ["storm clouds", "lightning", "snowstorm", "rainbow", "flood"],
}

OK_LICENCE = re.compile(r"^(public domain|pd|cc0|cc by(-sa)? [1-4]\.\d)", re.I)
BAD_TITLE = re.compile(
    r"(map|logo|flag of|coat of arms|diagram|chart|seal|signature|icon|painting|poster|drawing|illustration|"
    r"engraving|LC-|\b1[0-9]\d\d\b|\(19\d\d\)|svg|scan|stamp|banknote of 19)", re.I)


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(20 * (attempt + 1))
                continue
            raise
    raise RuntimeError("rate limited")


def candidates(query: str):
    params = {
        "action": "query", "format": "json", "generator": "search", "gsrnamespace": "6",
        "gsrlimit": "40", "gsrsearch": f"filetype:bitmap {query}",
        "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata", "iiurlwidth": "960",
    }
    data = json.loads(get("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)))
    pages = sorted(data.get("query", {}).get("pages", {}).values(), key=lambda p: p.get("index", 999))
    for p in pages:
        info = (p.get("imageinfo") or [{}])[0]
        lic = info.get("extmetadata", {}).get("LicenseShortName", {}).get("value", "").strip()
        w, h = info.get("width", 0), info.get("height", 0)
        if not OK_LICENCE.match(lic) or not info.get("mime", "").startswith("image/jpeg"):
            continue
        if w < 1000 or h < 560 or w < h * 1.15:  # large, landscape
            continue
        if BAD_TITLE.search(p.get("title", "")):
            continue
        url = info.get("thumburl", "")
        artist = re.sub(r"<[^>]+>", "", info.get("extmetadata", {}).get("Artist", {}).get("value", "")).strip()
        artist = re.sub(r"\s+", " ", artist)[:60] or "Wikimedia Commons"
        if url.startswith(("https://upload.wikimedia.org/", "https://thumb.wikimedia.org/")):
            yield url, f"{artist} / {lic}", lic


def main() -> None:
    out = {}
    if OUT.exists():
        out = {k: v for k, v in json.loads(OUT.read_text(encoding="utf-8")).items() if v}
    for cat, queries in QUERIES.items():
        if len(out.get(cat, [])) >= PER_TOPIC:
            continue
        picked, seen = [], set()
        per_query = max(3, PER_TOPIC // len(queries) + 1)
        for q in queries:
            n = 0
            for url, credit, lic in candidates(q):
                if url in seen:
                    continue
                seen.add(url)
                picked.append({"u": url, "c": credit})
                n += 1
                if n >= per_query or len(picked) >= PER_TOPIC:
                    break
            time.sleep(3)
            if len(picked) >= PER_TOPIC:
                break
        out[cat] = picked
        OUT.write_text(json.dumps(out, indent=1), encoding="utf-8")
        print(cat, len(picked))


if __name__ == "__main__":
    main()
