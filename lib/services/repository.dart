import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

import '../data/geo.dart';
import '../data/subtopics.dart';
import '../models/article.dart';
import '../models/bias.dart';
import '../models/category.dart';
import '../models/place.dart';
import '../models/source.dart';
import '../models/story.dart';
import 'bias_service.dart';
import 'classifier.dart';
import 'clustering.dart';
import 'crawler_feed.dart';
import 'curator.dart';
import 'net.dart';
import 'places.dart';
import 'provider_health.dart';
import 'providers.dart';
import 'text.dart';

class FetchSettings {
  bool useBing = true;
  bool useGdelt = false;

  /// Auto mode: route around slow / rate-limited sources automatically.
  bool autoSources = true;
  bool discoverLocal = true;
  int maxLocalOutlets = 25;
  /// Lower concurrency + fewer outlets for weak phones / metered data.
  bool lite = false;
  String homeCountry = 'US';
}

class NewsBundle {
  NewsBundle({
    required this.articles,
    required this.stories,
    this.outlets = const [],
    this.errors = const [],
  }) : fetchedAt = DateTime.now();

  final List<Article> articles;
  final List<Story> stories;
  final List<SourceInfo> outlets;
  final List<String> errors;
  final DateTime fetchedAt;
}

/// Orchestrates providers -> bias annotation -> classifier -> clustering.
class NewsRepository {
  NewsRepository({required this.bias, required this.classifier, required this.settings});

  final BiasService bias;
  final TopicClassifier classifier;
  final FetchSettings settings;
  void Function()? onModelUpdated;
  void Function()? onRatingsUpdated;

  /// Set by widget tests (no network available there).
  static bool offline = false;

  final Map<String, NewsBundle> _cache = {};
  final Map<String, Future<NewsBundle>> _inflight = {};
  final Map<String, List<SourceInfo>> _outletCache = {};
  static const _ttl = Duration(minutes: 15);

  int get _concurrency => settings.lite ? 3 : 6;

  /// Each source gets this long; slow ones are skipped (caught next refresh).
  static const taskBudget = Duration(seconds: 7);

  bool get _useBing => settings.autoSources || settings.useBing;

  /// GDELT is slow and rate limited, so Auto mode only adds it where it helps
  /// most: places Google covers poorly (no edition / non-English). Thin
  /// coverage also pulls it in via the widening fallbacks.
  bool _useGdelt(Place p) {
    if (!settings.autoSources) return settings.useGdelt;
    if (!ProviderHealth.instance.available('gdelt')) return false;
    if (p.level.index < PlaceLevel.country.index) return false;
    final ed = editionFor(p.countryCode);
    return ed == null || !ed.isEnglish;
  }

  static final _whenRe = RegExp(r'\s*when:\d+d');

  /// Google first. In Auto mode, if Google fails, is paused or returns
  /// nothing, the equivalent query runs on Bing instead.
  Future<List<Article>> Function() _gn(Future<List<Article>> Function() google, String bingQuery,
      {bool isLocal = false, Category? hint}) {
    return () async {
      final auto = settings.autoSources;
      Object? err;
      if (!auto || ProviderHealth.instance.available('google')) {
        try {
          final r = await google();
          if (r.isNotEmpty || !auto) return r;
        } catch (e) {
          if (!auto) rethrow;
          err = e;
        }
      }
      if (!auto || !ProviderHealth.instance.available('bing')) {
        if (err != null) throw err;
        return const <Article>[];
      }
      final r = await BingNews.search(bingQuery.replaceAll(_whenRe, ''), isLocal: isLocal);
      if (hint != null) {
        for (final a in r) {
          a.hintCategory ??= hint;
        }
      }
      return r;
    };
  }


  NewsBundle? cached(String key) => _cache[key];

  Future<NewsBundle> _memo(String key, bool force, Future<NewsBundle> Function() load) {
    final hit = _cache[key];
    if (!force && hit != null && DateTime.now().difference(hit.fetchedAt) < _ttl) {
      return Future.value(hit);
    }
    final running = _inflight[key];
    if (running != null) return running;
    if (force) Net.clearCache();
    final f = load().then((b) {
      _cache[key] = b;
      return b;
    }).whenComplete(() {
      _inflight.remove(key);
    });
    _inflight[key] = f;
    return f;
  }

  Future<NewsBundle> place(Place p, {bool force = false}) =>
      _memo('place:${p.id}', force, () => _loadPlace(p));

  Future<NewsBundle> topic(Category c, {bool force = false}) =>
      _memo('topic:${c.name}', force, () => _loadTopic(c));

  /// Persistent store for slow lookups (set by AppState).
  SharedPreferences? store;
  final Map<String, Future<List<SourceInfo>>> _outletInflight = {};

  /// Local outlets for a place. Wikidata is slow, so results are kept on the
  /// phone for 7 days and repeat visits never wait for it.
  Future<List<SourceInfo>> outletsFor(Place p) async {
    final key = p.id;
    final hit = _outletCache[key];
    if (hit != null) return hit;
    try {
      final raw = store?.getString('outlets:$key');
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final at = DateTime.tryParse(j['at'] as String? ?? '');
        if (at != null && DateTime.now().difference(at) < const Duration(days: 7)) {
          final list = (j['o'] as List).whereType<Map<String, dynamic>>().map(SourceInfo.fromJson).toList();
          bias.addDiscovered(list);
          return _outletCache[key] = list;
        }
      }
    } catch (_) {}
    return _outletInflight[key] ??= () async {
      try {
        final list = await PlaceService.outletsIn(p).timeout(const Duration(seconds: 15));
        bias.addDiscovered(list);
        _outletCache[key] = list;
        store?.setString('outlets:$key', jsonEncode({'at': DateTime.now().toIso8601String(), 'o': list.map((s) => s.toJson()).toList()}));
        return list;
      } catch (_) {
        return const <SourceInfo>[];
      } finally {
        _outletInflight.remove(key);
      }
    }();
  }

  Edition _edition(Place p) =>
      editionFor(p.countryCode) ?? editionFor(settings.homeCountry) ?? Edition.us;

  Future<NewsBundle> _loadPlace(Place p) async {
    final errors = <String>[];
    final tasks = <Future<List<Article>> Function()>[];
    final ed = _edition(p);
    final parent = p.parents.isNotEmpty ? p.parents.first : '';

    switch (p.level) {
      case PlaceLevel.world:
        final home = editionFor(settings.homeCountry) ?? Edition.us;
        tasks.add(_gn(() => GoogleNews.topic('WORLD', home, Category.world), 'world news', hint: Category.world));
        tasks.add(_gn(() => GoogleNews.topHeadlines(home), 'top news'));
        if (!home.isEnglish) tasks.add(_gn(() => GoogleNews.topic('WORLD', Edition.us, Category.world), 'international news', hint: Category.world));
        if (_useBing) tasks.add(() => BingNews.search('world news'));
      case PlaceLevel.continent:
        tasks.add(_gn(() => GoogleNews.search('${p.name} when:2d', Edition.us), p.name));
        if (_useBing) tasks.add(() => BingNews.search(p.name));
      case PlaceLevel.country:
        final native = editionFor(p.countryCode);
        if (native != null) {
          tasks.add(_gn(() => GoogleNews.topHeadlines(native), '${p.name} news'));
          tasks.add(_gn(() => GoogleNews.topic('NATION', native, Category.politics), '${p.name} politics', hint: Category.politics));
        }
        if (native == null || !native.isEnglish) {
          tasks.add(_gn(() => GoogleNews.search('"${p.name}" when:2d', Edition.us), '"${p.name}"'));
        }
        if (_useBing) tasks.add(() => BingNews.search(p.name));
        if (_useGdelt(p)) tasks.add(() => Gdelt.search('"${p.name}"', countryCode: p.countryCode));
      case PlaceLevel.region:
      case PlaceLevel.district:
      case PlaceLevel.city:
      case PlaceLevel.locality:
        final q = parent.isEmpty ? '"${p.name}"' : '"${p.name}" $parent';
        tasks.add(_gn(() => GoogleNews.search(q, ed, isLocal: p.isLocalLevel), q, isLocal: p.isLocalLevel));
        if (p.level == PlaceLevel.city || p.level == PlaceLevel.locality) {
          tasks.add(_gn(() => GoogleNews.geo(parent.isEmpty ? p.name : '${p.name}, $parent', ed), '${p.name} $parent local news', isLocal: true));
        }
        if (_useBing) tasks.add(() => BingNews.search(q, isLocal: p.isLocalLevel));
        if (_useGdelt(p)) tasks.add(() => Gdelt.search('"${p.name}"', countryCode: p.countryCode));
    }

    // Local outlet discovery: real community papers, radio and TV stations.
    var outlets = <SourceInfo>[];
    if (settings.discoverLocal && p.level.index >= PlaceLevel.country.index) {
      outlets = await outletsFor(p).timeout(const Duration(milliseconds: 1500), onTimeout: () => const <SourceInfo>[]);
      final maxOutlets = p.level == PlaceLevel.country
          ? 6
          : (settings.lite ? (settings.maxLocalOutlets ~/ 2) : settings.maxLocalOutlets);
      final ranked = outlets.where((o) => !_quietOutlets.contains(o.domain)).toList()..sort((a, b) => (b.feedUrl != null ? 1 : 0) - (a.feedUrl != null ? 1 : 0));
      for (final o in ranked.take(maxOutlets)) {
        final local = p.level != PlaceLevel.country;
        if (o.feedUrl != null) {
          tasks.add(() => DirectFeed.fetch(o.feedUrl!, sourceName: o.name, domain: o.domain, isLocal: local));
        } else {
          tasks.add(_gn(() => GoogleNews.site(o.domain, ed, isLocal: local), 'site:${o.domain}', isLocal: local));
        }
      }
    }

    final articles = await _run(tasks, errors);

    // Guarantee breadth: keep widening the net until at least [minSources]
    // distinct outlets cover this place (or we run out of strategies).
    for (final batch in _widenings(p, ed, parent, outlets)) {
      if (_distinct(articles) >= minSources) break;
      articles.addAll(await _run(batch, errors));
    }
    return _finish(articles, errors, outlets: outlets);
  }

  /// Minimum number of distinct outlets we try to show for any place.
  static const minSources = 10;

  static int _distinct(List<Article> a) => a.map((x) => x.domain).toSet().length;

  /// Progressively broader fallbacks, cheapest first.
  List<List<Future<List<Article>> Function()>> _widenings(
      Place p, Edition ed, String parent, List<SourceInfo> outlets) {
    final batches = <List<Future<List<Article>> Function()>>[];
    final local = p.isLocalLevel;

    // 1. Remaining discovered outlets for this place that weren't fetched yet.
    final usedMax = p.level == PlaceLevel.country ? 6 : settings.maxLocalOutlets;
    final rest = outlets.skip(usedMax).take(12).toList();
    if (rest.isNotEmpty) {
      batches.add([
        for (final o in rest)
          o.feedUrl != null
              ? () => DirectFeed.fetch(o.feedUrl!, sourceName: o.name, domain: o.domain, isLocal: local)
              : _gn(() => GoogleNews.site(o.domain, ed, isLocal: local), 'site:${o.domain}', isLocal: local)
      ]);
    }

    // 2. Looser searches: longer time window, no parent qualifier, other engines.
    batches.add([
      _gn(() => GoogleNews.search('"${p.name}" when:30d', ed, isLocal: local), '"${p.name}"', isLocal: local),
      if (parent.isNotEmpty) _gn(() => GoogleNews.search('${p.name} $parent news', ed, isLocal: local), '${p.name} $parent', isLocal: local),
      if (!ed.isEnglish) _gn(() => GoogleNews.search('"${p.name}"', Edition.us, isLocal: local), '${p.name} news', isLocal: local),
      () => BingNews.search('${p.name} news', isLocal: local),
      if (!_useGdelt(p)) () => Gdelt.search('"${p.name}"', countryCode: p.countryCode),
    ]);

    // 3. Curated outlets from the same country / continent, via site: search
    //    for this place's name (country & continent levels use their latest news).
    final catalog = bias.curated.where((s) => s.topics.isEmpty).where((s) {
      if (p.level == PlaceLevel.continent) {
        return countryByCode(s.country)?.continent == p.continentCode;
      }
      return p.countryCode != null && s.country == p.countryCode;
    }).take(12).toList();
    if (catalog.isNotEmpty) {
      final broad = p.level == PlaceLevel.continent || p.level == PlaceLevel.country;
      batches.add([
        for (final s in catalog)
          broad
              ? _gn(() => GoogleNews.site(s.domain, ed, isLocal: false), 'site:${s.domain}')
              : _gn(() => GoogleNews.search('site:${s.domain} "${p.name}"', ed, isLocal: local), 'site:${s.domain} ${p.name}', isLocal: local),
      ]);
    }

    // 4. Last resort for tiny places: news from the parent area.
    if (parent.isNotEmpty && local) {
      batches.add([
        _gn(() => GoogleNews.search('"$parent" when:7d', ed, isLocal: true), '"$parent"', isLocal: true),
        () => BingNews.search(parent, isLocal: true),
      ]);
    }
    return batches;
  }

  Future<NewsBundle> _loadTopic(Category c) async {
    final errors = <String>[];
    final ed = editionFor(settings.homeCountry) ?? Edition.us;
    final tasks = <Future<List<Article>> Function()>[];
    if (c.gnTopic != null) tasks.add(_gn(() => GoogleNews.topic(c.gnTopic!, ed, c), '${c.label} news', hint: c));
    final q = c.searchQuery;
    if (q != null) tasks.add(_gn(() => GoogleNews.search('$q when:2d', ed, hint: c), q, hint: c));
    final specialists = bias.curated.where((s) => s.feedUrl != null && s.topics.contains(c)).toList();
    for (final s in specialists.take(settings.lite ? 4 : 8)) {
      tasks.add(() => DirectFeed.fetch(s.feedUrl!, sourceName: s.name, domain: s.domain, hint: c));
    }
    if (tasks.isEmpty) tasks.add(_gn(() => GoogleNews.search('${c.label} when:2d', ed, hint: c), c.label, hint: c));
    if (_useBing) tasks.add(() => BingNews.search(c.searchQuery ?? '${c.label} news'));
    final articles = await _run(tasks, errors);
    return _finish(articles, errors);
  }

  /// The daily briefing: everything the reader follows, merged, re-clustered
  /// across sources and ranked by the [Curator].
  static const briefTopics = [
    Category.world, Category.politics, Category.business, Category.finance, Category.technology,
    Category.science, Category.health, Category.environment, Category.sports, Category.entertainment,
  ];

  Future<List<Story>>? _brief;
  DateTime _briefAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// "Today in brief": the most widely covered story from EACH major topic,
  /// independent of personal interests, so everyone sees the whole picture.
  Future<List<Story>> dailyBrief({bool force = false}) {
    if (offline) return Future.value(const <Story>[]);
    if (!force && _brief != null && DateTime.now().difference(_briefAt) < _ttl) return _brief!;
    _briefAt = DateTime.now();
    return _brief = () async {
      final home = countryByCode(settings.homeCountry)?.place;
      final bundles = await runPooled<NewsBundle>([
        () => place(Place.world, force: force),
        if (home != null) () => place(home, force: force),
        for (final t in briefTopics) () => topic(t, force: force),
      ], concurrency: settings.lite ? 2 : 4);
      final all = merge(await crawlerStories(force: force), <Story>[for (final b in bundles) ...?b?.stories]);
      final best = <Category, Story>{};
      for (final s in all) {
        final cur = best[s.category];
        if (cur == null || s.uniqueSources.length > cur.uniqueSources.length) best[s.category] = s;
      }
      final picks = best.values.where((s) => s.category != Category.general || best.length < 4).toList()
        ..sort((a, b) => b.uniqueSources.length.compareTo(a.uniqueSources.length));
      return picks.take(8).toList();
    }();
  }

  /// News about one company / asset, for its stock page.
  Future<NewsBundle> stockNews(String symbol, String name, {bool force = false}) =>
      _memo('stock:$symbol', force, () async {
        final errors = <String>[];
        final ed = editionFor(settings.homeCountry) ?? Edition.us;
        final clean = name.replaceAll(RegExp(r'\b(Inc|Corp|Corporation|Ltd|PLC|Holdings|Class [A-C])\b\.?,?', caseSensitive: false), '').trim();
        final q = '"$clean"';
        final articles = await _run([
          _gn(() => GoogleNews.search('$q stock when:7d', ed, hint: Category.finance), '$clean stock', hint: Category.finance),
          _gn(() => GoogleNews.search('$q when:3d', ed, hint: Category.business), clean, hint: Category.business),
          if (_useBing) () => BingNews.search('$clean stock'),
        ], errors);
        return _finish(articles, errors);
      });

  // ---- Crawler stories (many outlets per story) -------------------------
  final Set<String> _annotatedCrawl = {};

  /// Crawler stories, rated with the local catalog. Memory only.
  Future<List<Story>> crawlerStories({bool force = false}) async {
    if (offline) return const [];
    final list = await CrawlerFeed.load(force: force).timeout(const Duration(seconds: 15), onTimeout: () => const []);
    final fresh = list.where((s) => _annotatedCrawl.add(s.id)).toList();
    if (fresh.isNotEmpty) {
      final arts = [for (final s in fresh) ...s.articles];
      arts.removeWhere(isJunk);
      bias.annotate(arts);
    }
    return list;
  }

  /// The crawler is the main source once its feed is loaded and recent. The
  /// phone then only fetches what the crawler is thin on: cities / regions,
  /// countries without a Google News edition, and sparse topics. Fewer
  /// requests on the phone, so feeds fill faster and use less data.
  static bool crawlIsMain(List<Story> crawl) {
    final built = CrawlerFeed.builtAt;
    return crawl.length >= 100 && (built == null || DateTime.now().difference(built) < const Duration(minutes: 45));
  }

  static bool _crawlThinOn(List<Story> crawl, Category t) => crawl.where((s) => s.category == t).length < 15;

  static bool _crawlThinOnPlace(Place p) {
    if (p.level == PlaceLevel.world || p.level == PlaceLevel.continent) return false;
    if (p.level == PlaceLevel.country) return editionFor(p.countryCode) == null;
    return true;
  }

  /// Merges on-device stories into crawler stories: if they share any
  /// article link they are the same story (outlets are combined), otherwise
  /// the device story is added. Crawler stories usually carry far more outlets.
  static List<Story> merge(List<Story> base, List<Story> extra) {
    final byUrl = <String, Story>{};
    for (final s in base) {
      for (final a in s.articles) {
        byUrl[a.url] = s;
      }
    }
    final out = [...base];
    for (final s in extra) {
      Story? hit;
      for (final a in s.articles) {
        hit = byUrl[a.url];
        if (hit != null) break;
      }
      if (hit == null) {
        out.add(s);
        continue;
      }
      final domains = {for (final a in hit.articles) a.domain};
      for (final a in s.articles) {
        if (domains.add(a.domain)) hit.articles.add(a);
      }
    }
    return out;
  }

  /// [device] stories plus crawler stories (optionally of one topic).
  Future<List<Story>> withCrawler(List<Story> device, {Category? category, bool force = false}) async {
    final crawl = await crawlerStories(force: force);
    final pick = category == null ? crawl : crawl.where((s) => s.category == category).toList();
    return merge(pick, device);
  }

  /// Focused feed for a subtopic or niche (general -> subtopic -> niche).
  Future<NewsBundle> subtopic(SubPath sp, {bool force = false}) =>
      _memo('sub:${sp.category.name}:${sp.leaf.label}', force, () async {
        final errors = <String>[];
        final ed = editionFor(settings.homeCountry) ?? Edition.us;
        final q = sp.leaf.query;
        final articles = await _run([
          _gn(() => GoogleNews.search('$q when:4d', ed, hint: sp.category), q, hint: sp.category),
          if (!ed.isEnglish) _gn(() => GoogleNews.search('$q when:4d', Edition.us, hint: sp.category), q, hint: sp.category),
          if (_useBing) () => BingNews.search(q),
        ], errors);
        for (final a in articles) {
          a.hintCategory ??= sp.category;
        }
        return _finish(articles, errors);
      });

  /// Finds MORE outlets covering the same event as [s] (searches Google News
  /// and Bing for the headline's key words, keeps only same-story matches).
  /// Returns the new articles; the caller merges them into the story.
  static final _expanded = Expando<Future<List<Article>>>('expanded');
  int _expandActive = 0;
  final _expandWaiters = <Completer<void>>[];

  /// Finds more outlets for [s] and adds them to it (once per story, at most
  /// two searches at a time). Returns the outlets that were added.
  Future<List<Article>> expandCoverage(Story s) => _expanded[s] ??= _expandOnce(s);

  /// For cards: fill in left/right coverage when the story's lean is still
  /// unknown, so the card shows the same lean as the story page.
  Future<bool> fillLean(Story s) async {
    if (offline || s.distribution.isReliable) return false;
    return (await expandCoverage(s)).isNotEmpty;
  }

  Future<List<Article>> _expandOnce(Story s) async {
    while (_expandActive >= 2) {
      final w = Completer<void>();
      _expandWaiters.add(w);
      await w.future;
    }
    _expandActive++;
    try {
      final more = await _searchMore(s);
      s.articles.addAll(more);
      return more;
    } catch (_) {
      return const [];
    } finally {
      _expandActive--;
      if (_expandWaiters.isNotEmpty) _expandWaiters.removeAt(0).complete();
    }
  }

  Future<List<Article>> _searchMore(Story s) async {
    if (offline) return const [];
    final words = TextTokens.tokens(s.title).where((w) => w.length >= 4).take(7).toList();
    if (words.length < 3) return const [];
    final q = words.join(' ');
    final ed = editionFor(settings.homeCountry) ?? Edition.us;
    final errors = <String>[];
    final found = await _run([
      _gn(() => GoogleNews.search('$q when:3d', ed), q),
      if (!ed.isEnglish) _gn(() => GoogleNews.search('$q when:3d', Edition.us), q),
      () => BingNews.search(q),
    ], errors);
    final have = {for (final a in s.articles) a.url};
    final domains = {for (final a in s.articles) a.domain};
    final toks = TextTokens.stemSet(s.title);
    final fresh = <Article>[];
    for (final a in found) {
      if (have.contains(a.url) || isJunk(a)) continue;
      if (StoryClusterer.similarity(toks, TextTokens.stemSet(a.title)) < 0.34) continue;
      if (domains.add(a.domain)) fresh.add(a);
    }
    bias.annotate(fresh);
    return fresh;
  }

  /// News search for Explore.
  Future<NewsBundle> search(String query, {bool force = false}) {
    final q = query.trim();
    return _memo('search:${q.toLowerCase()}', force, () async {
      final errors = <String>[];
      final ed = editionFor(settings.homeCountry) ?? Edition.us;
      final articles = await _run([
        _gn(() => GoogleNews.search('$q when:7d', ed), q),
        () => BingNews.search(q),
      ], errors);
      return _finish(articles, errors);
    });
  }

  /// Everything from a broad pool (world, your country, politics / world /
  /// business, and what you follow), used by the Blindspot collections.
  Future<List<Story>> broadPool({required List<Place> places, required List<Category> topics, bool force = false}) async {
    final home = countryByCode(settings.homeCountry)?.place;
    final topicSet = {Category.politics, Category.world, Category.business, ...topics};
    final crawl = await crawlerStories(force: force);
    final main = crawlIsMain(crawl);
    final bundles = await runPooled<NewsBundle>([
      if (!main) () => place(Place.world, force: force),
      if (home != null && (!main || _crawlThinOnPlace(home))) () => place(home, force: force),
      for (final p in places)
        if (!main || _crawlThinOnPlace(p)) () => place(p, force: force),
      for (final t in topicSet)
        if (!main || _crawlThinOn(crawl, t)) () => topic(t, force: force),
    ], concurrency: 3);
    final seen = <String>{};
    final all = <Article>[];
    for (final b in bundles) {
      for (final a in b?.articles ?? const <Article>[]) {
        if (seen.add(a.url)) all.add(a);
      }
    }
    return merge(crawl, _clusterAndLabel(all));
  }

  /// Blindspot scan over a broad pool (not just your briefing): world, your
  /// country, politics / world / business news, plus everything you follow.
  Future<List<Story>> blindspotPool({
    required List<Place> places,
    required List<Category> topics,
    bool force = false,
  }) async {
    final home = countryByCode(settings.homeCountry)?.place;
    final topicSet = {Category.politics, Category.world, Category.business, ...topics};
    final bundles = await runPooled<NewsBundle>([
      () => place(Place.world, force: force),
      if (home != null) () => place(home, force: force),
      for (final p in places) () => place(p, force: force),
      for (final t in topicSet) () => topic(t, force: force),
    ], concurrency: settings.lite ? 2 : 3);
    final seen = <String>{};
    final all = <Article>[];
    for (final b in bundles) {
      for (final a in b?.articles ?? const <Article>[]) {
        if (seen.add(a.url)) all.add(a);
      }
    }
    final stories = _clusterAndLabel(all);
    int rank(Story s) => s.distribution.blindspotFor != null ? 0 : 1;
    final picked = stories.where((s) => s.distribution.blindspotFor != null || s.distribution.skewedTo != null).toList()
      ..sort((a, b) {
        final c = rank(a).compareTo(rank(b));
        return c != 0 ? c : b.uniqueSources.length.compareTo(a.uniqueSources.length);
      });
    return picked;
  }

  /// Progressive briefing for a fast start. Emits a ranked feed after each
  /// stage instead of waiting for everything:
  ///   1. World + your first 3 topics (in parallel)
  ///   2. each followed place, one at a time
  ///   3. the remaining topics, one at a time
  Stream<List<Story>> briefingStream({
    required List<Place> places,
    required List<Category> topics,
    required InterestProfile profile,
    bool force = false,
  }) async* {
    final collected = <Article>[];
    final seen = <String>{};
    Future<void> add(Future<NewsBundle> f) async {
      try {
        for (final a in (await f).articles) {
          if (seen.add(a.url)) collected.add(a);
        }
      } catch (_) {}
    }

    var crawl = const <Story>[];
    List<Story> ranked() => Curator.rank(merge(crawl, _clusterAndLabel(collected)), profile);

    // Our crawler's pre-built stories (dozens of outlets each) arrive first.
    crawl = await crawlerStories(force: force);
    if (crawl.isNotEmpty) yield Curator.rank(crawl, profile);
    final main = crawlIsMain(crawl);
    bool needTopic(Category t) => !main || _crawlThinOn(crawl, t);

    // Stage 1: yield as each of World + first 3 topics arrives (fastest first).
    final stage1 = <Future<NewsBundle>>[
      if (!main) place(Place.world, force: force),
      for (final t in topics.take(3))
        if (needTopic(t)) topic(t, force: force),
    ];
    if (stage1.isNotEmpty) {
      final arrivals = StreamController<void>();
      var pending = stage1.length;
      for (final f in stage1) {
        add(f).whenComplete(() {
          arrivals.add(null);
          if (--pending == 0) arrivals.close();
        });
      }
      await for (final _ in arrivals.stream) {
        if (collected.isNotEmpty) yield ranked();
      }
    }
    for (final p in places) {
      if (main && !_crawlThinOnPlace(p)) continue;
      await add(place(p, force: force));
      yield ranked();
    }
    for (final t in topics.skip(3)) {
      if (!needTopic(t)) continue;
      await add(topic(t, force: force));
      yield ranked();
    }
  }

  Future<List<Story>> briefing({
    required List<Place> places,
    required List<Category> topics,
    required InterestProfile profile,
    bool force = false,
  }) async {
    final bundles = await runPooled<NewsBundle>([
      () => place(Place.world, force: force),
      for (final p in places) () => place(p, force: force),
      for (final t in topics) () => topic(t, force: force),
    ], concurrency: settings.lite ? 1 : 2);
    final all = <Article>[];
    for (final b in bundles) {
      if (b != null) all.addAll(b.articles);
    }
    final stories = _clusterAndLabel(all);
    return Curator.rank(stories, profile);
  }

  /// "Related" stories for the story page: same keywords first, then same
  /// topic, nudged by the reader's own interests. Uses already-loaded news
  /// plus the story's topic feed, so it's instant most of the time.
  Future<List<Story>> related(Story s, InterestProfile profile, {int limit = 12}) async {
    if (!offline && s.category != Category.general && s.category != Category.local) {
      try {
        await topic(s.category).timeout(const Duration(seconds: 12));
      } catch (_) {}
    }
    final toks = TextTokens.stemSet(s.title);
    final seenUrls = s.articles.map((a) => a.url).toSet();
    final pool = <String, Story>{};
    for (final b in _cache.values) {
      for (final st in b.stories) {
        if (st.id == s.id || st.articles.any((a) => seenUrls.contains(a.url))) continue;
        pool[st.id] = st;
      }
    }
    final scored = <(Story, double)>[];
    for (final st in pool.values) {
      final sim = StoryClusterer.similarity(toks, TextTokens.stemSet(st.title));
      final sameTopic = st.category == s.category;
      if (sim < 0.12 && !sameTopic) continue;
      final score = sim * 6 + (sameTopic ? 1.0 : 0) + profile.score(st) * 0.4 +
          math.log(1 + st.uniqueSources.length) * 0.3;
      scored.add((st, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(limit).map((e) => e.$1).toList();
  }

  Future<List<Article>> _run(List<Future<List<Article>> Function()> tasks, List<String> errors) async {
    final wrapped = [
      for (final t in tasks)
        () async {
          try {
            return await t().timeout(taskBudget);
          } catch (e) {
            errors.add(e.toString());
            return <Article>[];
          }
        }
    ];
    final results = await runPooled<List<Article>>(wrapped, concurrency: _concurrency);
    return [for (final r in results) ...?r];
  }

  /// Rates outlets we've never seen before via Wikidata (batched, cached).
  Future<void> _enrichUnrated(List<Article> articles) async {
    final unknown = <String>{};
    for (final a in articles) {
      if (bias.lookup(a.domain, name: a.sourceName).bias == Bias.unrated && !bias.lookedUp.contains(a.domain)) {
        unknown.add(a.domain);
      }
    }
    if (unknown.isEmpty) return;
    final list = unknown.take(50).toList();
    bias.lookedUp.addAll(list);
    final chunks = [for (var i = 0; i < list.length; i += 25) list.sublist(i, i + 25 > list.length ? list.length : i + 25)];
    await Future.wait(chunks.map((c) async {
      try {
        final found = await PlaceService.ratingsForDomains(c).timeout(const Duration(seconds: 6));
        bias.addDiscovered(found.values);
      } catch (_) {
        bias.lookedUp.removeAll(c); // retry next time
      }
    }));
    onRatingsUpdated?.call();
  }

  // ---- Garbage filter -------------------------------------------------
  /// Auto-generated filler that adds nothing (stock-holding notices, etc.).
  static final _spam = RegExp(
      r'(acquires? (new )?(stake|position|[\d,]+ shares)|(sells|buys|purchases) [\d,]+ shares|'
      r'(increases|decreases|raises|trims|lifts|cuts) (its )?(stake|position|holdings) in|position in .+ \(|'
      r'price target (raised|lowered|cut|increased)|(stock|shares) (price )?(down|up) [\d.]+%|'
      r'short interest (update|in)|sees (unusually )?(large|high) options volume|'
      r'^(sponsored|advertisement|press release)\b|horoscope|lottery results|crossword)',
      caseSensitive: false);

  /// Known content farms that mass-produce templated "news".
  static const _farms = {
    'marketbeat.com', 'americanbankingnews.com', 'tickerreport.com', 'etfdailynews.com', 'defenseworld.net',
    'thelincolnianonline.com', 'themarketsdaily.com', 'thecerbatgem.com', 'theenterpriseleader.com',
    'modernreaders.com', 'wkrb13.com', 'zolmax.com', 'dailypolitical.com', 'thestockobserver.com',
  };

  static bool isJunk(Article a, {DateTime? now}) {
    now ??= DateTime.now().toUtc();
    final p = a.published;
    final maxAge = a.isLocal ? const Duration(days: 10) : const Duration(days: 4);
    if (p != null && now.difference(p) > maxAge) return true;
    if (_farms.contains(a.domain)) return true;
    if (a.title.length < 12) return true;
    return _spam.hasMatch(a.title);
  }

  /// Local outlets that returned nothing this session (skipped next time so
  /// slots go to outlets that actually publish).
  final Set<String> _quietOutlets = {};

  Future<NewsBundle> _finish(List<Article> articles, List<String> errors, {List<SourceInfo> outlets = const []}) async {
    articles.removeWhere((a) => isJunk(a));
    if (outlets.isNotEmpty) {
      final active = articles.map((a) => a.domain).toSet();
      _quietOutlets.addAll(outlets.map((o) => o.domain).where((d) => !active.contains(d)));
    }
    bias.annotate(articles);
    // Rate never-seen outlets in the background; the shared Article objects
    // are re-annotated in place, so cards pick it up on their next build.
    unawaited(_enrichUnrated(articles).then((_) => bias.annotate(articles)).catchError((_) {}));
    var learned = false;
    for (final a in articles) {
      if (a.hintCategory != null && a.hintCategory != Category.local) {
        classifier.learn(a);
        learned = true;
      }
    }
    if (learned) onModelUpdated?.call();
    final stories = _clusterAndLabel(articles);
    stories.sort((a, b) {
      final c = b.uniqueSources.length.compareTo(a.uniqueSources.length);
      if (c != 0) return c;
      return (b.latest ?? DateTime(0)).compareTo(a.latest ?? DateTime(0));
    });
    return NewsBundle(articles: articles, stories: stories, outlets: outlets, errors: errors);
  }

  List<Story> _clusterAndLabel(List<Article> articles) {
    final stories = StoryClusterer.cluster(articles);
    for (final s in stories) {
      final votes = <Category, int>{};
      for (final a in s.articles) {
        final c = classifier.classify(a);
        votes[c] = (votes[c] ?? 0) + (c == Category.general ? 0 : 2) + 1;
      }
      var best = Category.general;
      var bestV = 0;
      votes.forEach((c, v) {
        if (v > bestV) {
          best = c;
          bestV = v;
        }
      });
      s.category = best;
    }
    return stories;
  }
}
