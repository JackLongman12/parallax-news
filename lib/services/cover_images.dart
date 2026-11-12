import 'dart:async';

import '../models/story.dart';
import 'feed_parser.dart';
import 'net.dart';
import 'providers.dart';
import 'text.dart';

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

  static String? cached(Story s) => _cache[s.id] ?? s.imageUrl;

  /// Restores a cover remembered from the last session (validated again).
  static void seed(String id, String url) {
    final u = Uri.tryParse(url);
    if (u != null && u.scheme == 'https' && isPublicHost(u.host)) _cache[id] = url;
  }

  /// Bing /th thumbnails and similar are small; try for something better first.
  static bool isLowRes(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return true;
    if (u.host.endsWith('bing.com') && u.path.startsWith('/th')) return true;
    final w = int.tryParse(u.queryParameters['w'] ?? u.queryParameters['width'] ?? '');
    return w != null && w < 500;
  }

  /// Images from Wikimedia Commons need a credit line.
  static bool needsCredit(String url) => Uri.tryParse(url)?.host == 'upload.wikimedia.org';

  static Future<String?> forStory(Story s) {
    final direct = s.imageUrl;
    if (!enabled) return Future.value(direct);
    if (direct != null && !isLowRes(direct)) return Future.value(direct);
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

  static Future<String?> _ogImage(String url) async {
    try {
      final html = await Net.getText(url, useCache: false, headBytes: 200 * 1024, timeout: const Duration(seconds: 8));
      return extractMetaImage(html, Uri.parse(url));
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _find(Story s) async {
    // 1. Full-size images already present in the story's feeds.
    for (final a in s.articles) {
      final img = a.imageUrl;
      if (img != null && !isLowRes(img)) return img;
    }
    // 2. Publisher pages' og:image (Google links are redirect wrappers; skip).
    for (final a in s.articles.where((a) => a.provider != 'google' && isSafeWebUrl(a.url)).take(2)) {
      final img = await _ogImage(a.url);
      if (img != null) return img;
    }
    // 3. Find the same story on Bing, then use that publisher's og:image.
    String? thumb;
    try {
      final results = await BingNews.search(s.title).timeout(const Duration(seconds: 8));
      for (final r in results.take(2)) {
        final img = await _ogImage(r.url);
        if (img != null) return img;
        thumb ??= r.imageUrl;
      }
    } catch (_) {}
    // 4. Any lower-res image we have (already upscaled where possible).
    thumb ??= s.articles.map((a) => a.imageUrl).whereType<String>().firstOrNull;
    if (thumb != null) return thumb;
    // 5. Generic but relevant photo by keywords from Wikimedia Commons.
    return commonsImage(s);
  }

  static final _caps = RegExp(r"\b[A-Z][a-zA-Z'’-]{2,}(?:\s+[A-Z][a-zA-Z'’-]{2,})*");

  /// Keywords for an image search: proper nouns first (places, people,
  /// organisations), then the most specific other words.
  static String keywordsFor(Story s) {
    final title = s.title;
    final proper = _caps
        .allMatches(title)
        .map((m) => m.group(0)!)
        .where((w) => !TextTokens.isStopWord(w.toLowerCase()))
        .toList();
    final words = TextTokens.tokens(title)..sort((a, b) => b.length.compareTo(a.length));
    final parts = <String>[...proper.take(2)];
    for (final w in words) {
      if (parts.length >= 3) break;
      if (!parts.any((p) => p.toLowerCase().contains(w))) parts.add(w);
    }
    return parts.join(' ');
  }

  static Future<String?> commonsImage(Story s) async {
    final queries = [keywordsFor(s), s.category.label];
    for (final q in queries) {
      if (q.trim().isEmpty) continue;
      try {
        final url = 'https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=search'
            '&gsrnamespace=6&gsrlimit=8&prop=imageinfo&iiprop=url|size|mime&iiurlwidth=1200'
            '&gsrsearch=${Uri.encodeQueryComponent('filetype:bitmap $q')}';
        final json = await Net.getJson(url).timeout(const Duration(seconds: 8));
        final query = json is Map ? json['query'] : null;
        final pages = query is Map ? query['pages'] : null;
        if (pages is! Map) continue;
        final infos = pages.values
            .whereType<Map>()
            .map((p) => ((p['imageinfo'] as List?)?.firstOrNull) as Map?)
            .whereType<Map>()
            .where((i) => (i['width'] as num? ?? 0) >= 800 && '${i['mime']}'.startsWith('image/'))
            .toList();
        for (final i in infos) {
          final thumb = Uri.tryParse('${i['thumburl'] ?? i['url']}');
          if (thumb != null && thumb.scheme == 'https' && thumb.host == 'upload.wikimedia.org') {
            return thumb.toString();
          }
        }
      } catch (_) {}
    }
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
    return FeedParser.upscaleImage(u.toString());
  }
}
