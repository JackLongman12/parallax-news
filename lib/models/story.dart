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

  /// The side that is under-covering this story, if it is a blindspot.
  Side? get blindspotFor {
    if (rated < 3) return null;
    if (share(Side.left) <= 0.15 && share(Side.right) >= 0.5) return Side.left;
    if (share(Side.right) <= 0.15 && share(Side.left) >= 0.5) return Side.right;
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
}
