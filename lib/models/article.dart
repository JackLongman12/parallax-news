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

  /// 'google', 'bing', 'gdelt', 'rss'
  final String provider;
  bool isLocal;

  /// Category given by the feed itself (e.g. a Google News topic feed or a
  /// topic-specialist outlet). Used as a label for the on-device classifier.
  Category? hintCategory;

  /// Filled in by the bias service.
  SourceInfo? source;
}
