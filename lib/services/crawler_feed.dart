import 'dart:convert';
import 'dart:io' show gzip;

import '../models/article.dart';
import '../models/category.dart';
import '../models/story.dart';
import 'net.dart';

/// Pre-built stories from our own crawler (GitHub Actions, every ~5 min):
/// hundreds of feeds clustered into stories with many outlets each.
///
/// Kept in MEMORY only (never written to disk) and refreshed every 5 min,
/// so it adds no storage. If the crawler or worker is unreachable, the app
/// silently falls back to on-device fetching.
class CrawlerFeed {
  /// Cloudflare worker endpoint (set at build time once deployed), else the
  /// GitHub release asset directly.
  static const workerUrl = String.fromEnvironment('FEED_WORKER_URL', defaultValue: '');
  static const githubUrl = 'https://github.com/JackLongman12/parallax-news/releases/download/feed/feed.json.gz';

  static bool enabled = true;
  static List<Story>? _stories;
  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<List<Story>>? _inflight;

  /// Status for Settings: when the crawler built the feed, where the app got
  /// it from, and the last failure (null after a successful load).
  static DateTime? builtAt;
  static DateTime? get loadedAt => _stories == null ? null : _at;
  static int get count => _stories?.length ?? 0;
  static String get via => workerUrl.startsWith('https://') ? 'Cloudflare' : 'GitHub';
  static String? lastError;

  static Future<List<Story>> load({bool force = false}) {
    if (!enabled) return Future.value(const []);
    if (!force && _stories != null && DateTime.now().difference(_at) < const Duration(minutes: 5)) {
      return Future.value(_stories!);
    }
    return _inflight ??= _fetch().whenComplete(() => _inflight = null);
  }

  static Future<List<Story>> _fetch() async {
    try {
      String text;
      if (workerUrl.startsWith('https://')) {
        text = await Net.getText('$workerUrl/feed', useCache: false, timeout: const Duration(seconds: 12));
      } else {
        final bytes = await Net.getBytes(githubUrl, timeout: const Duration(seconds: 15));
        text = utf8.decode(gzip.decode(bytes), allowMalformed: true);
      }
      final json = jsonDecode(text);
      final list = parse(json);
      if (list.isEmpty) throw const FormatException('empty feed');
      final at = json is Map ? json['at'] : null;
      builtAt = at is int ? DateTime.fromMillisecondsSinceEpoch(at * 1000) : null;
      _stories = list;
      _at = DateTime.now();
      lastError = null;
      return _stories!;
    } on FormatException {
      lastError = 'feed was unreadable';
      return _stories ?? const [];
    } catch (_) {
      lastError = 'could not reach $via';
      return _stories ?? const [];
    }
  }

  /// Parses the crawler JSON (defensively: it comes from the network).
  static List<Story> parse(dynamic json) {
    if (json is! Map || json['stories'] is! List) return const [];
    final out = <Story>[];
    for (final s in (json['stories'] as List).whereType<Map>()) {
      final arts = <Article>[];
      for (final a in (s['a'] as List? ?? const []).whereType<Map>()) {
        final url = a['u'];
        final title = a['t'];
        final domain = a['d'];
        if (url is! String || title is! String || domain is! String || !isSafeWebUrl(url)) continue;
        final p = a['p'];
        final img = a['i'];
        arts.add(Article(
          title: title,
          url: url,
          sourceName: (a['s'] as String?) ?? domain,
          domain: domain.toLowerCase(),
          published: p is num ? DateTime.fromMillisecondsSinceEpoch((p * 1000).round(), isUtc: true) : null,
          snippet: (a['n'] as String?) ?? '',
          imageUrl: _safeImage(img),
          provider: (a['v'] as String?) ?? 'crawl',
        ));
      }
      if (arts.isEmpty) continue;
      final cover = _safeImage(s['img']);
      if (cover != null && arts.first.imageUrl == null) {
        final f = arts.first;
        arts[0] = Article(
          title: f.title,
          url: f.url,
          sourceName: f.sourceName,
          domain: f.domain,
          published: f.published,
          snippet: f.snippet,
          imageUrl: cover,
          provider: f.provider,
        );
      }
      out.add(Story(
        id: 'c${s['id'] ?? arts.first.url.hashCode}',
        articles: arts,
        category: Category.byName(s['c'] as String?) ?? Category.general,
      ));
    }
    return out;
  }

  static String? _safeImage(dynamic v) {
    if (v is! String) return null;
    final u = Uri.tryParse(v);
    return u != null && u.scheme == 'https' && isPublicHost(u.host) ? v : null;
  }
}
