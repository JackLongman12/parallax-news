import 'category.dart';
import 'source.dart';

class Article {
  Article({
    required this.title,
    required this.url,
    required this.sourceName,
    required this.domain,
    this.published,
    this.snippet = '',
    this.imageUrl,
    required this.provider,
    this.isLocal = false,
    this.hintCategory,
  });

  final String title;
  final String url;
  final String sourceName;
  final String domain;
  final DateTime? published;
  final String snippet;
  final String? imageUrl;

  /// 'google', 'bing', 'rss', 'api', 'crawl'
  final String provider;
  bool isLocal;

  /// Category given by the feed itself (e.g. a Google News topic feed or a
  /// topic-specialist outlet). Used as a label for the on-device classifier.
  Category? hintCategory;

  /// Filled in by the bias service.
  SourceInfo? source;

  Map<String, dynamic> toJson() => {
        't': title,
        'u': url,
        's': sourceName,
        'd': domain,
        'p': published?.millisecondsSinceEpoch,
        'n': snippet,
        'i': imageUrl,
        'v': provider,
        'l': isLocal,
        'h': hintCategory?.name,
      };

  static Article? fromJson(Map<String, dynamic> j) {
    try {
      return Article(
        title: j['t'] as String,
        url: j['u'] as String,
        sourceName: j['s'] as String,
        domain: j['d'] as String,
        published: j['p'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['p'] as int, isUtc: true),
        snippet: (j['n'] as String?) ?? '',
        imageUrl: j['i'] as String?,
        provider: (j['v'] as String?) ?? 'rss',
        isLocal: j['l'] == true,
        hintCategory: Category.byName(j['h'] as String?),
      );
    } catch (_) {
      return null;
    }
  }
}
