import 'dart:convert';
import 'dart:math' as math;

import '../models/bias.dart';
import '../models/category.dart';
import '../models/story.dart';

/// Learns what the reader cares about from what they open, entirely on-device.
/// Nothing is uploaded anywhere.
class InterestProfile {
  final Map<Category, double> weights = {};
  final Set<Category> muted = {};
  DateTime lastDecay = DateTime.now();

  void recordOpen(Story s) {
    weights[s.category] = (weights[s.category] ?? 0) + 1.0;
    _maybeDecay();
  }

  void _maybeDecay() {
    final days = DateTime.now().difference(lastDecay).inHours / 24.0;
    if (days < 1) return;
    final f = math.pow(0.85, days).toDouble();
    weights.updateAll((_, v) => v * f);
    lastDecay = DateTime.now();
  }

  /// 0..1 affinity for a category relative to the reader's favourite.
  double affinity(Category c) {
    if (weights.isEmpty) return 0;
    final maxW = weights.values.fold<double>(0, math.max);
    if (maxW <= 0) return 0;
    return (weights[c] ?? 0) / maxW;
  }

  String toJsonString() => jsonEncode({
        'w': weights.map((k, v) => MapEntry(k.name, v)),
        'm': muted.map((c) => c.name).toList(),
        't': lastDecay.toIso8601String(),
      });

  void loadJsonString(String s) {
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      (j['w'] as Map<String, dynamic>).forEach((k, v) {
        final c = Category.byName(k);
        if (c != null) weights[c] = (v as num).toDouble();
      });
      for (final m in (j['m'] as List)) {
        final c = Category.byName(m.toString());
        if (c != null) muted.add(c);
      }
      lastDecay = DateTime.tryParse(j['t'] as String) ?? DateTime.now();
    } catch (_) {}
  }
}

/// Builds the daily briefing: ranks stories by how widely they are covered,
/// how fresh they are and how much they match the reader, then re-ranks for
/// diversity so one topic (or one political side) cannot flood the feed.
class Curator {
  static List<Story> rank(List<Story> stories, InterestProfile profile,
      {int limit = 60, Set<String> localDomains = const {}}) {
    final now = DateTime.now().toUtc();
    for (final s in stories) {
      final sources = s.uniqueSources.length;
      final ageH = s.latest == null ? 24.0 : now.difference(s.latest!).inMinutes / 60.0;
      final fresh = math.exp(-math.max(0, ageH) / 18.0);
      final coverage = math.log(1 + sources) / math.ln2;
      final interest = profile.affinity(s.category);
      final dist = s.distribution;
      final balance = balanceOf(dist);
      var score = coverage * 1.6 + fresh * 3.0 + interest * 2.0 + balance * 0.6;
      if (s.hasLocal) score += 1.2;
      if (dist.blindspotFor != null) score += 0.4;
      if (profile.muted.contains(s.category)) score -= 100;
      s.score = score;
    }
    final pool = stories.where((s) => s.score > -50).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    // Diversity re-rank (MMR-style): each repeat of a category costs 25%.
    final picked = <Story>[];
    final catCount = <Category, int>{};
    while (picked.length < limit && pool.isNotEmpty) {
      var bestI = 0;
      var bestScore = double.negativeInfinity;
      for (var i = 0; i < pool.length && i < 80; i++) {
        final s = pool[i];
        final adj = s.score * math.pow(0.75, catCount[s.category] ?? 0);
        if (adj > bestScore) {
          bestScore = adj.toDouble();
          bestI = i;
        }
      }
      final s = pool.removeAt(bestI);
      picked.add(s);
      catCount[s.category] = (catCount[s.category] ?? 0) + 1;
    }
    return picked;
  }

  /// 1.0 = covered evenly by left, center and right; 0.0 = one side only.
  static double balanceOf(BiasDistribution d) {
    if (d.rated < 2) return 0.5;
    final maxShare = [Side.left, Side.center, Side.right].map(d.share).reduce(math.max);
    return (1 - (maxShare - 1 / 3) / (2 / 3)).clamp(0.0, 1.0);
  }
}
