import 'provider_health.dart';
import 'net.dart';

class Quote {
  Quote(this.label, this.price, this.changePct, {this.symbol = '', this.name, this.currency});
  final String label;
  final double price;
  final double changePct;
  final String symbol;
  final String? name;
  final String? currency;

  bool get bigMove => changePct.abs() >= 3;
}

class SymbolMatch {
  SymbolMatch(this.symbol, this.name, this.type);
  final String symbol;
  final String name;
  final String type;
}

/// Market data from Yahoo Finance's public endpoints (no key). Unofficial,
/// so every failure is tolerated and the UI simply hides what's missing.
class Markets {
  static const indices = <String, String>{
    '^GSPC': 'S&P 500',
    '^IXIC': 'Nasdaq',
    '^DJI': 'Dow',
    '^FTSE': 'FTSE 100',
    '^N225': 'Nikkei',
    'BTC-USD': 'Bitcoin',
    'GC=F': 'Gold',
    'CL=F': 'Oil',
    'EURUSD=X': 'EUR/USD',
  };

  /// Default watchlist for new users.
  static const defaultWatchlist = ['NVDA', 'AAPL', 'MSFT', 'TSLA', 'AMZN', 'GOOGL', 'META', 'BTC-USD'];

  static final _symbolRe = RegExp(r'^[A-Za-z0-9.^=\-]{1,15}$');
  static bool isValidSymbol(String s) => _symbolRe.hasMatch(s);

  static List<Quote>? _cache;
  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);
  static final Map<String, (DateTime, Quote)> _quoteCache = {};
  static bool enabled = true;

  static Quote? parseChart(String label, dynamic json, {String symbol = ''}) {
    if (json is! Map) return null;
    final chart = json['chart'];
    final results = chart is Map ? chart['result'] : null;
    if (results is! List || results.isEmpty || results.first is! Map) return null;
    final meta = (results.first as Map)['meta'];
    if (meta is! Map) return null;
    final price = (meta['regularMarketPrice'] as num?)?.toDouble();
    final prev = ((meta['chartPreviousClose'] ?? meta['previousClose']) as num?)?.toDouble();
    if (price == null || prev == null || prev == 0) return null;
    final name = (meta['shortName'] ?? meta['longName'])?.toString();
    return Quote(label, price, (price - prev) / prev * 100,
        symbol: symbol, name: name, currency: meta['currency']?.toString());
  }

  /// Closing prices for a sparkline / chart.
  static List<double> parseCloses(dynamic json) {
    if (json is! Map) return const [];
    final chart = json['chart'];
    final results = chart is Map ? chart['result'] : null;
    if (results is! List || results.isEmpty || results.first is! Map) return const [];
    final ind = (results.first as Map)['indicators'];
    final quote = ind is Map ? ind['quote'] : null;
    if (quote is! List || quote.isEmpty || quote.first is! Map) return const [];
    final closes = (quote.first as Map)['close'];
    if (closes is! List) return const [];
    return closes.whereType<num>().map((n) => n.toDouble()).toList();
  }

  static Future<dynamic> _chart(String symbol, {String range = '1d', String interval = '1d'}) {
    final url = 'https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(symbol)}'
        '?range=$range&interval=$interval';
    return ProviderHealth.instance.run('yahoo', () => Net.getJson(url, useCache: false));
  }

  static Future<Quote?> quote(String symbol, {String? label}) async {
    if (!enabled || !isValidSymbol(symbol)) return null;
    final hit = _quoteCache[symbol];
    if (hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 3)) return hit.$2;
    try {
      final q = parseChart(label ?? symbol, await _chart(symbol), symbol: symbol);
      if (q != null) _quoteCache[symbol] = (DateTime.now(), q);
      return q;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Quote>> quotes(List<String> symbols) async =>
      (await Future.wait(symbols.map((s) => quote(s, label: indices[s])))).whereType<Quote>().toList();

  /// Index strip (cached 5 minutes).
  static Future<List<Quote>> load() async {
    if (!enabled) return const [];
    if (_cache != null && DateTime.now().difference(_at) < const Duration(minutes: 5)) return _cache!;
    final q = await quotes(indices.keys.toList());
    if (q.isNotEmpty) {
      _cache = q;
      _at = DateTime.now();
    }
    return q;
  }

  /// One-month daily closes for a symbol's chart.
  static Future<List<double>> history(String symbol, {String range = '1mo'}) async {
    if (!enabled || !isValidSymbol(symbol)) return const [];
    try {
      final interval = range == '1d' ? '5m' : (range == '5d' ? '30m' : '1d');
      return parseCloses(await _chart(symbol, range: range, interval: interval));
    } catch (_) {
      return const [];
    }
  }

  /// Find a stock / ETF / crypto by name or ticker ("nvidia" -> NVDA).
  static Future<List<SymbolMatch>> search(String q) async {
    if (!enabled || q.trim().length < 2) return const [];
    try {
      final url = 'https://query1.finance.yahoo.com/v1/finance/search'
          '?q=${Uri.encodeQueryComponent(q.trim())}&quotesCount=10&newsCount=0';
      final json = await ProviderHealth.instance.run('yahoo', () => Net.getJson(url, useCache: false));
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
