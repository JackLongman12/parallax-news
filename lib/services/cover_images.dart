import 'dart:async';

import '../models/story.dart';
import 'feed_parser.dart';
import 'net.dart';
import 'providers.dart';

/// Finds a real news photo for a story. Google News RSS carries no images, so
/// we try, cheapest first:
///   1. an image already in any of the story's feeds (Bing, publisher RSS, GDELT)
///   2. the og:image / twitter:image of a publisher article page (first ~200 KB)
///   3. a Bing News search for the headline, taking the first item with an image
/// Results are cached; at most 3 lookups run at once, and only for cards that
/// are actually on screen.
class CoverImages {
  static final Map<String, String?> _cache = {};
  static final Map<String, Future<String?>> _inflight = {};
  static int _active = 0;
  static final List<Completer<void>> _waiters = [];

  /// Disabled by the screenshot generator (no network in widget tests).
  static bool enabled = true;

  static String? cached(Story s) => s.imageUrl ?? _cache[s.id];

  static Future<String?> forStory(Story s) {
    final direct = s.imageUrl;
    if (direct != null || !enabled) return Future.value(direct);
    if (_cache.containsKey(s.id)) return Future.value(_cache[s.id]);
    return _inflight[s.id] ??= _limited(() => _find(s)).then((url) {
      if (_cache.length > 600) _cache.clear();
      _cache[s.id] = url;
      _inflight.remove(s.id);
      return url;
    });
  }

  static Future<T> _limited<T>(Future<T> Function() task) async {
    while (_active >= 3) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _active++;
    try {
      return await task();
    } finally {
      _active--;
      if (_waiters.isNotEmpty) _waiters.removeAt(0).complete();
    }
  }

  static Future<String?> _find(Story s) async {
    // 2. Publisher pages (Google links are redirect wrappers, so skip them).
    final pages = s.articles.where((a) => a.provider != 'google' && isSafeWebUrl(a.url)).take(2);
    for (final a in pages) {
      try {
        final html = await Net.getText(a.url,
            useCache: false, headBytes: 200 * 1024, timeout: const Duration(seconds: 8));
        final img = extractMetaImage(html, Uri.parse(a.url));
        if (img != null) return img;
      } catch (_) {}
    }
    // 3. Search the headline on Bing News, which returns thumbnails.
    try {
      final results = await BingNews.search(s.title).timeout(const Duration(seconds: 8));
      for (final r in results) {
        if (r.imageUrl != null) return r.imageUrl;
      }
    } catch (_) {}
    return null;
  }

  static final _meta = RegExp(r'<meta\s[^>]*>', caseSensitive: false);
  static final _prop = RegExp(r'''(?:property|name)\s*=\s*["']([^"']+)["']''', caseSensitive: false);
  static final _content = RegExp(r'''content\s*=\s*["']([^"']+)["']''', caseSensitive: false);

  /// Pulls og:image / twitter:image from page HTML. Public HTTPS only.
  static String? extractMetaImage(String html, Uri base) {
    String? og, tw;
    for (final m in _meta.allMatches(html)) {
      final tag = m.group(0)!;
      final prop = _prop.firstMatch(tag)?.group(1)?.toLowerCase();
      if (prop == null) continue;
      final content = _content.firstMatch(tag)?.group(1);
      if (content == null) continue;
      if (prop == 'og:image' || prop == 'og:image:secure_url' || prop == 'og:image:url') og ??= content;
      if (prop == 'twitter:image' || prop == 'twitter:image:src') tw ??= content;
    }
    final raw = og ?? tw;
    if (raw == null) return null;
    final resolved = base.resolve(FeedParser.decodeEntities(raw.trim()));
    final u = resolved.scheme == 'http' ? resolved.replace(scheme: 'https') : resolved;
    if (u.scheme != 'https' || !isPublicHost(u.host)) return null;
    return u.toString();
  }
}
