#!/usr/bin/env python3
"""Download one public-domain / CC0 photo per topic from Wikimedia Commons
into assets/topics/<category>.jpg (bundled default images, shown offline).

Only images whose licence is Public Domain or CC0 are accepted, so no
attribution is legally required (credits are still written to CREDITS.txt).
"""
import json
import pathlib
import re
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/topics"
UA = "ParallaxNews-asset-fetch/1.0 (open-source news app)"

QUERIES = {
    "general": ["newspapers stack", "city skyline night"],
    "politics": ["parliament chamber", "capitol building"],
    "world": ["united nations headquarters", "earth from space"],
    "business": ["skyscrapers business district", "container ship port"],
    "technology": ["circuit board macro", "server room"],
    "ai": ["robot", "computer chip"],
    "science": ["laboratory glassware", "microscope"],
    "space": ["rocket launch", "nebula hubble"],
    "health": ["stethoscope", "hospital corridor"],
    "sports": ["stadium", "running track athletics"],
    "entertainment": ["cinema seats", "concert stage"],
    "gaming": ["video game controller", "arcade machines"],
    "environment": ["wind turbines", "forest"],
    "crime": ["courtroom", "police car"],
    "education": ["university campus building", "library bookshelves"],
    "finance": ["Wall Street sign New York", "trading floor screens"],
    "autos": ["electric car charging station", "modern car on road"],
    "travel": ["airplane wing sky", "mountain lake"],
    "lifestyle": ["coffee cup", "yoga"],
    "local": ["main street town", "town hall"],
    "energy": ["solar panels", "power lines"],
    "realEstate": ["suburban houses street", "modern apartment building"],
    "defense": ["fighter jet flying", "navy destroyer at sea"],
    "labor": ["construction workers site", "warehouse workers"],
    "weather": ["storm clouds", "lightning"],
}

OK_LICENCE = re.compile(r"^(public domain|pd|cc0)", re.I)


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def find(query: str):
    params = {
        "action": "query", "format": "json", "generator": "search", "gsrnamespace": "6",
        "gsrlimit": "25", "gsrsearch": f"filetype:bitmap {query}",
        "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata", "iiurlwidth": "720",
    }
    data = json.loads(get("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)))
    pages = sorted(data.get("query", {}).get("pages", {}).values(), key=lambda p: p.get("index", 999))
    for p in pages:
        info = (p.get("imageinfo") or [{}])[0]
        meta = info.get("extmetadata", {})
        lic = meta.get("LicenseShortName", {}).get("value", "")
        if not OK_LICENCE.match(lic.strip()):
            continue
        if info.get("width", 0) < 900 or info.get("height", 0) < 500 or not info.get("mime", "").startswith("image/jpeg"):
            continue
        title = p.get("title", "")
        if re.search(r"(map|logo|flag|diagram|chart|seal|coat of arms|icon|painting|poster|LC-|1[89]\d\d|\(19\d\d\))", title, re.I):
            continue
        return info["thumburl"], title, lic
    return None


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    credits = []
    old = (OUT / "CREDITS.txt").read_text(encoding="utf-8").splitlines()[1:] if (OUT / "CREDITS.txt").exists() else []
    credits.extend(old)
    for cat, queries in QUERIES.items():
        if (OUT / f"{cat}.jpg").exists():
            continue  # resume: already downloaded
        hit = None
        for q in queries:
            hit = find(q)
            if hit:
                break
            time.sleep(4)
        if not hit:
            print("no image for", cat)
            continue
        url, title, lic = hit
        (OUT / f"{cat}.jpg").write_bytes(get(url))
        credits.append(f"{cat}.jpg: {title} ({lic}) https://commons.wikimedia.org/wiki/{urllib.parse.quote(title.replace(' ', '_'))}")
        print("ok", cat, lic, title[:60])
        time.sleep(4)
    (OUT / "CREDITS.txt").write_text("Default topic images (Wikimedia Commons, public domain / CC0):\n" + "\n".join(credits) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
