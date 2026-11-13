"""Market snapshot for the app's Markets tab.

Phones get rate-limited by Yahoo Finance quickly (and a whole home network
shares one limit), so the crawler fetches the data the Markets tab opens with
every few minutes from GitHub's servers and publishes it as one small file.

The output maps the exact Yahoo request path the app would call to Yahoo's
JSON answer (trimmed to the fields the app reads), so the app can answer
those calls from the snapshot instantly and only go live for anything else.
Standard library only.
"""

import datetime
import gzip
import http.cookiejar
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
ERRORS = {}
JAR = http.cookiejar.CookieJar()
OPENER = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(JAR))
CRUMB = None


def session():
    """Yahoo answers servers in data centres only with a session cookie and a
    matching "crumb" (the same handshake yfinance and browsers do)."""
    global CRUMB
    for url in ("https://fc.yahoo.com", "https://finance.yahoo.com/"):
        try:
            OPENER.open(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=10).read(1000)
        except Exception:  # noqa: BLE001 - fc.yahoo.com answers 404 but sets the cookie
            pass
    for host in (HOST2, HOST):
        try:
            req = urllib.request.Request(host + "/v1/test/getcrumb", headers={"User-Agent": UA})
            c = OPENER.open(req, timeout=10).read(200).decode().strip()
            if c and "<" not in c and len(c) < 40:
                CRUMB = c
                return
        except Exception as e:  # noqa: BLE001
            ERRORS[f"crumb {getattr(e, 'code', type(e).__name__)}"] = ERRORS.get(f"crumb {getattr(e, 'code', type(e).__name__)}", 0) + 1


def get(path):
    """One try per Yahoo server. After 6 failures in a row Yahoo is blocking
    this runner, so stop asking (the app falls back to live data)."""
    global FAILS
    if FAILS >= 6:
        return None
    full = path + (("&" if "?" in path else "?") + "crumb=" + urllib.parse.quote(CRUMB) if CRUMB else "")
    for host in (HOST, HOST2):
        try:
            req = urllib.request.Request(host + full, headers={"User-Agent": UA, "Accept": "application/json"})
            with OPENER.open(req, timeout=10) as r:
                FAILS = 0
                return json.loads(r.read(3_000_000))
        except Exception as e:  # noqa: BLE001 - any failure: next host
            k = str(getattr(e, "code", type(e).__name__))
            ERRORS[k] = ERRORS.get(k, 0) + 1
            time.sleep(1 if k == "429" else 0.2)
    FAILS += 1
    return None


# CNBC's public quote service: backup when Yahoo refuses GitHub's servers.
CNBC_SYMBOL = {
    "^GSPC": ".SPX", "^DJI": ".DJI", "^IXIC": ".IXIC", "^RUT": ".RUT", "^VIX": ".VIX",
    "GC=F": "@GC.1", "CL=F": "@CL.1", "BTC-USD": "BTC.CM=", "EURUSD=X": "EUR=",
    "^TNX": "US10Y", "^FTSE": ".FTSE", "^N225": ".N225",
}


def _num(v):
    try:
        return float(str(v).replace(",", "").replace("%", ""))
    except (TypeError, ValueError):
        return None


def _cnbc_json(url):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read(3_000_000))
    except Exception as e:  # noqa: BLE001
        k = f"cnbc {getattr(e, 'code', type(e).__name__)}"
        ERRORS[k] = ERRORS.get(k, 0) + 1
        return None


def cnbc_charts(symbols):
    """Yahoo-shaped chart answers built from CNBC quotes + 1-day bars."""
    want = {CNBC_SYMBOL.get(s, s): s for s in symbols}
    out = {}
    q = _cnbc_json("https://quote.cnbc.com/quote-html-webservice/restQuote/symbolType/symbol?symbols="
                   + urllib.parse.quote("|".join(want), safe="")
                   + "&requestMethod=itv&noform=1&partnerId=2&fund=1&exthrs=1&output=json&events=1")
    try:
        quotes = q["FormattedQuoteResult"]["FormattedQuote"]
    except (KeyError, TypeError):
        return out
    for item in quotes:
        ysym = want.get(item.get("symbol"))
        price, prev = _num(item.get("last")), _num(item.get("previous_day_closing"))
        if not ysym or item.get("code") != 0 or price is None or not prev:
            continue
        try:
            ts = int(datetime.datetime.fromisoformat(item["last_time"].replace(".000", "")).timestamp())
        except (KeyError, ValueError):
            ts = int(time.time())
        times, closes = [], []
        bars = _cnbc_json("https://ts-api.cnbc.com/harmony/app/charts/1D.json?symbol="
                          + urllib.parse.quote(item["symbol"], safe=""))
        try:
            pb = bars["barData"]["priceBars"]
            for b in pb[::5]:  # 1-minute bars -> every 5 minutes, like Yahoo's 5m
                c = _num(b.get("close"))
                if c is not None:
                    times.append(int(b["tradeTimeinMills"]) // 1000)
                    closes.append(c)
        except (KeyError, TypeError, ValueError):
            pass
        time.sleep(0.2)
        vol = _num(item.get("volume"))
        meta = {
            "symbol": ysym, "regularMarketPrice": price, "chartPreviousClose": prev,
            "previousClose": prev, "longName": item.get("name"), "shortName": item.get("shortName"),
            "currency": item.get("currencyCode"), "regularMarketDayHigh": _num(item.get("high")),
            "regularMarketDayLow": _num(item.get("low")),
            "regularMarketVolume": int(vol) if vol is not None else None,
            "fiftyTwoWeekHigh": _num(item.get("yrhiprice")), "fiftyTwoWeekLow": _num(item.get("yrloprice")),
            "fullExchangeName": item.get("exchange"), "regularMarketTime": ts,
        }
        out[chart_path(ysym)] = {"chart": {"result": [{
            "meta": {k: v for k, v in meta.items() if v is not None},
            "timestamp": times,
            "indicators": {"quote": [{"close": closes, "open": [_num(item.get("open"))]}]},
        }]}}
    return out


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
    session()
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
    missing = []
    for s in syms:
        j = get(chart_path(s))
        c = trim_chart(j) if j else None
        if c:
            out[chart_path(s)] = c
        else:
            missing.append(s)
        time.sleep(0.3)
    if missing:
        backup = cnbc_charts(missing)
        out.update(backup)
        print(f"markets: {len(backup)}/{len(missing)} from CNBC backup")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    data = json.dumps({"v": 1, "at": int(time.time()), "r": out}, separators=(",", ":")).encode()
    with gzip.open(OUT, "wb") as f:
        f.write(data)
    print(f"markets: {len(out)} answers ({len(syms)} symbols), {len(data) // 1024} KB, {time.time() - t0:.0f}s,"
          f" crumb={'yes' if CRUMB else 'no'}, errors={ERRORS}")


if __name__ == "__main__":
    main()
