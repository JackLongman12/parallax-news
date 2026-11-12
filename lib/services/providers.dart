import '../data/geo.dart';
import '../models/article.dart';
import '../models/category.dart';
import 'feed_parser.dart';
import 'net.dart';

/// Google News RSS: free, keyless, covers essentially every locality on earth
/// and tells us the real publisher of each item.
class GoogleNews {
  static const _base = 'https://news.google.com/rss';

  static Future<List<Article>> topHeadlines(Edition ed) =>
      _fetch('$_base?${ed.query}', hint: null);

  static Future<List<Article>> topic(String topicId, Edition ed, Category hint) =>
      _fetch('$_base/headlines/section/topic/$topicId?${ed.query}', hint: hint);

  /// Google's own "local news" section for a named place.
  static Future<List<Article>> geo(String placeName, Edition ed) => _fetch(
      '$_base/headlines/section/geo/${Uri.encodeComponent(placeName)}?${ed.query}',
      hint: Category.local,
      isLocal: true);

  static Future<List<Article>> search(String query, Edition ed,
          {Category? hint, bool isLocal = false}) =>
      _fetch('$_base/search?q=${Uri.encodeQueryComponent(query)}&${ed.query}',
          hint: hint, isLocal: isLocal);

  /// Latest items from one outlet — used for local outlets without an RSS feed.
  static Future<List<Article>> site(String domain, Edition ed, {bool isLocal = true}) =>
      search('site:$domain when:7d', ed, isLocal: isLocal);

  static Future<List<Article>> _fetch(String url, {Category? hint, bool isLocal = false}) async {
    final body = await Net.getText(url);
    return FeedParser.parse(body, provider: 'google', hint: hint, isLocal: isLocal);
  }
}

/// Bing News RSS: a second, independent index to widen local coverage.
class BingNews {
  static Future<List<Article>> search(String query, {String? market, bool isLocal = false}) async {
    final mkt = market == null ? '' : '&mkt=${Uri.encodeQueryComponent(market)}';
    final body = await Net.getText(
        'https://www.bing.com/news/search?q=${Uri.encodeQueryComponent(query)}&format=rss$mkt');
    return FeedParser.parse(body, provider: 'bing', isLocal: isLocal);
  }
}

/// GDELT DOC 2.0: global multilingual index (rate limited; off by default).
class Gdelt {
  static Future<List<Article>> search(String query, {String? countryCode}) async {
    final q = countryCode == null ? query : '$query sourcecountry:${_fips(countryCode)}';
    final url = 'https://api.gdeltproject.org/api/v2/doc/doc?query=${Uri.encodeQueryComponent(q)}'
        '&mode=ArtList&maxrecords=75&format=json&sort=DateDesc&timespan=3d';
    final json = await Net.getJson(url);
    final list = (json is Map ? json['articles'] : null) as List? ?? const [];
    final out = <Article>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final url = raw['url']?.toString() ?? '';
      final title = FeedParser.cleanText(raw['title']?.toString() ?? '');
      if (!isSafeWebUrl(url) || title.isEmpty) continue;
      final img = raw['socialimage']?.toString();
      out.add(Article(
        title: title,
        url: url,
        sourceName: raw['domain']?.toString() ?? domainOf(url),
        domain: domainOf(url),
        published: _gdeltDate(raw['seendate']?.toString()),
        imageUrl: _safeImage(img),
        provider: 'gdelt',
      ));
    }
    return out;
  }

  static String? _safeImage(String? img) {
    final u = img == null ? null : Uri.tryParse(img);
    return u != null && u.scheme == 'https' && isPublicHost(u.host) ? u.toString() : null;
  }

  static DateTime? _gdeltDate(String? s) {
    // Format: 20261113T101500Z
    if (s == null || s.length < 15) return null;
    return DateTime.tryParse('${s.substring(0, 8)}T${s.substring(9, 15)}Z');
  }

  // GDELT uses FIPS country codes; most match ISO, a few common ones differ.
  static String _fips(String iso) {
    const m = {
      'GB': 'UK', 'DE': 'GM', 'JP': 'JA', 'KR': 'KS', 'CN': 'CH', 'AU': 'AS', 'ES': 'SP',
      'IE': 'EI', 'IL': 'IS', 'PH': 'RP', 'ZA': 'SF', 'NG': 'NI', 'RU': 'RS', 'UA': 'UP',
      'TR': 'TU', 'SE': 'SW', 'AT': 'AU', 'CH': 'SZ', 'PT': 'PO', 'VN': 'VM', 'BD': 'BG',
    };
    return m[iso.toUpperCase()] ?? iso.toUpperCase();
  }
}

/// Fetches a publisher's own RSS/Atom feed.
class DirectFeed {
  static Future<List<Article>> fetch(String feedUrl,
      {required String sourceName, required String domain, Category? hint, bool isLocal = false}) async {
    final body = await Net.getText(feedUrl);
    return FeedParser.parse(body,
        provider: 'rss', sourceName: sourceName, sourceDomain: domain, hint: hint, isLocal: isLocal, maxItems: 30);
  }
}
