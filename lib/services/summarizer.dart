import '../models/article.dart';
import '../models/bias.dart';
import '../models/story.dart';
import 'clustering.dart';
import 'text.dart';

class SummaryPoint {
  SummaryPoint(this.text, this.article);
  final String text;
  final Article article;
}

class StorySummary {
  StorySummary({required this.points, required this.framing, required this.outlets});

  /// Extracted key sentences (most corroborated across outlets).
  final List<SummaryPoint> points;

  /// One headline per side of the spectrum: how each side framed the story.
  final Map<Side?, Article> framing;
  final int outlets;

  bool get isEmpty => points.isEmpty && framing.length < 2;
}

/// Extractive TL;DR: never writes new text, so it can't invent facts.
///
/// 1. Split every outlet's summary text into sentences.
/// 2. Score each sentence by how much the *other* outlets' sentences agree
///    with it (centrality) — corroborated facts float up, one outlet's spin
///    sinks.
/// 3. Pick up to 3 that are not near-duplicates and come from different
///    outlets (maximal marginal relevance), keeping attribution.
/// Runs in a few milliseconds on any phone.
class Summarizer {
  static final _split = RegExp(r'(?<=[.!?])\s+(?=[A-Z0-9"“‘(])');

  static StorySummary summarize(Story story, {int maxPoints = 3}) {
    final sources = story.uniqueSources;
    final sentences = <(String, Article, Set<String>)>[];
    final titles = story.articles.map((a) => a.title.toLowerCase()).toSet();
    for (final a in story.articles) {
      if (a.snippet.isEmpty) continue;
      for (final raw in a.snippet.split(_split)) {
        final s = raw.trim();
        if (s.length < 40 || s.length > 320 || s.endsWith('...') || s.endsWith('…')) continue;
        if (titles.contains(s.toLowerCase())) continue;
        final toks = TextTokens.stemSet(s);
        if (toks.length < 4) continue;
        sentences.add((s, a, toks));
      }
    }

    // Centrality: agreement with sentences from *other* outlets.
    final scores = <double>[];
    for (var i = 0; i < sentences.length; i++) {
      var sc = 0.0;
      for (var j = 0; j < sentences.length; j++) {
        if (i == j || sentences[i].$2.domain == sentences[j].$2.domain) continue;
        sc += StoryClusterer.similarity(sentences[i].$3, sentences[j].$3);
      }
      // Slight preference for sentences that share words with the headline.
      sc += 0.5 * StoryClusterer.similarity(sentences[i].$3, TextTokens.stemSet(story.title));
      scores.add(sc);
    }

    final order = List.generate(sentences.length, (i) => i)..sort((a, b) => scores[b].compareTo(scores[a]));
    final picked = <int>[];
    final usedDomains = <String>{};
    for (final i in order) {
      if (picked.length >= maxPoints) break;
      final dup = picked.any((j) => StoryClusterer.similarity(sentences[i].$3, sentences[j].$3) > 0.45);
      if (dup) continue;
      if (usedDomains.contains(sentences[i].$2.domain) && sentences.length > maxPoints * 2) continue;
      picked.add(i);
      usedDomains.add(sentences[i].$2.domain);
    }

    final framing = <Side?, Article>{};
    for (final a in sources) {
      final side = a.source?.bias.side;
      framing.putIfAbsent(side, () => a);
    }

    return StorySummary(
      points: [for (final i in picked) SummaryPoint(sentences[i].$1, sentences[i].$2)],
      framing: framing,
      outlets: sources.length,
    );
  }
}
