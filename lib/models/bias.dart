import 'package:flutter/material.dart';

/// Political lean of a source. Ratings are community-maintained and
/// country-relative (a "centre" outlet in one country may differ from another).
enum Bias {
  farLeft('FL', 'Far Left', -3),
  left('L', 'Left', -2),
  leanLeft('LL', 'Lean Left', -1),
  center('C', 'Center', 0),
  leanRight('LR', 'Lean Right', 1),
  right('R', 'Right', 2),
  farRight('FR', 'Far Right', 3),
  unrated('U', 'Unrated', 0);

  const Bias(this.code, this.label, this.score);
  final String code;
  final String label;
  final int score;

  static Bias fromCode(String? code) {
    if (code == null) return Bias.unrated;
    for (final b in Bias.values) {
      if (b.code == code.toUpperCase()) return b;
    }
    return Bias.unrated;
  }

  Side? get side {
    switch (this) {
      case Bias.farLeft:
      case Bias.left:
      case Bias.leanLeft:
        return Side.left;
      case Bias.center:
        return Side.center;
      case Bias.leanRight:
      case Bias.right:
      case Bias.farRight:
        return Side.right;
      case Bias.unrated:
        return null;
    }
  }

  Color get color {
    switch (this) {
      case Bias.farLeft:
        return const Color(0xFF1E2F9E);
      case Bias.left:
        return const Color(0xFF3F5BEA);
      case Bias.leanLeft:
        return const Color(0xFF7D93FF);
      case Bias.center:
        return const Color(0xFFA08CFF);
      case Bias.leanRight:
        return const Color(0xFFFF8FA8);
      case Bias.right:
        return const Color(0xFFE0406A);
      case Bias.farRight:
        return const Color(0xFFA3123F);
      case Bias.unrated:
        return const Color(0xFFB9B3C9);
    }
  }
}

enum Side {
  left('Left', Color(0xFF3F5BEA)),
  center('Center', Color(0xFFA08CFF)),
  right('Right', Color(0xFFE0406A));

  const Side(this.label, this.color);
  final String label;
  final Color color;
}

enum Factuality {
  veryHigh('VH', 'Very high'),
  high('H', 'High'),
  mostlyFactual('MF', 'Mostly factual'),
  mixed('M', 'Mixed'),
  low('L', 'Low'),
  unknown('', 'Unknown');

  const Factuality(this.code, this.label);
  final String code;
  final String label;

  static Factuality fromCode(String? code) {
    if (code == null || code.isEmpty) return Factuality.unknown;
    for (final f in Factuality.values) {
      if (f.code == code) return f;
    }
    return Factuality.unknown;
  }
}

/// Maps Wikidata "political alignment" / "political ideology" labels to a [Bias].
Bias biasFromWikidataLabel(String label) {
  final l = label.toLowerCase();
  if (l.contains('far-left') || l.contains('far left') || l.contains('radical left') ||
      l.contains('communis') || l.contains('marxis')) {
    return Bias.farLeft;
  }
  if (l.contains('far-right') || l.contains('far right') || l.contains('radical right') ||
      l.contains('neo-fasc') || l.contains('white national')) {
    return Bias.farRight;
  }
  if (l.contains('centre-left') || l.contains('center-left') || l.contains('social democra') ||
      l.contains('social liberal')) {
    return Bias.leanLeft;
  }
  if (l.contains('centre-right') || l.contains('center-right') || l.contains('liberal conservat') ||
      l.contains('christian democra')) {
    return Bias.leanRight;
  }
  if (l.contains('left-wing') || l.contains('left wing') || l.contains('progressiv') ||
      l.contains('socialis') || l.contains('green politics')) {
    return Bias.left;
  }
  if (l.contains('right-wing') || l.contains('right wing') || l.contains('conservat') ||
      l.contains('nationalis')) {
    return Bias.right;
  }
  if (l.contains('libertarian')) return Bias.leanRight;
  if (l.contains('centris') || l == 'centre' || l == 'center') {
    return Bias.center;
  }
  return Bias.unrated;
}
