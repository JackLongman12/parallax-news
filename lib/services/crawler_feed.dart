import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, gzip;

import 'package:path_provider/path_provider.dart';

import '../models/article.dart';
import '../models/category.dart';
import '../models/story.dart';
import 'net.dart';

/// Pre-built stories from our own crawler (GitHub Actions, every ~5 min):
/// hundreds of feeds clustered into stories with many outlets each.
///
/// Refreshed every 5 min. The last good copy (~1 MB) is kept on disk for
/// outages; with nothing at all, the app falls back to on-device fetching.
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
  static List<Story> get stories => _stories ?? const [];
  static String get via => _via;
  static String? lastError;

  static Future<List<Story>> load({bool force = false}) {
    if (!enabled) return Future.value(const []);
    if (!force && _stories != null && DateTime.now().difference(_at) < const Duration(minutes: 5)) {
      return Future.value(_stories!);
    }
    return _inflight ??= _fetch().whenComplete(() => _inflight = null);
  }

  /// Worker first, then GitHub directly, then the last feed saved on the
  /// phone (so a cold start during an outage still shows stories).
  static Future<List<Story>> _fetch() async {
    Object? fail;
    for (final source in [if (workerUrl.startsWith('https://')) 'Cloudflare', 'GitHub']) {
      try {
        final text = source == 'Cloudflare'
            ? await Net.getText('$workerUrl/feed', useCache: false, timeout: const Duration(seconds: 12))
            : utf8.decode(gzip.decode(await Net.getBytes(githubUrl, timeout: const Duration(seconds: 15))),
                allowMalformed: true);
        if (_use(text, source)) {
          unawaited(_save(text));
          return _stories!;
        }
        fail = const FormatException('empty feed');
      } catch (e) {
        fail = e;
      }
    }
    if (_stories == null) {
      final saved = await _load();
      if (saved != null && _use(saved, 'saved copy')) {
        lastError = 'offline, showing the last saved feed';
        return _stories!;
      }
    }
    lastError = fail is FormatException ? 'feed was unreadable' : 'could not reach Cloudflare or GitHub';
    return _stories ?? const [];
  }

  static String _via = 'GitHub';

  static bool _use(String text, String source) {
    final json = jsonDecode(text);
    final list = parse(json);
    if (list.isEmpty) return false;
    final at = json is Map ? json['at'] : null;
    builtAt = at is int ? DateTime.fromMillisecondsSinceEpoch(at * 1000) : null;
    _stories = list;
    _at = DateTime.now();
    _via = source;
    lastError = null;
    return true;
  }

  // One gzipped copy (~1 MB), replaced on every successful load.
  static Future<File?> _file() async {
    try {
      return File('${(await getApplicationSupportDirectory()).path}/feed_last.json.gz');
    } catch (_) {
      return null;
    }
  }

  static Future<void> _save(String text) async {
    try {
      await (await _file())?.writeAsBytes(gzip.encode(utf8.encode(text)), flush: true);
    } catch (_) {}
  }

  static Future<String?> _load() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return null;
      return utf8.decode(gzip.decode(await f.readAsBytes()), allowMalformed: true);
    } catch (_) {
      return null;
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
