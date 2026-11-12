import '../models/article.dart';
import '../models/category.dart';
import '../models/story.dart';
import 'text.dart';

/// Groups articles about the same event from different outlets into a [Story].
/// Greedy single pass with an inverted index: roughly O(n · k), fine for the
/// few hundred headlines a refresh produces even on low-end phones.
class StoryClusterer {
  static List<Story> cluster(List<Article> input) {
    // Drop exact duplicates (same URL, or same outlet + same headline).
    final seen = <String>{};
    final articles = <Article>[];
    for (final a in input) {
      final key1 = a.url;
      final key2 = '${a.domain}|${a.title.toLowerCase()}';
      if (seen.contains(key1) || seen.contains(key2)) continue;
      seen
        ..add(key1)
        ..add(key2);
      articles.add(a);
    }
    articles.sort((a, b) {
      final pa = a.published, pb = b.published;
      if (pa == null && pb == null) return 0;
      if (pa == null) return 1;
      if (pb == null) return -1;
      return pb.compareTo(pa);
    });

    final clusters = <_Cluster>[];
    final index = <String, List<int>>{};

    for (final a in articles) {
      final toks = TextTokens.stemSet(a.title);
      if (toks.isEmpty) continue;
      final candidates = <int, int>{};
      for (final t in toks) {
        for (final ci in index[t] ?? const <int>[]) {
          candidates[ci] = (candidates[ci] ?? 0) + 1;
        }
      }
      var best = -1;
      var bestSim = 0.0;
      candidates.forEach((ci, inter) {
        if (inter < 2) return;
        final c = clusters[ci];
        final sim = similarity(toks, c.tokens, inter);
        if (sim > bestSim) {
          bestSim = sim;
          best = ci;
        }
      });
      if (best >= 0 && bestSim >= 0.42) {
        final c = clusters[best];
        c.articles.add(a);
        // Keep the cluster signature focused: only the first few headlines.
        if (c.articles.length <= 4) {
          for (final t in toks) {
            if (c.tokens.add(t)) index.putIfAbsent(t, () => []).add(best);
          }
        }
      } else {
        final ci = clusters.length;
        clusters.add(_Cluster(a, toks));
        for (final t in toks) {
          index.putIfAbsent(t, () => []).add(ci);
        }
      }
    }

    return [
      for (final c in clusters)
        Story(
          id: c.articles.first.url.hashCode.toRadixString(36),
          articles: c.articles,
          category: Category.general,
        )
    ];
  }

  /// Blend of Jaccard and overlap coefficient — robust to short headlines.
  static double similarity(Set<String> a, Set<String> b, [int? inter]) {
    final i = inter ?? a.where(b.contains).length;
    if (i == 0) return 0;
    final union = a.length + b.length - i;
    final jaccard = i / union;
    final overlap = i / (a.length < b.length ? a.length : b.length);
    return 0.5 * jaccard + 0.5 * overlap;
  }
}

class _Cluster {
  _Cluster(Article first, Set<String> toks)
      : articles = [first],
        tokens = {...toks};
  final List<Article> articles;
  final Set<String> tokens;
}
