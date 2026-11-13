"""Market snapshot for the app's Markets tab.

Phones get rate-limited by Yahoo Finance quickly (and a whole home network
shares one limit), so the crawler fetches the data the Markets tab opens with
every few minutes from GitHub's servers and publishes it as one small file.

The output maps the exact Yahoo request path the app would call to Yahoo's
JSON answer (trimmed to the fields the app reads), so the app can answer
those calls from the snapshot instantly and only go live for anything else.
Standard library only.
"""

import gzip
import json
import os
import time
import urllib.parse
import urllib.request

HOST = "https://query1.finance.yahoo.com"
HOST2 = "https://query2.finance.yahoo.com"
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36"
OUT = os.path.join(os.path.dirname(__file__), "out", "markets.json.gz")

# Must match lib/services/markets.dart (indices + defaultWatchlist).
INDICES = ["^GSPC", "^DJI", "^IXIC", "^RUT", "^VIX", "GC=F", "CL=F", "BTC-USD",
           "EURUSD=X", "^TNX", "^FTSE", "^N225"]
WATCHLIST = ["NVDA", "AAPL", "MSFT", "TSLA", "AMZN", "GOOGL", "META", "BTC-USD"]
SCREENS = ["day_gainers", "day_losers", "most_actives"]

META_KEYS = {
    "regularMarketPrice", "chartPreviousClose", "previousClose", "longName", "shortName",
    "currency", "regularMarketDayHigh", "regularMarketDayLow", "regularMarketVolume",
    "fiftyTwoWeekHigh", "fiftyTwoWeekLow", "fullExchangeName", "exchangeName",
    "regularMarketTime", "symbol",
}


FAILS = 0


def get(path):
    """One try per Yahoo server. After 6 failures in a row Yahoo is blocking
    this runner, so stop asking (the app falls back to live data)."""
    global FAILS
    if FAILS >= 6:
        return None
    for host in (HOST, HOST2):
        try:
            req = urllib.request.Request(host + path, headers={"User-Agent": UA, "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=10) as r:
                FAILS = 0
                return json.loads(r.read(3_000_000))
        except Exception as e:  # noqa: BLE001 - any failure: next host
            time.sleep(1 if getattr(e, "code", None) == 429 else 0.2)
    FAILS += 1
    return None


def chart_path(sym):
    # Same encoding as Dart's Uri.encodeComponent for these symbols.
    return "/v8/finance/chart/" + urllib.parse.quote(sym, safe="") + "?range=1d&interval=5m"


def trim_chart(j):
    try:
        res = j["chart"]["result"][0]
        q = res["indicators"]["quote"][0]
        return {"chart": {"result": [{
            "meta": {k: v for k, v in res["meta"].items() if k in META_KEYS},
            "timestamp": res.get("timestamp", []),
            "indicators": {"quote": [{"close": q.get("close", []), "open": q.get("open", [])[:1]}]},
        }]}}
    except (KeyError, IndexError, TypeError):
        return None


def main():
    t0 = time.time()
    out = {}
    trending_path = "/v1/finance/trending/US?count=12"
    tr = get(trending_path)
    trending = []
    if tr:
        out[trending_path] = tr
        try:
            trending = [q["symbol"] for q in tr["finance"]["result"][0]["quotes"]][:8]
        except (KeyError, IndexError, TypeError):
            pass
    for s in SCREENS:
        p = f"/v1/finance/screener/predefined/saved?scrIds={s}&count=10"
        j = get(p)
        if j:
            out[p] = j
        time.sleep(0.3)
    syms = list(dict.fromkeys(INDICES + WATCHLIST + trending))
    for s in syms:
        j = get(chart_path(s))
        c = trim_chart(j) if j else None
        if c:
            out[chart_path(s)] = c
        time.sleep(0.3)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    data = json.dumps({"v": 1, "at": int(time.time()), "r": out}, separators=(",", ":")).encode()
    with gzip.open(OUT, "wb") as f:
        f.write(data)
    print(f"markets: {len(out)} answers ({len(syms)} symbols), {len(data) // 1024} KB, {time.time() - t0:.0f}s")


if __name__ == "__main__":
    main()
