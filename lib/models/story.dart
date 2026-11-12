import 'article.dart';
import 'bias.dart';
import 'category.dart';

class BiasDistribution {
  BiasDistribution(this.left, this.center, this.right, this.unrated);
  final int left;
  final int center;
  final int right;
  final int unrated;

  int get rated => left + center + right;
  int get total => rated + unrated;

  double share(Side s) {
    if (rated == 0) return 0;
    switch (s) {
      case Side.left:
        return left / rated;
      case Side.center:
        return center / rated;
      case Side.right:
        return right / rated;
    }
  }

  /// Share of outlets that have a rating at all.
  double get ratedShare => total == 0 ? 0 : rated / total;

  /// Only claim a left/center/right split when enough of the coverage is
  /// actually rated. Otherwise the story is shown as "Lean unknown" so a
  /// single rated outlet can't paint the whole story with a political colour.
  /// With 3+ rated outlets the split is meaningful however many unrated
  /// outlets also cover it (big stories pull in many small unrated sites).
  bool get isReliable => rated >= 3 || (rated >= 2 && ratedShare >= 0.5);

  /// The side that is under-covering this story, if it is a blindspot:
  /// 3+ rated outlets (and at least a quarter of coverage rated, or 6+
  /// rated), with one side at <=20% while the other has >=60%.
  Side? get blindspotFor {
    if (rated < 3 || (ratedShare < 0.25 && rated < 6)) return null;
    if (share(Side.left) <= 0.2 && share(Side.right) >= 0.6) return Side.left;
    if (share(Side.right) <= 0.2 && share(Side.left) >= 0.6) return Side.right;
    return null;
  }

  /// Left and right cover it about equally (3+ outlets each, each 30%+ of
  /// rated coverage, the smaller side at least 70% the size of the bigger):
  /// the same event from both sides, so the framing can be compared.
  bool get divergent {
    if (left < 3 || right < 3) return false;
    if (share(Side.left) < 0.3 || share(Side.right) < 0.3) return false;
    final lo = left < right ? left : right, hi = left < right ? right : left;
    return lo / hi >= 0.7;
  }

  /// Weaker signal than a blindspot: reliably rated coverage where one side
  /// supplies 70%+ of it. Shown as "mostly one side", never as a blindspot.
  Side? get skewedTo {
    if (!isReliable) return null;
    for (final s in Side.values) {
      if (s != Side.center && share(s) >= 0.7) return s;
    }
    return null;
  }
}

class Story {
  Story({required this.id, required this.articles, required this.category});

  final String id;
  final List<Article> articles;
  Category category;
  double score = 0;

  Article get lead {
    // Prefer a center-rated source for the headline, else the first article.
    for (final a in articles) {
      if (a.source?.bias == Bias.center) return a;
    }
    return articles.first;
  }

  String get title => lead.title;

  String? get imageUrl {
    for (final a in articles) {
      if (a.imageUrl != null) return a.imageUrl;
    }
    return null;
  }

  DateTime? get latest {
    DateTime? best;
    for (final a in articles) {
      final p = a.published;
      if (p != null && (best == null || p.isAfter(best))) best = p;
    }
    return best;
  }

  /// One entry per distinct outlet.
  List<Article> get uniqueSources {
    final seen = <String>{};
    final out = <Article>[];
    for (final a in articles) {
      if (seen.add(a.domain)) out.add(a);
    }
    return out;
  }

  bool get hasLocal => articles.any((a) => a.isLocal);

  BiasDistribution get distribution {
    var l = 0, c = 0, r = 0, u = 0;
    for (final a in uniqueSources) {
      final side = a.source?.bias.side;
      if (side == Side.left) {
        l++;
      } else if (side == Side.center) {
        c++;
      } else if (side == Side.right) {
        r++;
      } else {
        u++;
      }
    }
    return BiasDistribution(l, c, r, u);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'c': category.name,
        'a': articles.take(12).map((a) => a.toJson()).toList(),
      };

  static Story? fromJson(Map<String, dynamic> j) {
    try {
      final arts = (j['a'] as List).whereType<Map<String, dynamic>>().map(Article.fromJson).whereType<Article>().toList();
      if (arts.isEmpty) return null;
      return Story(id: j['id'] as String, articles: arts, category: Category.byName(j['c'] as String?) ?? Category.general);
    } catch (_) {
      return null;
    }
  }
}
