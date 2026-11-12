import 'dart:convert';
import 'dart:math' as math;

import '../data/subtopics.dart';
import '../models/article.dart';
import '../models/bias.dart';
import '../models/category.dart';
import '../models/story.dart';
import 'text.dart';

/// On-device recommendation profile, in the spirit of TikTok / Instagram
/// ranking but computed entirely on the phone (nothing is uploaded).
///
/// Implicit signals, weakest to strongest:
///   * impression – card was on screen ~1s but not opened      (-0.05)
///   * bounce     – opened then left in under 4s               (-0.4)
///   * open       – tapped the story                           (+1.0)
///   * dwell      – seconds spent reading the story page       (up to +2.5)
///   * click-through – opened an outlet's article             (+1.2, +outlet)
///   * share                                                   (+2.5)
/// Explicit: "More like this" (+4), "Less like this" (-4), hide outlet.
///
/// Each signal updates three things: the story's topic, its outlets and its
/// headline keywords — so the feed learns "AI chips" vs "AI regulation", not
/// just "Technology". Weights decay ~10%/day so tastes can change.
class InterestProfile {
  final Map<Category, double> weights = {};
  final Map<String, double> sources = {};
  final Map<String, double> keywords = {};
  final Set<Category> muted = {};
  final Set<String> hiddenSources = {};

  /// Interest by time of day: "category:bucket" (bucket = 6-hour window).
  final Map<String, double> hourly = {};

  /// Topic of the story read most recently (avoid serving more of the same right away).
  Category? lastRead;

  static int get _bucket => DateTime.now().hour ~/ 6;
  DateTime lastDecay = DateTime.now();
  int signals = 0;

  final Set<String> _seenThisSession = {};

  static const maxKeywords = 1500;
  static const maxSources = 800;

  void _bump(Story s, double w, {double kwFactor = 0.35, double srcFactor = 0.4}) {
    _maybeDecay();
    weights[s.category] = (weights[s.category] ?? 0) + w;
    for (final a in s.uniqueSources.take(4)) {
      sources[a.domain] = (sources[a.domain] ?? 0) + w * srcFactor;
    }
    for (final t in TextTokens.stemSet(s.title)) {
      keywords[t] = (keywords[t] ?? 0) + w * kwFactor;
    }
    signals++;
    _prune();
  }

  final Map<Category, int> _sessionCats = {};

  /// How many stories of [c] were scrolled past this session (fatigue).
  int sessionSeen(Category c) => _sessionCats[c] ?? 0;

  void recordImpression(Story s) {
    if (_seenThisSession.add(s.id)) {
      _sessionCats[s.category] = (_sessionCats[s.category] ?? 0) + 1;
      _bump(s, -0.05);
    }
  }

  void recordOpen(Story s) {
    _bump(s, 1.0);
    lastRead = s.category;
    final k = '${s.category.name}:$_bucket';
    hourly[k] = (hourly[k] ?? 0) + 1.0;
  }

  /// 0..1: how much this topic is read at the current time of day.
  double timeAffinity(Category c) => _squash(hourly['${c.name}:$_bucket'] ?? 0, 4);

  void recordDwell(Story s, Duration d) {
    final secs = d.inMilliseconds / 1000.0;
    if (secs < 4) {
      _bump(s, -0.4); // bounced: the headline over-promised
    } else {
      _bump(s, math.min(2.5, secs / 25));
    }
  }

  void recordClickThrough(Story s, Article a) {
    sources[a.domain] = (sources[a.domain] ?? 0) + 1.2;
    _bump(s, 0.8);
  }

  void recordShare(Story s) => _bump(s, 2.5);
  void moreLikeThis(Story s) => _bump(s, 4.0);
  void lessLikeThis(Story s) => _bump(s, -4.0);

  void _maybeDecay() {
    final days = DateTime.now().difference(lastDecay).inHours / 24.0;
    if (days < 1) return;
    final f = math.pow(0.9, days).toDouble();
    weights.updateAll((_, v) => v * f);
    sources.updateAll((_, v) => v * f);
    keywords.updateAll((_, v) => v * f);
    hourly.updateAll((_, v) => v * f);
    lastDecay = DateTime.now();
  }

  void _prune() {
    void trim(Map<String, double> m, int max) {
      if (m.length <= max) return;
      final entries = m.entries.toList()..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
      m
        ..clear()
        ..addEntries(entries.take((max * 0.8).round()));
    }

    trim(keywords, maxKeywords);
    trim(sources, maxSources);
  }

  static double _squash(double v, double scale) {
    final x = v / scale;
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1); // tanh
  }

  /// -1..1 affinity for a topic (kept for UI / simple uses).
  double affinity(Category c) => _squash(weights[c] ?? 0, 6);

  /// Personal relevance of a story, roughly -4.5..4.5.
  double score(Story s) {
    final cat = affinity(s.category);
    final srcs = s.uniqueSources.take(6).toList();
    final src = srcs.isEmpty
        ? 0.0
        : srcs.map((a) => _squash(sources[a.domain] ?? 0, 3)).reduce((a, b) => a + b) / srcs.length;
    final toks = TextTokens.stemSet(s.title);
    var kw = 0.0;
    if (toks.isNotEmpty) {
      // Use the strongest matching keywords (a single strong interest should count).
      final vals = toks.map((t) => _squash(keywords[t] ?? 0, 2.5)).toList()..sort((a, b) => b.abs().compareTo(a.abs()));
      kw = vals.take(3).fold(0.0, (a, b) => a + b) / 3;
    }
    return cat * 2.0 + src * 1.0 + kw * 1.5;
  }

  bool isHidden(Story s) {
    if (hiddenSources.isEmpty) return false;
    return s.uniqueSources.every((a) => hiddenSources.contains(a.domain));
  }

  String toJsonString() => jsonEncode({
        'w': weights.map((k, v) => MapEntry(k.name, v)),
        's': sources,
        'k': keywords,
        'm': muted.map((c) => c.name).toList(),
        'h': hiddenSources.toList(),
        't': lastDecay.toIso8601String(),
        'n': signals,
        'hr': hourly,
      });

  void loadJsonString(String s) {
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      (j['w'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
        final c = Category.byName(k);
        if (c != null) weights[c] = (v as num).toDouble();
      });
      (j['s'] as Map<String, dynamic>? ?? {}).forEach((k, v) => sources[k] = (v as num).toDouble());
      (j['k'] as Map<String, dynamic>? ?? {}).forEach((k, v) => keywords[k] = (v as num).toDouble());
      for (final m in (j['m'] as List? ?? const [])) {
        final c = Category.byName(m.toString());
        if (c != null) muted.add(c);
      }
      hiddenSources.addAll((j['h'] as List? ?? const []).map((e) => e.toString()));
      lastDecay = DateTime.tryParse(j['t'] as String? ?? '') ?? DateTime.now();
      signals = (j['n'] as num?)?.toInt() ?? 0;
      (j['hr'] as Map<String, dynamic>? ?? {}).forEach((k, v) => hourly[k] = (v as num).toDouble());
    } catch (_) {}
  }

  void reset() {
    weights.clear();
    sources.clear();
    keywords.clear();
    signals = 0;
  }
}

/// Builds the feed: relevance (personal score) + freshness + coverage breadth,
/// then a diversity pass and exploration slots so the feed never collapses
/// into a bubble — the main difference from engagement-only social feeds.
class Curator {
  static List<Story> rank(List<Story> stories, InterestProfile profile, {int limit = 60}) {
    final now = DateTime.now().toUtc();
    // Personalisation strength grows with the number of signals collected.
    final trust = math.min(1.0, profile.signals / 40.0);
    for (final s in stories) {
      final sources = s.uniqueSources.length;
      final ageH = s.latest == null ? 24.0 : now.difference(s.latest!).inMinutes / 60.0;
      final fresh = math.exp(-math.max(0, ageH) / 18.0);
      final coverage = math.log(1 + sources) / math.ln2;
      final personal = profile.score(s);
      final dist = s.distribution;
      var score = coverage * 1.4 + fresh * 3.0 + personal * (0.6 + 1.4 * trust) + balanceOf(dist) * 0.5;
      if (s.hasLocal) score += 1.0;
      if (s.imageUrl != null) score += 0.2;
      // Prefer stories several outlets cover: they show real left/center/right
      // contrast. Single-outlet items sink unless they are local news.
      if (sources == 1 && !s.hasLocal) score -= 1.8;
      if (sources >= 3) score += 0.8;
      if (dist.isReliable) score += 0.6;
      // Time of day: e.g. markets in the morning, sports in the evening.
      score += profile.timeAffinity(s.category) * 0.8 * trust;
      // Developing stories: share of reports from the last 2 hours.
      score += developing(s, now) * 1.2;
      // Just read this topic? Lead with something else first.
      if (profile.lastRead == s.category) score -= 0.5;
      // Session fatigue: topics you've already scrolled past a lot cool off.
      score -= 0.25 * math.min(8, profile.sessionSeen(s.category));
      // A little randomness so each refresh feels different.
      score += (rng.nextDouble() - 0.5) * 0.6;
      if (profile.muted.contains(s.category) || profile.isHidden(s)) score -= 100;
      s.score = score;
    }
    final pool = stories.where((s) => s.score > -50).toList()..sort((a, b) => b.score.compareTo(a.score));

    // Dynamic exploration: the narrower your interests look, the more often
    // we slot in something new (every 2nd..7th story).
    final every = exploreEvery(profile);
    final picked = <Story>[];
    final catCount = <Category, int>{};
    final srcCount = <String, int>{};
    Side? lastSkew;
    while (picked.length < limit && pool.isNotEmpty) {
      var bestI = 0;
      var bestScore = double.negativeInfinity;
      final explore = picked.length % every == every - 1;
      for (var i = 0; i < pool.length && i < 80; i++) {
        final s = pool[i];
        double adj;
        if (explore) {
          // Prefer topics with little interest so far, weighted by quality.
          final novelty = 1 - profile.affinity(s.category).clamp(0.0, 1.0);
          final unseen = catCount.containsKey(s.category) ? 0.0 : 1.5;
          adj = s.score * 0.35 + novelty * 3 + unseen + rng.nextDouble();
        } else {
          adj = s.score *
              math.pow(0.72, catCount[s.category] ?? 0) *
              math.pow(0.85, srcCount[s.lead.domain] ?? 0);
          // Avoid two one-sided stories from the same side in a row.
          final skew = s.distribution.skewedTo;
          if (skew != null && skew == lastSkew) adj *= 0.8;
        }
        if (adj > bestScore) {
          bestScore = adj.toDouble();
          bestI = i;
        }
      }
      final s = pool.removeAt(bestI);
      picked.add(s);
      catCount[s.category] = (catCount[s.category] ?? 0) + 1;
      srcCount[s.lead.domain] = (srcCount[s.lead.domain] ?? 0) + 1;
      lastSkew = s.distribution.skewedTo;
    }
    return picked;
  }

  static final math.Random rng = math.Random();

  /// 0..1: how much of a story's coverage appeared in the last 2 hours
  /// (only counts once 3+ outlets are on it).
  static double developing(Story s, DateTime now) {
    final dated = s.articles.map((a) => a.published).whereType<DateTime>().toList();
    if (s.uniqueSources.length < 3 || dated.isEmpty) return 0;
    final recent = dated.where((d) => now.difference(d).inMinutes <= 120).length;
    return recent / dated.length;
  }

  /// How spread out the reader's interests are: 0 = one topic, 1 = even.
  static double interestSpread(InterestProfile p) {
    final pos = p.weights.values.where((w) => w > 0).toList();
    if (pos.length < 2) return pos.isEmpty ? 1.0 : 0.0;
    final sum = pos.fold<double>(0, (a, b) => a + b);
    var h = 0.0;
    for (final w in pos) {
      final q = w / sum;
      h -= q * math.log(q);
    }
    return (h / math.log(pos.length)).clamp(0.0, 1.0) * math.min(1.0, pos.length / 6);
  }

  /// Exploration slot frequency: every 2nd story for a narrow reader, up to
  /// every 7th for someone who already reads widely. New users: every 4th.
  static int exploreEvery(InterestProfile p) {
    if (p.signals < 10) return 4;
    return (2 + interestSpread(p) * 5).round().clamp(2, 7);
  }

  /// 1.0 = covered evenly by left, center and right; 0.0 = one side only.
  static double balanceOf(BiasDistribution d) {
    if (!d.isReliable) return 0.5;
    final maxShare = [Side.left, Side.center, Side.right].map(d.share).reduce(math.max);
    return (1 - (maxShare - 1 / 3) / (2 / 3)).clamp(0.0, 1.0);
  }
}

/// Recommends subtopics / niches: some matched to the reader's interests,
/// some deliberately outside them to break the bubble.
class SubtopicSuggester {
  static double _interest(InterestProfile p, SubPath sp) {
    final kw = sp.leaf.keywords;
    var s = 0.0;
    for (final k in kw) {
      s += p.keywords[k] ?? 0;
    }
    return s / (kw.isEmpty ? 1 : kw.length) * 2 + p.affinity(sp.category) * 1.5 + sp.chain.length * 0.1;
  }

  /// Best matches for the reader (only once there is something to go on).
  static List<SubPath> forYou(InterestProfile p, {int n = 8}) {
    final paths = allSubPaths().where((sp) => !p.muted.contains(sp.category)).toList();
    final scored = [for (final sp in paths) (sp, _interest(p, sp))]..sort((a, b) => b.$2.compareTo(a.$2));
    return scored.where((e) => e.$2 > 0.05).take(n).map((e) => e.$1).toList();
  }

  /// Subtopics from topics the reader rarely touches; reshuffled each call.
  static List<SubPath> breakOut(InterestProfile p, {int n = 6}) {
    final cold = allSubPaths()
        .where((sp) => sp.chain.length == 1 && !p.muted.contains(sp.category) && p.affinity(sp.category) <= 0.15)
        .toList()
      ..shuffle(Curator.rng);
    final seenCats = <Category>{};
    return [for (final sp in cold) if (seenCats.add(sp.category)) sp].take(n).toList();
  }
}
