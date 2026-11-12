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

  /// Which story is using which image, so two stories never share a cover.
  static final Map<String, String> _usedBy = {};

  /// Claims [url] for story [id]; false if another story already uses it
  /// or it looks like a generic logo / placeholder.
  static bool _claim(String? url, String id) {
    if (url == null || looksGeneric(url)) return false;
    final key = _imageKey(url);
    final owner = _usedBy[key];
    if (owner != null && owner != id) return false;
    if (_usedBy.length > 1500) _usedBy.clear();
    _usedBy[key] = id;
    return true;
  }

  /// Same picture at different sizes / query strings counts as the same image.
  static String _imageKey(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return url;
    if (u.host.endsWith('bing.com')) return 'bing:${u.queryParameters['id'] ?? u.path}';
    // Wikimedia thumbs: /.../thumb/a/ab/File.jpg/1200px-File.jpg -> File.jpg
    final segs = u.pathSegments;
    final ti = segs.indexOf('thumb');
    if (u.host == 'upload.wikimedia.org' && ti >= 0 && segs.length > ti + 3) return 'wm:${segs[ti + 3]}';
    return '${u.host}${u.path}';
  }

  static final _generic = RegExp(r'(logo|placeholder|default|fallback|blank|spacer|avatar|favicon|social[-_]?share|og[-_]?default)',
      caseSensitive: false);

  /// Publisher fallbacks (site logos etc.) that would repeat on every story.
  static bool looksGeneric(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return true;
    return _generic.hasMatch(u.path.split('/').last) || u.path.endsWith('.svg') || u.path.endsWith('.ico');
  }

  static String? cached(Story s) => _cache[s.id] ?? s.imageUrl;

  /// Restores a cover remembered from the last session (validated again).
  static void seed(String id, String url) {
    final u = Uri.tryParse(url);
    if (u != null && u.scheme == 'https' && isPublicHost(u.host) && _claim(url, id)) _cache[id] = url;
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
    if (_cache.containsKey(s.id)) return Future.value(_cache[s.id]);
    if (direct != null && !isLowRes(direct) && _claim(direct, s.id)) {
      _cache[s.id] = direct;
      return Future.value(direct);
    }
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
    final id = s.id;
    // 1. Full-size images already present in the story's feeds.
    for (final a in s.articles) {
      final img = a.imageUrl;
      if (img != null && !isLowRes(img) && _claim(img, id)) return img;
    }
    // 2. Publisher pages' og:image (Google links are redirect wrappers; skip).
    for (final a in s.articles.where((a) => a.provider != 'google' && isSafeWebUrl(a.url)).take(3)) {
      final img = await _ogImage(a.url);
      if (_claim(img, id)) return img;
    }
    // 3. Find the same story on Bing, then use those publishers' og:image.
    final thumbs = <String>[];
    try {
      final results = await BingNews.search(s.title).timeout(const Duration(seconds: 8));
      for (final r in results.take(3)) {
        final img = await _ogImage(r.url);
        if (_claim(img, id)) return img;
        if (r.imageUrl != null) thumbs.add(r.imageUrl!);
      }
    } catch (_) {}
    // 4. Any lower-res image we have (already upscaled where possible).
    thumbs.addAll(s.articles.map((a) => a.imageUrl).whereType<String>());
    for (final t in thumbs) {
      if (_claim(t, id)) return t;
    }
    // 5. A relevant photo by keywords from Wikimedia Commons (not used elsewhere).
    return commonsImage(s);
  }

  static final _caps = RegExp(r"\b[A-Z][a-zA-Z'’-]{2,}(?:\s+[A-Z][a-zA-Z'’-]{2,})*");

  static List<String> _properNouns(String title) => _caps
      .allMatches(title)
      .map((m) => m.group(0)!)
      .where((w) => !TextTokens.isStopWord(w.toLowerCase()))
      .toList();

  /// Keywords for an image search: proper nouns first (places, people,
  /// organisations), then the most specific other words.
  static String keywordsFor(Story s) {
    final title = s.title;
    final proper = _properNouns(title);
    final words = TextTokens.tokens(title)..sort((a, b) => b.length.compareTo(a.length));
    final parts = <String>[...proper.take(2)];
    for (final w in words) {
      if (parts.length >= 3) break;
      if (!parts.any((p) => p.toLowerCase().contains(w))) parts.add(w);
    }
    return parts.join(' ');
  }

  /// Progressively broader searches, most specific first.
  static List<String> imageQueries(Story s) {
    final proper = _properNouns(s.title);
    final words = TextTokens.tokens(s.title)..sort((a, b) => b.length.compareTo(a.length));
    final qs = <String>[
      keywordsFor(s),
      if (proper.isNotEmpty) proper.first,
      if (proper.length > 1) proper[1],
      if (words.length >= 2) '${words[0]} ${words[1]}',
      if (words.isNotEmpty) '${words[0]} ${s.category.label}',
      s.category.label,
    ];
    final seen = <String>{};
    return [for (final q in qs) if (q.trim().isNotEmpty && seen.add(q.toLowerCase())) q];
  }

  static Future<String?> commonsImage(Story s) async {
    for (final q in imageQueries(s).take(4)) {
      try {
        final url = 'https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=search'
            '&gsrnamespace=6&gsrlimit=20&prop=imageinfo&iiprop=url|size|mime&iiurlwidth=1200'
            '&gsrsearch=${Uri.encodeQueryComponent('filetype:bitmap $q')}';
        final json = await Net.getJson(url).timeout(const Duration(seconds: 8));
        final query = json is Map ? json['query'] : null;
        final pages = query is Map ? query['pages'] : null;
        if (pages is! Map) continue;
        // Keep search-relevance order.
        final ordered = pages.values.whereType<Map>().toList()
          ..sort((a, b) => ((a['index'] as num?) ?? 999).compareTo((b['index'] as num?) ?? 999));
        for (final p in ordered) {
          final info = (p['imageinfo'] as List?)?.firstOrNull;
          if (info is! Map) continue;
          if ((info['width'] as num? ?? 0) < 800 || !'${info['mime']}'.startsWith('image/')) continue;
          final thumb = Uri.tryParse('${info['thumburl'] ?? info['url']}');
          if (thumb == null || thumb.scheme != 'https' || thumb.host != 'upload.wikimedia.org') continue;
          if (_claim(thumb.toString(), s.id)) return thumb.toString();
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
