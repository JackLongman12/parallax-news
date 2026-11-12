import 'dart:async';
import 'dart:math' as math;

import '../data/geo.dart';
import '../models/article.dart';
import '../models/bias.dart';
import '../models/category.dart';
import '../models/place.dart';
import '../models/source.dart';
import '../models/story.dart';
import 'bias_service.dart';
import 'classifier.dart';
import 'clustering.dart';
import 'curator.dart';
import 'net.dart';
import 'places.dart';
import 'providers.dart';
import 'text.dart';

class FetchSettings {
  bool useBing = true;
  bool useGdelt = false;
  bool discoverLocal = true;
  int maxLocalOutlets = 10;
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

  final Map<String, NewsBundle> _cache = {};
  final Map<String, Future<NewsBundle>> _inflight = {};
  final Map<String, List<SourceInfo>> _outletCache = {};
  static const _ttl = Duration(minutes: 15);

  int get _concurrency => settings.lite ? 2 : 4;

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

  Future<List<SourceInfo>> outletsFor(Place p) async {
    final key = p.id;
    final hit = _outletCache[key];
    if (hit != null) return hit;
    try {
      final list = await PlaceService.outletsIn(p).timeout(const Duration(seconds: 25));
      bias.addDiscovered(list);
      _outletCache[key] = list;
      return list;
    } catch (_) {
      return const [];
    }
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
        tasks.add(() => GoogleNews.topic('WORLD', home, Category.world));
        tasks.add(() => GoogleNews.topHeadlines(home));
        if (!home.isEnglish) tasks.add(() => GoogleNews.topic('WORLD', Edition.us, Category.world));
        if (settings.useBing) tasks.add(() => BingNews.search('world news'));
      case PlaceLevel.continent:
        tasks.add(() => GoogleNews.search('${p.name} when:2d', Edition.us));
        if (settings.useBing) tasks.add(() => BingNews.search(p.name));
      case PlaceLevel.country:
        final native = editionFor(p.countryCode);
        if (native != null) {
          tasks.add(() => GoogleNews.topHeadlines(native));
          tasks.add(() => GoogleNews.topic('NATION', native, Category.politics));
        }
        if (native == null || !native.isEnglish) {
          tasks.add(() => GoogleNews.search('"${p.name}" when:2d', Edition.us));
        }
        if (settings.useBing) tasks.add(() => BingNews.search(p.name));
        if (settings.useGdelt) tasks.add(() => Gdelt.search('"${p.name}"', countryCode: p.countryCode));
      case PlaceLevel.region:
      case PlaceLevel.district:
      case PlaceLevel.city:
      case PlaceLevel.locality:
        final q = parent.isEmpty ? '"${p.name}"' : '"${p.name}" $parent';
        tasks.add(() => GoogleNews.search(q, ed, isLocal: p.isLocalLevel));
        if (p.level == PlaceLevel.city || p.level == PlaceLevel.locality) {
          tasks.add(() => GoogleNews.geo(parent.isEmpty ? p.name : '${p.name}, $parent', ed));
        }
        if (settings.useBing) tasks.add(() => BingNews.search(q, isLocal: p.isLocalLevel));
        if (settings.useGdelt) tasks.add(() => Gdelt.search('"${p.name}"', countryCode: p.countryCode));
    }

    // Local outlet discovery: real community papers, radio and TV stations.
    var outlets = <SourceInfo>[];
    if (settings.discoverLocal && p.level.index >= PlaceLevel.country.index) {
      outlets = await outletsFor(p);
      final maxOutlets = p.level == PlaceLevel.country
          ? 6
          : (settings.lite ? (settings.maxLocalOutlets ~/ 2) : settings.maxLocalOutlets);
      final ranked = [...outlets]..sort((a, b) => (b.feedUrl != null ? 1 : 0) - (a.feedUrl != null ? 1 : 0));
      for (final o in ranked.take(maxOutlets)) {
        final local = p.level != PlaceLevel.country;
        if (o.feedUrl != null) {
          tasks.add(() => DirectFeed.fetch(o.feedUrl!, sourceName: o.name, domain: o.domain, isLocal: local));
        } else {
          tasks.add(() => GoogleNews.site(o.domain, ed, isLocal: local));
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
              : () => GoogleNews.site(o.domain, ed, isLocal: local)
      ]);
    }

    // 2. Looser searches: longer time window, no parent qualifier, other engines.
    batches.add([
      () => GoogleNews.search('"${p.name}" when:30d', ed, isLocal: local),
      if (parent.isNotEmpty) () => GoogleNews.search('${p.name} $parent news', ed, isLocal: local),
      if (!ed.isEnglish) () => GoogleNews.search('"${p.name}"', Edition.us, isLocal: local),
      () => BingNews.search('${p.name} news', isLocal: local),
      if (!settings.useGdelt) () => Gdelt.search('"${p.name}"', countryCode: p.countryCode),
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
              ? () => GoogleNews.site(s.domain, ed, isLocal: false)
              : () => GoogleNews.search('site:${s.domain} "${p.name}"', ed, isLocal: local),
      ]);
    }

    // 4. Last resort for tiny places: news from the parent area.
    if (parent.isNotEmpty && local) {
      batches.add([
        () => GoogleNews.search('"$parent" when:7d', ed, isLocal: true),
        () => BingNews.search(parent, isLocal: true),
      ]);
    }
    return batches;
  }

  Future<NewsBundle> _loadTopic(Category c) async {
    final errors = <String>[];
    final ed = editionFor(settings.homeCountry) ?? Edition.us;
    final tasks = <Future<List<Article>> Function()>[];
    if (c.gnTopic != null) tasks.add(() => GoogleNews.topic(c.gnTopic!, ed, c));
    final q = c.searchQuery;
    if (q != null) tasks.add(() => GoogleNews.search('$q when:2d', ed, hint: c));
    final specialists = bias.curated.where((s) => s.feedUrl != null && s.topics.contains(c)).toList();
    for (final s in specialists.take(settings.lite ? 4 : 8)) {
      tasks.add(() => DirectFeed.fetch(s.feedUrl!, sourceName: s.name, domain: s.domain, hint: c));
    }
    if (tasks.isEmpty) tasks.add(() => GoogleNews.search('${c.label} when:2d', ed, hint: c));
    final articles = await _run(tasks, errors);
    return _finish(articles, errors);
  }

  /// The daily briefing: everything the reader follows, merged, re-clustered
  /// across sources and ranked by the [Curator].
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
    if (s.category != Category.general && s.category != Category.local) {
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
            return await t();
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

  Future<NewsBundle> _finish(List<Article> articles, List<String> errors, {List<SourceInfo> outlets = const []}) async {
    await _enrichUnrated(articles);
    bias.annotate(articles);
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
