import '../data/geo.dart';
import '../models/article.dart';
import '../models/category.dart';
import 'feed_parser.dart';
import 'net.dart';
import 'provider_health.dart';

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
    final body = await ProviderHealth.instance.run('google', () => Net.getText(url));
    return FeedParser.parse(body, provider: 'google', hint: hint, isLocal: isLocal);
  }
}

/// Bing News RSS: a second, independent index to widen local coverage.
class BingNews {
  static Future<List<Article>> search(String query, {String? market, bool isLocal = false}) async {
    final mkt = market == null ? '' : '&mkt=${Uri.encodeQueryComponent(market)}';
    final body = await ProviderHealth.instance.run('bing', () => Net.getText(
        'https://www.bing.com/news/search?q=${Uri.encodeQueryComponent(query)}&format=rss$mkt'));
    return FeedParser.parse(body, provider: 'bing', isLocal: isLocal);
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
