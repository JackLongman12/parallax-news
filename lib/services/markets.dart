import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'crawler_feed.dart';
import 'provider_health.dart';
import 'net.dart';

/// A quote as Yahoo Finance reports it (all values from Yahoo's own data).
class Quote {
  Quote(
    this.label,
    this.price,
    this.changePct, {
    this.symbol = '',
    this.name,
    this.currency,
    this.prevClose,
    this.open,
    this.dayHigh,
    this.dayLow,
    this.volume,
    this.yearHigh,
    this.yearLow,
    this.exchange,
    this.marketTime,
    this.spark = const [],
  });

  final String label;
  final double price;
  final double changePct;
  final String symbol;
  final String? name;
  final String? currency;
  final double? prevClose;
  final double? open;
  final double? dayHigh;
  final double? dayLow;
  final int? volume;
  final double? yearHigh;
  final double? yearLow;
  final String? exchange;
  final DateTime? marketTime;

  /// Intraday prices for a mini chart.
  final List<double> spark;

  double? get change => prevClose == null ? null : price - prevClose!;
  bool get bigMove => changePct.abs() >= 3;
}

class SymbolMatch {
  SymbolMatch(this.symbol, this.name, this.type);
  final String symbol;
  final String name;
  final String type;
}

class History {
  History(this.times, this.closes, {this.prevClose});
  final List<DateTime> times;
  final List<double> closes;
  final double? prevClose;
  bool get isEmpty => closes.length < 2;
}

/// Market data from Yahoo Finance's public chart / search / trending
/// endpoints (no key). Unofficial: every failure is tolerated and the UI
/// hides what is missing rather than showing wrong numbers.
class Markets {
  static const indices = <String, String>{
    '^GSPC': 'S&P 500',
    '^DJI': 'Dow 30',
    '^IXIC': 'Nasdaq',
    '^RUT': 'Russell 2000',
    '^VIX': 'VIX',
    'GC=F': 'Gold',
    'CL=F': 'Crude Oil',
    'BTC-USD': 'Bitcoin',
    'EURUSD=X': 'EUR/USD',
    '^TNX': '10-Yr Yield',
    '^FTSE': 'FTSE 100',
    '^N225': 'Nikkei 225',
  };

  static const defaultWatchlist = ['NVDA', 'AAPL', 'MSFT', 'TSLA', 'AMZN', 'GOOGL', 'META', 'BTC-USD'];

  static final _symbolRe = RegExp(r'^[A-Za-z0-9.^=\-]{1,15}$');
  static bool isValidSymbol(String s) => _symbolRe.hasMatch(s);

  static bool enabled = true;
  static final Map<String, (DateTime, Quote)> _quoteCache = {};
  static List<Quote>? _indexCache;
  static DateTime _indexAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const _host = 'https://query1.finance.yahoo.com';

  static double? _d(dynamic v) => v is num ? v.toDouble() : null;

  static Map? _result(dynamic json) {
    if (json is! Map) return null;
    final chart = json['chart'];
    final results = chart is Map ? chart['result'] : null;
    if (results is! List || results.isEmpty || results.first is! Map) return null;
    return results.first as Map;
  }

  static List<double?> _series(Map result, String key) {
    final ind = result['indicators'];
    final q = ind is Map ? ind['quote'] : null;
    if (q is! List || q.isEmpty || q.first is! Map) return const [];
    final list = (q.first as Map)[key];
    if (list is! List) return const [];
    return [for (final v in list) _d(v)];
  }

  /// Parses a chart response into a quote. Change is measured against the
  /// previous session's close, exactly as Yahoo Finance displays it.
  static Quote? parseChart(String label, dynamic json, {String symbol = ''}) {
    final res = _result(json);
    final meta = res?['meta'];
    if (res == null || meta is! Map) return null;
    final price = _d(meta['regularMarketPrice']);
    final prev = _d(meta['chartPreviousClose']) ?? _d(meta['previousClose']);
    if (price == null || prev == null || prev == 0) return null;
    final opens = _series(res, 'open').whereType<double>();
    final t = meta['regularMarketTime'];
    return Quote(
      label,
      price,
      (price - prev) / prev * 100,
      symbol: symbol,
      name: (meta['longName'] ?? meta['shortName'])?.toString(),
      currency: meta['currency']?.toString(),
      prevClose: prev,
      open: opens.isEmpty ? null : opens.first,
      dayHigh: _d(meta['regularMarketDayHigh']),
      dayLow: _d(meta['regularMarketDayLow']),
      volume: (meta['regularMarketVolume'] as num?)?.toInt(),
      yearHigh: _d(meta['fiftyTwoWeekHigh']),
      yearLow: _d(meta['fiftyTwoWeekLow']),
      exchange: (meta['fullExchangeName'] ?? meta['exchangeName'])?.toString(),
      marketTime: t is num ? DateTime.fromMillisecondsSinceEpoch(t.toInt() * 1000) : null,
      spark: _series(res, 'close').whereType<double>().toList(),
    );
  }

  /// Closing prices only (kept for older callers / tests).
  static List<double> parseCloses(dynamic json) {
    final res = _result(json);
    return res == null ? const [] : _series(res, 'close').whereType<double>().toList();
  }

  static History? parseHistory(dynamic json) {
    final res = _result(json);
    if (res == null) return null;
    final ts = res['timestamp'];
    final closes = _series(res, 'close');
    if (ts is! List) return null;
    final times = <DateTime>[];
    final vals = <double>[];
    for (var i = 0; i < ts.length && i < closes.length; i++) {
      final c = closes[i];
      final t = ts[i];
      if (c == null || t is! num) continue;
      times.add(DateTime.fromMillisecondsSinceEpoch(t.toInt() * 1000));
      vals.add(c);
    }
    final meta = res['meta'];
    return History(times, vals, prevClose: meta is Map ? _d(meta['chartPreviousClose']) : null);
  }

  // Yahoo rate-limits bursts (the Markets tab alone needs ~25 calls), so:
  // at most 3 requests at a time, identical requests share one fetch, answers
  // are reused for 45 s, and a failed call retries on Yahoo's second server,
  // then via our Cloudflare worker (if it has the /y route).
  static final _inflight = <String, Future<dynamic>>{};
  static final _cache = <String, (DateTime, dynamic)>{};
  static int _active = 0;
  static final _waiters = <Completer<void>>[];

  // ---- Snapshot from our crawler (refreshed every ~5 min on GitHub) ----
  // Holds Yahoo's answers for everything the Markets tab opens with, so the
  // tab fills instantly and works even while Yahoo rate-limits this phone.
  // Kept on disk (~100 KB) so it is there the moment the app starts.
  static const snapshotUrl = 'https://github.com/JackLongman12/parallax-news/releases/download/feed/markets.json.gz';
  static Map<String, dynamic> _snap = const {};
  static DateTime? snapshotAt; // when the crawler built it
  static DateTime _snapCheckedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void>? _snapLoading;
  static bool _diskRead = false;

  static Future<File?> _snapFile() async {
    try {
      return File('${(await getApplicationSupportDirectory()).path}/markets_snapshot.json');
    } catch (_) {
      return null;
    }
  }

  static bool _useSnap(dynamic j) {
    if (j is! Map || j['r'] is! Map || j['at'] is! num) return false;
    final at = DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt() * 1000);
    if (snapshotAt != null && !at.isAfter(snapshotAt!)) return false;
    _snap = Map<String, dynamic>.from(j['r'] as Map);
    snapshotAt = at;
    return true;
  }

  static Future<void> _ensureSnapshot() async {
    if (!_diskRead) {
      _diskRead = true;
      try {
        final f = await _snapFile();
        if (f != null && await f.exists()) _useSnap(jsonDecode(await f.readAsString()));
      } catch (_) {}
    }
    if (DateTime.now().difference(_snapCheckedAt) < const Duration(minutes: 3)) return;
    final load = _snapLoading ??= () async {
      try {
        final bytes = await Net.getBytes(snapshotUrl, timeout: const Duration(seconds: 8));
        final text = utf8.decode(gzip.decode(bytes), allowMalformed: true);
        if (_useSnap(jsonDecode(text))) {
          _snapCheckedAt = DateTime.now();
          final f = await _snapFile();
          await f?.writeAsString(text);
        }
      } catch (_) {
      } finally {
        _snapCheckedAt = DateTime.now();
        _snapLoading = null;
      }
    }();
    // With a usable snapshot on disk, don't wait for the download.
    if (_snap.isEmpty) await load;
  }

  static Future<dynamic> _get(String path) async {
    await _ensureSnapshot();
    final s = _snap[path];
    final at = snapshotAt;
    if (s != null && at != null && DateTime.now().difference(at) < const Duration(minutes: 30)) return s;
    try {
      return await _live(path);
    } catch (_) {
      if (s != null) return s; // older snapshot beats an empty screen
      // Yahoo is blocking this phone: build the chart from CNBC instead.
      final backup = await _cnbcChart(path);
      if (backup != null) return backup;
      rethrow;
    }
  }

  // ---- CNBC backup (public quote service, no key) ----
  static const _cnbcSymbol = {
    '^GSPC': '.SPX', '^DJI': '.DJI', '^IXIC': '.IXIC', '^RUT': '.RUT', '^VIX': '.VIX',
    'GC=F': '@GC.1', 'CL=F': '@CL.1', 'BTC-USD': 'BTC.CM=', 'EURUSD=X': 'EUR=',
    '^TNX': 'US10Y', '^FTSE': '.FTSE', '^N225': '.N225', 'ETH-USD': 'ETH.CM=',
  };
  static const _cnbcRange = {
    '1d': '1D', '5d': '5D', '1mo': '1M', '6mo': '6M', 'ytd': 'YTD', '1y': '1Y', '5y': '5Y', 'max': 'ALL',
  };
  static double? _n(dynamic v) => v == null ? null : double.tryParse('$v'.replaceAll(',', '').replaceAll('%', ''));
  static double? _pos(dynamic v) { final d = _n(v); return d != null && d > 0 ? d : null; } // CNBC sends 0.00 before the open

  /// A Yahoo-shaped chart answer for a /v8/finance/chart/... path, from CNBC.
  static Future<dynamic> _cnbcChart(String path) async {
    final m = RegExp(r'^/v8/finance/chart/([^?]+)\?range=(\w+)').firstMatch(path);
    if (m == null) return null;
    final sym = Uri.decodeComponent(m[1]!);
    final range = _cnbcRange[m[2]!];
    if (range == null || !isValidSymbol(sym)) return null;
    final c = _cnbcSymbol[sym] ?? (RegExp(r'^[A-Z.]{1,6}$').hasMatch(sym) ? sym : null);
    if (c == null) return null;
    try {
      final enc = Uri.encodeQueryComponent(c);
      final results = await Future.wait([
        Net.getJson('https://quote.cnbc.com/quote-html-webservice/restQuote/symbolType/symbol?symbols=$enc'
            '&requestMethod=itv&noform=1&partnerId=2&fund=1&exthrs=1&output=json&events=1', useCache: false),
        Net.getJson('https://ts-api.cnbc.com/harmony/app/charts/$range.json?symbol=$enc', useCache: false).catchError((_) => null),
      ]);
      final list = ((results[0] as Map?)?['FormattedQuoteResult'] as Map?)?['FormattedQuote'];
      final q = list is List && list.isNotEmpty && list.first is Map ? list.first as Map : null;
      final price = _n(q?['last']);
      // Before the open CNBC's previous_day_closing already equals the last
      // price; "change" still holds the latest session's move.
      final ch = _n(q?['change']);
      var prev = price != null && ch != null ? price - ch : _n(q?['previous_day_closing']);
      if (q == null || q['code'] != 0 || price == null || prev == null || prev == 0) return null;
      final times = <int>[], closes = <double>[];
      final bars = ((results[1] as Map?)?['barData'] as Map?)?['priceBars'];
      if (bars is List) {
        final step = range == '1D' ? 5 : 1; // 1-minute bars -> 5-minute, like Yahoo
        for (var i = 0; i < bars.length; i += step) {
          final b = bars[i];
          final close = b is Map ? _n(b['close']) : null;
          final t = b is Map ? b['tradeTimeinMills'] : null;
          if (close != null && t is num) {
            times.add(t.toInt() ~/ 1000);
            closes.add(close);
          }
        }
      }
      // Longer ranges are measured from the start of the range, like Yahoo.
      if (range != '1D' && closes.isNotEmpty) prev = closes.first;
      final vol = _n(q['volume']);
      return {
        'chart': {
          'result': [
            {
              'meta': {
                'symbol': sym,
                'regularMarketPrice': price,
                'chartPreviousClose': prev,
                'longName': q['name'],
                'shortName': q['shortName'],
                'currency': q['currencyCode'],
                'regularMarketDayHigh': _pos(q['high']),
                'regularMarketDayLow': _pos(q['low']),
                'regularMarketVolume': vol?.toInt(),
                'fiftyTwoWeekHigh': _n(q['yrhiprice']),
                'fiftyTwoWeekLow': _n(q['yrloprice']),
                'fullExchangeName': q['exchange'],
              },
              'timestamp': times,
              'indicators': {
                'quote': [
                  {'close': closes, 'open': [_pos(q['open'])]}
                ]
              },
            }
          ]
        }
      };
    } catch (_) {
      return null;
    }
  }

  static Future<dynamic> _live(String path) {
    final hit = _cache[path];
    if (hit != null && DateTime.now().difference(hit.$1) < const Duration(seconds: 45)) return Future.value(hit.$2);
    return _inflight[path] ??= _fetch(path).whenComplete(() => _inflight.remove(path));
  }

  static Future<dynamic> _fetch(String path) async {
    while (_active >= 3) {
      final w = Completer<void>();
      _waiters.add(w);
      await w.future;
    }
    _active++;
    try {
      final json = await ProviderHealth.instance.run('yahoo', () => _tryHosts(path));
      if (_cache.length > 150) _cache.clear();
      _cache[path] = (DateTime.now(), json);
      return json;
    } finally {
      _active--;
      if (_waiters.isNotEmpty) _waiters.removeAt(0).complete();
    }
  }

  static Future<dynamic> _tryHosts(String path) async {
    Object? first;
    for (final h in [
      _host,
      'https://query2.finance.yahoo.com',
      if (CrawlerFeed.workerUrl.startsWith('https://')) '${CrawlerFeed.workerUrl}/y',
    ]) {
      try {
        // Short timeout: a blocked host should fail fast, not stall the tab.
        return jsonDecode(await Net.getText('$h$path', useCache: false, timeout: const Duration(seconds: 5)));
      } catch (e) {
        first ??= e;
      }
    }
    throw first!;
  }

  /// Live quote incl. today's intraday line (one request).
  static Future<Quote?> quote(String symbol, {String? label}) async {
    if (!enabled || !isValidSymbol(symbol)) return null;
    final hit = _quoteCache[symbol];
    if (hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 2)) return hit.$2;
    try {
      final json = await _get('/v8/finance/chart/${Uri.encodeComponent(symbol)}?range=1d&interval=5m');
      final q = parseChart(label ?? symbol, json, symbol: symbol);
      if (q != null) _quoteCache[symbol] = (DateTime.now(), q);
      return q;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Quote>> quotes(List<String> symbols) async =>
      (await Future.wait(symbols.map((s) => quote(s, label: indices[s])))).whereType<Quote>().toList();

  /// Market summary (cached 2 minutes).
  static Future<List<Quote>> load() async {
    if (!enabled) return const [];
    if (_indexCache != null && DateTime.now().difference(_indexAt) < const Duration(minutes: 2)) return _indexCache!;
    final q = await quotes(indices.keys.toList());
    if (q.isNotEmpty) {
      _indexCache = q;
      _indexAt = DateTime.now();
    }
    return q;
  }

  static const ranges = ['1d', '5d', '1mo', '6mo', 'ytd', '1y', '5y', 'max'];
  static String _interval(String range) => switch (range) {
        '1d' => '5m',
        '5d' => '15m',
        '1mo' => '1h',
        '6mo' || 'ytd' || '1y' => '1d',
        '5y' => '1wk',
        _ => '1mo',
      };

  static Future<History?> history(String symbol, {String range = '1d'}) async {
    if (!enabled || !isValidSymbol(symbol) || !ranges.contains(range)) return null;
    try {
      return parseHistory(await _get('/v8/finance/chart/${Uri.encodeComponent(symbol)}?range=$range&interval=${_interval(range)}'));
    } catch (_) {
      return null;
    }
  }

  /// Trending tickers (Yahoo's "Trending" list).
  static Future<List<String>> trending({String region = 'US'}) async {
    if (!enabled || !RegExp(r'^[A-Z]{2}$').hasMatch(region)) return const [];
    try {
      final json = await _get('/v1/finance/trending/$region?count=12');
      final res = json is Map ? json['finance'] : null;
      final list = res is Map ? res['result'] : null;
      if (list is! List || list.isEmpty || list.first is! Map) return const [];
      final quotes = (list.first as Map)['quotes'];
      if (quotes is! List) return const [];
      return [
        for (final q in quotes.whereType<Map>())
          if (q['symbol'] is String && isValidSymbol(q['symbol'] as String)) q['symbol'] as String,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Top gainers / losers / most active (Yahoo predefined screeners).
  static Future<List<Quote>> movers(String screen) async {
    if (!enabled || !const {'day_gainers', 'day_losers', 'most_actives'}.contains(screen)) return const [];
    try {
      final json = await _get('/v1/finance/screener/predefined/saved?scrIds=$screen&count=10');
      final fin = json is Map ? json['finance'] : null;
      final list = fin is Map ? fin['result'] : null;
      if (list is! List || list.isEmpty || list.first is! Map) return const [];
      final quotes = (list.first as Map)['quotes'];
      if (quotes is! List) return const [];
      final out = <Quote>[];
      for (final q in quotes.whereType<Map>()) {
        final sym = q['symbol'];
        final price = _d(q['regularMarketPrice']);
        final pct = _d(q['regularMarketChangePercent']);
        if (sym is! String || !isValidSymbol(sym) || price == null || pct == null) continue;
        out.add(Quote(sym, price, pct,
            symbol: sym,
            name: (q['shortName'] ?? q['longName'])?.toString(),
            prevClose: _d(q['regularMarketPreviousClose']),
            volume: (q['regularMarketVolume'] as num?)?.toInt(),
            currency: q['currency']?.toString()));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Find a stock / ETF / crypto by name or ticker ("nvidia" -> NVDA).
  static Future<List<SymbolMatch>> search(String q) async {
    if (!enabled || q.trim().length < 2) return const [];
    try {
      final json = await _get('/v1/finance/search?q=${Uri.encodeQueryComponent(q.trim())}&quotesCount=10&newsCount=0');
      final list = json is Map ? json['quotes'] : null;
      if (list is! List) return const [];
      return [
        for (final m in list.whereType<Map>())
          if (m['symbol'] is String && isValidSymbol(m['symbol'] as String))
            SymbolMatch(m['symbol'] as String, '${m['shortname'] ?? m['longname'] ?? m['symbol']}', '${m['quoteType'] ?? ''}'),
      ];
    } catch (_) {
      return const [];
    }
  }
}
