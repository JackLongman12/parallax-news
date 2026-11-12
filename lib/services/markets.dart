import 'provider_health.dart';
import 'net.dart';

class Quote {
  Quote(this.label, this.price, this.changePct);
  final String label;
  final double price;
  final double changePct;
}

/// Live market snapshot from Yahoo Finance's public chart endpoint (no key).
/// Unofficial, so every failure is tolerated: the strip just hides.
class Markets {
  static const symbols = <String, String>{
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

  static List<Quote>? _cache;
  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);
  static bool enabled = true;

  static Quote? parseChart(String label, dynamic json) {
    if (json is! Map) return null;
    final chart = json['chart'];
    final results = chart is Map ? chart['result'] : null;
    if (results is! List || results.isEmpty || results.first is! Map) return null;
    final meta = (results.first as Map)['meta'];
    if (meta is! Map) return null;
    final price = (meta['regularMarketPrice'] as num?)?.toDouble();
    final prev = ((meta['chartPreviousClose'] ?? meta['previousClose']) as num?)?.toDouble();
    if (price == null || prev == null || prev == 0) return null;
    return Quote(label, price, (price - prev) / prev * 100);
  }

  static Future<List<Quote>> load() async {
    if (!enabled) return const [];
    if (_cache != null && DateTime.now().difference(_at) < const Duration(minutes: 5)) return _cache!;
    final futures = symbols.entries.map((e) async {
      try {
        final url = 'https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(e.key)}?range=1d&interval=1d';
        final json = await ProviderHealth.instance.run('yahoo', () => Net.getJson(url, useCache: false));
        return parseChart(e.value, json);
      } catch (_) {
        return null;
      }
    });
    final quotes = (await Future.wait(futures)).whereType<Quote>().toList();
    if (quotes.isNotEmpty) {
      _cache = quotes;
      _at = DateTime.now();
    }
    return quotes;
  }
}
