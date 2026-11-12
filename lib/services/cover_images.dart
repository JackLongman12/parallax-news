import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/category.dart';
import '../models/story.dart';
import 'clustering.dart';
import 'crawler_feed.dart';
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
    if (isWikimediaHost(u.host) && ti >= 0 && segs.length > ti + 3) return 'wm:${segs[ti + 3]}';
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
  /// Wikimedia serves files from upload.* and resized copies from thumb.*.
  static bool isWikimediaHost(String? host) => host == 'upload.wikimedia.org' || host == 'thumb.wikimedia.org';

  static bool needsCredit(String url) => isWikimediaHost(Uri.tryParse(url)?.host);

  static final Map<String, String> _credits = {};

  /// Photographer / licence for a Wikimedia photo (as the licence requires).
  static String creditFor(String url) => _credits[url] ?? 'Wikimedia Commons';

  /// True for a real news photo (not a Wikimedia stand-in).
  static bool isNewsPhoto(String? url) => url != null && !needsCredit(url);

  static Future<String?> forStory(Story s) {
    final direct = s.imageUrl;
    if (!enabled) return Future.value(direct);
    if (_cache.containsKey(s.id) && _cache[s.id] != null && !_isPool(_cache[s.id]!)) return Future.value(_cache[s.id]);
    if (direct != null && !isLowRes(direct) && _claim(direct, s.id)) {
      _remember(s.id, direct);
      return Future.value(direct);
    }
    return _inflight[s.id] ??= _limited(() => _find(s)).then((url) {
      _inflight.remove(s.id);
      if (url != null) _remember(s.id, url);
      return url ?? _cache[s.id];
    });
  }

  /// Instant image for a card: the remembered cover, or a distinct photo
  /// from the topic's pool (no network). The real news photo replaces it.
  static String? quick(Story s) {
    final known = cached(s);
    if (known != null || !enabled) return known;
    // Sports / entertainment / gaming photos show specific things (a basketball
    // game is wrong for a football story), so those use the neutral bundled
    // topic photo instead of a random stock one.
    if (const {Category.sports, Category.entertainment, Category.gaming}.contains(s.category)) return null;
    final pool = variants[s.category.name] ?? variants['general'];
    if (pool == null || pool.isEmpty) return null;
    final start = s.id.hashCode.abs() % pool.length;
    for (var i = 0; i < pool.length; i++) {
      final url = pool[(start + i) % pool.length];
      if (_claim(url, s.id)) {
        _cache[s.id] = url;
        return url;
      }
    }
    return null;
  }

  /// Curated extra photos per topic (assets/topics/variants.json): public
  /// domain / CC0, chosen ahead of time so they are always on-topic.
  static Map<String, List<String>> variants = {};

  /// A curated photo for a topic; [seed] picks which one (variety).
  static String? variantFor(Category c, int seed) {
    final list = variants[c.name];
    if (list == null || list.isEmpty) return null;
    return list[seed.abs() % list.length];
  }

  static Future<void> loadVariants() async {
    try {
      final raw = jsonDecode(await rootBundle.loadString('assets/topics/variants.json')) as Map<String, dynamic>;
      final out = <String, List<String>>{};
      raw.forEach((k, v) {
        final urls = <String>[];
        for (final e in (v as List)) {
          final u = e is Map ? e['u'] : e;
          if (u is! String || !u.startsWith('https://') || !isWikimediaHost(Uri.tryParse(u)?.host)) continue;
          urls.add(u);
          if (e is Map && e['c'] is String) _credits[u] = (e['c'] as String).replaceAll(RegExp(r'[\u0000-\u001F]'), '');
        }
        out[k] = urls;
      });
      variants = out;
    } catch (_) {}
  }

  // ---- Topic photo pools (one request per topic, remembered for a week) ----
  static final Map<Category, List<String>> _pools = {};
  static final Set<String> _poolUrls = {};
  static bool _isPool(String url) => _poolUrls.contains(url);
  static SharedPreferences? _store;

  /// Restores pools + remembered covers from the last session, then refreshes
  /// stale pools in the background.
  static Future<void> init(SharedPreferences prefs, Iterable<Category> warm) async {
    _store = prefs;
    try {
      final raw = jsonDecode(prefs.getString('imgPools') ?? '{}') as Map<String, dynamic>;
      final at = DateTime.tryParse(prefs.getString('imgPoolsAt') ?? '');
      raw.forEach((k, v) {
        final c = Category.byName(k);
        if (c == null || v is! List) return;
        final urls = v.whereType<String>().where((u) => isWikimediaHost(Uri.tryParse(u)?.host)).toList();
        _pools[c] = urls;
        _poolUrls.addAll(urls);
      });
      final covers = jsonDecode(prefs.getString('coverMap') ?? '{}') as Map<String, dynamic>;
      covers.forEach((id, url) {
        if (url is String) seed(id, url);
      });
      if (at != null && DateTime.now().difference(at) < const Duration(days: 7) && _pools.length >= warm.length) return;
    } catch (_) {}
    // Live Commons pools are no longer filled: curated variants replace them.
  }

  static Future<void> _fillPool(Category c) async {
    final qs = concepts[c] ?? const <String>[];
    final urls = <String>[];
    for (final q in qs.take(2)) {
      urls.addAll(await _commonsList(q, limit: 15));
    }
    if (urls.isNotEmpty) {
      _pools[c] = urls;
      _poolUrls.addAll(urls);
    }
  }

  static void _savePools() {
    _store?.setString('imgPools', jsonEncode(_pools.map((k, v) => MapEntry(k.name, v))));
    _store?.setString('imgPoolsAt', DateTime.now().toIso8601String());
  }

  static Timer? _saveTimer;
  static void _remember(String id, String url) {
    if (_cache.length > 600) _cache.clear();
    _cache[id] = url;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 5), () {
      final entries = _cache.entries.where((e) => e.value != null).toList();
      final keep = Map.fromEntries(entries.skip(entries.length > 400 ? entries.length - 400 : 0));
      _store?.setString('coverMap', jsonEncode(keep));
    });
  }

  static Future<T> _limited<T>(Future<T> Function() task) async {
    while (_active >= 6) {
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
    // The Worker reads the page at the edge and caches the answer for a day,
    // so phones skip downloading article HTML. Sites that block it fall back
    // to a direct fetch.
    if (CrawlerFeed.workerUrl.startsWith('https://')) {
      try {
        final j = await Net.getJson('${CrawlerFeed.workerUrl}/og?url=${Uri.encodeQueryComponent(url)}', useCache: false);
        final img = j is Map ? j['image'] : null;
        if (img is String && img.startsWith('https://') && isSafeWebUrl(img) && !looksGeneric(img)) return img;
      } catch (_) {}
    }
    try {
      final html = await Net.getText(url, useCache: false, headBytes: 96 * 1024, timeout: const Duration(seconds: 6));
      return extractMetaImage(html, Uri.parse(url));
    } catch (_) {
      return null;
    }
  }

  /// First non-null result among [futures] that can be claimed for [id].
  static Future<String?> _firstClaimed(List<Future<String?>> futures, String id) {
    if (futures.isEmpty) return Future.value(null);
    final done = Completer<String?>();
    var left = futures.length;
    for (final f in futures) {
      f.then((v) {
        if (!done.isCompleted && v != null && _claim(v, id)) done.complete(v);
      }).catchError((_) {}).whenComplete(() {
        if (--left == 0 && !done.isCompleted) done.complete(null);
      });
    }
    return done.future;
  }

  static Future<String?> _find(Story s) async {
    final id = s.id;
    // 1. Full-size images already present in the story's feeds.
    for (final a in s.articles) {
      final img = a.imageUrl;
      if (img != null && !isLowRes(img) && _claim(img, id)) return img;
    }
    // 2+3 in PARALLEL: publishers' og:image, and the same story found on Bing.
    final thumbs = <String>[];
    Future<String?> viaBing() async {
      try {
        final all = await BingNews.search(s.title).timeout(const Duration(seconds: 6));
        final results = all.where((r) => sameStory(s.title, r.title)).toList();
        for (final r in results) {
          if (r.imageUrl != null) thumbs.add(r.imageUrl!);
        }
        return _firstClaimed([for (final r in results.take(3)) _ogImage(r.url)], id);
      } catch (_) {
        return null;
      }
    }

    // The covering outlets' own article pages: find the article on that
    // outlet's site (Google links are wrappers), then read its preview image.
    Future<String?> onOutletSite(String domain) async {
      if (!_domainRe.hasMatch(domain) || !isPublicHost(domain)) return null;
      try {
        final hits = await BingNews.search('site:$domain ${s.title}').timeout(const Duration(seconds: 6));
        final own = hits.where((h) {
          final d = domainOf(h.url);
          // Exact domain or a real subdomain only, and it must be the same story.
          return (d == domain || d.endsWith('.$domain')) && sameStory(s.title, h.title);
        }).take(1).toList();
        if (own.isEmpty) return null;
        return _ogImage(own.first.url);
      } catch (_) {
        return null;
      }
    }

    final googleOnly = s.articles.where((a) => a.provider == 'google').map((a) => a.domain).toSet().take(2);
    final best = await _firstClaimed([
      for (final a in s.articles.where((a) => a.provider != 'google' && isSafeWebUrl(a.url)).take(3)) _ogImage(a.url),
      for (final d in googleOnly) onOutletSite(d),
      viaBing(),
    ], id);
    if (best != null) return best;
    // 4. Any lower-res image we have (already upscaled where possible).
    thumbs.addAll(s.articles.map((a) => a.imageUrl).whereType<String>());
    for (final t in thumbs) {
      if (_claim(t, id)) return t;
    }
    // 6. Last resort: a distinct curated photo for the topic.
    return quick(s);
  }

  static final _domainRe = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$');

  /// True when two headlines are clearly about the same event.
  static bool sameStory(String a, String b) =>
      StoryClusterer.similarity(TextTokens.stemSet(a), TextTokens.stemSet(b)) >= 0.45;

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

  /// Photo concepts per topic, used when a story has no specific image.
  static const Map<Category, List<String>> concepts = {
    Category.general: ['news studio', 'printing press newspaper', 'city skyline night'],
    Category.politics: ['parliament chamber', 'ballot box election', 'capitol building'],
    Category.world: ['united nations general assembly', 'globe world map', 'flags of the world'],
    Category.business: ['business district skyscrapers', 'container port cargo', 'office meeting'],
    Category.technology: ['circuit board', 'data center servers', 'smartphone'],
    Category.ai: ['humanoid robot', 'artificial intelligence', 'neural network visualization'],
    Category.science: ['laboratory scientist', 'microscope', 'particle accelerator'],
    Category.space: ['rocket launch', 'galaxy', 'international space station'],
    Category.health: ['hospital doctor', 'stethoscope', 'medical laboratory'],
    Category.sports: ['football stadium', 'athletics race track', 'basketball game'],
    Category.entertainment: ['cinema theatre', 'concert stage lights', 'film camera'],
    Category.gaming: ['video game controller', 'esports tournament', 'arcade'],
    Category.environment: ['wind turbines', 'forest landscape', 'flood'],
    Category.crime: ['courtroom', 'police car', 'scales of justice'],
    Category.education: ['university library', 'classroom', 'graduation ceremony'],
    Category.finance: ['stock exchange trading floor', 'stock market chart', 'banknotes'],
    Category.autos: ['electric car charging', 'car assembly line', 'highway traffic'],
    Category.travel: ['airport airplane', 'restaurant food', 'tourist landmark'],
    Category.lifestyle: ['fashion runway', 'yoga', 'home interior'],
    Category.local: ['town hall', 'main street town', 'community park'],
    Category.energy: ['oil refinery', 'solar panels', 'power plant'],
    Category.realEstate: ['residential houses neighborhood', 'apartment building', 'construction crane'],
    Category.defense: ['military parade', 'fighter jet', 'warship'],
    Category.labor: ['factory workers', 'labor union rally', 'office workers'],
    Category.weather: ['storm clouds', 'snowstorm', 'lightning'],
  };

  static final Map<String, String?> _keyed = {};

  /// Several good images for a query (for topic pools).
  static Future<List<String>> _commonsList(String q, {int limit = 15}) async {
    try {
      final url = 'https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=search'
          '&gsrnamespace=6&gsrlimit=30&prop=imageinfo&iiprop=url|size|mime&iiurlwidth=1080'
          '&gsrsearch=${Uri.encodeQueryComponent('filetype:bitmap $q')}';
      final json = await Net.getJson(url).timeout(const Duration(seconds: 8));
      final query = json is Map ? json['query'] : null;
      final pages = query is Map ? query['pages'] : null;
      if (pages is! Map) return const [];
      final out = <String>[];
      for (final p in pages.values.whereType<Map>()) {
        final title = '${p['title'] ?? ''}';
        if (RegExp(r'(map|logo|flag|coat of arms|diagram|chart|seal|signature|icon)', caseSensitive: false).hasMatch(title)) continue;
        final info = (p['imageinfo'] as List?)?.firstOrNull;
        if (info is! Map) continue;
        if ((info['width'] as num? ?? 0) < 800 || !'${info['mime']}'.startsWith('image/')) continue;
        final thumb = Uri.tryParse('${info['thumburl'] ?? info['url']}');
        if (thumb == null || thumb.scheme != 'https' || !isWikimediaHost(thumb.host)) continue;
        out.add(thumb.toString());
        if (out.length >= limit) break;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// One Commons search; returns the first unused image whose file title
  /// passes [accept] (used to make sure the photo is actually relevant).
  static Future<String?> _commons(String q, String claimId, {bool Function(String title)? accept}) async {
    try {
      final url = 'https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=search'
          '&gsrnamespace=6&gsrlimit=20&prop=imageinfo&iiprop=url|size|mime&iiurlwidth=1200'
          '&gsrsearch=${Uri.encodeQueryComponent('filetype:bitmap $q')}';
      final json = await Net.getJson(url).timeout(const Duration(seconds: 8));
      final query = json is Map ? json['query'] : null;
      final pages = query is Map ? query['pages'] : null;
      if (pages is! Map) return null;
      final ordered = pages.values.whereType<Map>().toList()
        ..sort((a, b) => ((a['index'] as num?) ?? 999).compareTo((b['index'] as num?) ?? 999));
      for (final p in ordered) {
        final title = '${p['title'] ?? ''}'.toLowerCase();
        if (accept != null && !accept(title)) continue;
        if (RegExp(r'(map|logo|flag|coat of arms|diagram|chart|seal|signature|icon)', caseSensitive: false).hasMatch(title) &&
            !q.contains('map') && !q.contains('chart') && !q.contains('flag')) {
          continue; // avoid maps/logos/diagrams unless asked for
        }
        final info = (p['imageinfo'] as List?)?.firstOrNull;
        if (info is! Map) continue;
        if ((info['width'] as num? ?? 0) < 800 || !'${info['mime']}'.startsWith('image/')) continue;
        final thumb = Uri.tryParse('${info['thumburl'] ?? info['url']}');
        if (thumb == null || thumb.scheme != 'https' || !isWikimediaHost(thumb.host)) continue;
        if (_claim(thumb.toString(), claimId)) return thumb.toString();
      }
    } catch (_) {}
    return null;
  }

  /// A relevant photo by the story's own keywords: the file title must
  /// contain at least one of the story's key words, so no random matches.
  static Future<String?> commonsImage(Story s) async {
    final names = _properNouns(s.title)
        .expand((p) => p.toLowerCase().split(RegExp(r'\s+')))
        .where((w) => w.length >= 4 && !TextTokens.isStopWord(w))
        .toSet();
    final words = TextTokens.tokens(s.title).where((w) => w.length >= 5).toSet();
    // Relevant only if the file names a person/place/organisation from the
    // headline, or shares at least two specific words with it.
    bool relevant(String title) => names.any(title.contains) || words.where(title.contains).length >= 2;
    for (final q in imageQueries(s).where((q) => q != s.category.label).take(3)) {
      final img = await _commons(q, s.id, accept: relevant);
      if (img != null) return img;
    }
    return null;
  }

  /// A good photo for a topic (Topics grid, rings, and story fallback).
  static Future<String?> topicImage(Category c, {String? claimFor}) async {
    final key = 'topic:${c.name}:${claimFor ?? ''}';
    if (_keyed.containsKey(key)) return _keyed[key];
    if (!enabled) return null;
    String? found;
    for (final q in concepts[c] ?? const <String>[]) {
      found = await _commons(q, claimFor ?? key);
      if (found != null) break;
    }
    _keyed[key] = found;
    return found;
  }

  /// A photo of a place (rings / cards), e.g. its skyline or landmark.
  static Future<String?> placeImage(String name, String id) async {
    final key = 'place:$id';
    if (_keyed.containsKey(key)) return _keyed[key];
    if (!enabled) return null;
    final n = name.toLowerCase();
    String? found;
    for (final q in ['$name skyline', '$name city', name]) {
      found = await _commons(q, key, accept: (t) => t.contains(n.split(' ').first));
      if (found != null) break;
    }
    _keyed[key] = found;
    return found;
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
