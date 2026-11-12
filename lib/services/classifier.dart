import 'dart:convert';
import 'dart:math' as math;

import '../models/article.dart';
import '../models/category.dart';
import 'text.dart';

/// On-device topic classifier that runs comfortably on low-end phones.
///
/// It is a multinomial Naive Bayes model (microseconds per headline, a few
/// hundred KB of memory) that **trains itself every day for free**: Google News
/// topic feeds and topic-specialist outlets come pre-labelled, so each refresh
/// adds fresh labelled headlines. A hand-written keyword lexicon covers
/// day one and categories that have no labelled feed (AI, Space, Gaming…).
class TopicClassifier {
  TopicClassifier();

  final Map<Category, Map<String, int>> _counts = {};
  final Map<Category, int> _totals = {};
  final Map<Category, int> _docs = {};
  final Set<String> _vocab = {};
  int _allDocs = 0;

  /// Caps the model at roughly 0.5 MB of stored counts.
  static const maxVocab = 12000;

  static final Map<Category, List<String>> _lexicon = {
    Category.ai: ['artificial intelligence', ' ai ', 'openai', 'chatgpt', 'anthropic', 'claude', 'gemini', 'llm', 'machine learning', 'neural', 'deepmind', 'copilot', 'generative', 'deepfake', 'chatbot', 'nvidia'],
    Category.technology: ['apple', 'google', 'microsoft', 'iphone', 'android', 'samsung', 'software', 'app ', 'startup', 'chip', 'semiconductor', 'cyber', 'hack', 'smartphone', 'tech', 'internet', 'meta ', 'tiktok', 'data breach', 'gadget'],
    Category.science: ['scientist', 'study finds', 'research', 'physics', 'species', 'fossil', 'genome', 'quantum', 'researchers', 'archaeolog', 'biolog', 'chemist'],
    Category.space: ['nasa', 'spacex', 'rocket', 'orbit', 'astronaut', 'mars', 'moon', 'satellite', 'telescope', 'asteroid', 'galaxy', 'launch pad', 'esa '],
    Category.health: ['health', 'hospital', 'vaccine', 'cancer', 'disease', 'virus', 'outbreak', 'doctor', 'patients', 'medical', 'drug', 'mental health', 'covid', 'measles', 'obesity', 'nhs'],
    Category.sports: ['football', 'soccer', 'nba', 'nfl', 'mlb', 'nhl', 'cricket', 'tennis', 'golf', 'olympic', 'match', 'league', 'coach', 'championship', 'world cup', 'goal', 'tournament', 'rugby', 'f1 ', 'formula 1', 'striker', 'quarterback'],
    Category.entertainment: ['film', 'movie', 'box office', 'netflix', 'album', 'singer', 'actor', 'actress', 'celebrity', 'tv series', 'hollywood', 'oscar', 'grammy', 'concert', 'tour', 'streaming', 'premiere', 'k-pop'],
    Category.gaming: ['video game', 'gaming', 'playstation', 'xbox', 'nintendo', 'steam', 'esports', 'gamer', 'switch 2', 'game studio'],
    Category.business: ['company', 'ceo', 'shares', 'earnings', 'profit', 'revenue', 'merger', 'acquisition', 'layoffs', 'retail', 'industry', 'economy', 'gdp', 'inflation', 'tariff', 'trade deal', 'jobs report'],
    Category.finance: ['stock', 'stocks', 'nasdaq', 'dow ', 's&p', 'bitcoin', 'crypto', 'ethereum', 'bond', 'interest rate', 'fed ', 'central bank', 'investor', 'market rally'],
    Category.politics: ['election', 'vote', 'parliament', 'senate', 'congress', 'president', 'prime minister', 'minister', 'campaign', 'lawmakers', 'party', 'governor', 'mayor', 'policy', 'bill ', 'democrat', 'republican', 'labour', 'tory', 'coalition'],
    Category.world: ['war', 'ukraine', 'gaza', 'israel', 'russia', 'china', 'united nations', 'nato', 'ceasefire', 'refugee', 'diplomat', 'summit', 'sanction', 'invasion', 'missile'],
    Category.environment: ['climate', 'emission', 'carbon', 'wildfire', 'flood', 'drought', 'heatwave', 'hurricane', 'pollution', 'renewable', 'solar', 'wind farm', 'biodiversity', 'environment', 'storm', 'earthquake'],
    Category.crime: ['police', 'arrest', 'court', 'judge', 'trial', 'murder', 'shooting', 'charged', 'sentenced', 'lawsuit', 'prison', 'crime', 'stabbing', 'fraud', 'supreme court', 'jury'],
    Category.education: ['school', 'students', 'university', 'teacher', 'college', 'education', 'exam', 'campus', 'tuition', 'curriculum'],
    Category.autos: ['car ', 'cars', 'tesla', 'electric vehicle', ' ev ', 'automaker', 'toyota', 'ford', 'volkswagen', 'byd', 'recall', 'motor'],
    Category.travel: ['travel', 'airline', 'flight', 'airport', 'tourism', 'tourist', 'hotel', 'restaurant', 'recipe', 'food', 'chef', 'cruise'],
    Category.lifestyle: ['fashion', 'wellness', 'relationship', 'parenting', 'home decor', 'beauty', 'fitness', 'diet'],
    Category.energy: ['oil price', 'opec', 'natural gas', 'crude', 'refinery', 'pipeline', 'solar power', 'nuclear plant', 'power grid', 'electricity', 'lng'],
    Category.realEstate: ['housing market', 'mortgage', 'home prices', 'real estate', 'rent', 'landlord', 'property market', 'homebuyers'],
    Category.defense: ['military', 'army', 'navy', 'air force', 'pentagon', 'defense ministry', 'troops', 'drone strike', 'fighter jet', 'warship'],
    Category.labor: ['jobs report', 'unemployment', 'layoffs', 'union', 'strike', 'wages', 'workers', 'hiring', 'payrolls'],
    Category.weather: ['forecast', 'storm', 'hurricane', 'typhoon', 'heatwave', 'snow', 'tornado', 'rainfall', 'weather'],
    Category.local: ['council', 'city hall', 'county', 'township', 'neighborhood', 'neighbourhood', 'local residents', 'road closure', 'school board', 'community'],
  };

  /// Feed a labelled article into the model.
  void learn(Article a) {
    final label = a.hintCategory;
    if (label == null || label == Category.general) return;
    final toks = TextTokens.tokens('${a.title} ${a.snippet}').map(TextTokens.stem);
    final m = _counts.putIfAbsent(label, () => {});
    var added = 0;
    for (final t in toks) {
      if (!_vocab.contains(t)) {
        if (_vocab.length >= maxVocab) continue;
        _vocab.add(t);
      }
      m[t] = (m[t] ?? 0) + 1;
      added++;
    }
    _totals[label] = (_totals[label] ?? 0) + added;
    _docs[label] = (_docs[label] ?? 0) + 1;
    _allDocs++;
  }

  /// Returns the best category. Lexicon hits and the NB posterior are combined.
  Category classify(Article a, {Category fallback = Category.general}) {
    if (a.hintCategory != null) return a.hintCategory!;
    final text = ' ${a.title.toLowerCase()} ${a.snippet.toLowerCase()} ';

    final scores = <Category, double>{};
    _lexicon.forEach((cat, words) {
      var hits = 0;
      for (final w in words) {
        if (text.contains(w)) hits++;
      }
      if (hits > 0) scores[cat] = hits * 2.0;
    });

    if (_allDocs >= 50) {
      final toks = TextTokens.tokens(text).map(TextTokens.stem).toList();
      if (toks.isNotEmpty) {
        final v = _vocab.length + 1;
        final logp = <Category, double>{};
        for (final cat in _counts.keys) {
          final m = _counts[cat]!;
          final total = _totals[cat] ?? 0;
          var lp = math.log((_docs[cat] ?? 0) / _allDocs);
          for (final t in toks) {
            lp += math.log(((m[t] ?? 0) + 1) / (total + v));
          }
          logp[cat] = lp;
        }
        if (logp.isNotEmpty) {
          // Softmax to a probability, then add as evidence.
          final maxLp = logp.values.reduce(math.max);
          var sum = 0.0;
          final probs = <Category, double>{};
          logp.forEach((c, lp) {
            final e = math.exp(lp - maxLp);
            probs[c] = e;
            sum += e;
          });
          probs.forEach((c, p) {
            final prob = p / sum;
            if (prob > 0.35) scores[c] = (scores[c] ?? 0) + prob * 4;
          });
        }
      }
    }

    if (scores.isEmpty) return a.isLocal ? Category.local : fallback;
    var best = fallback;
    var bestScore = 0.0;
    scores.forEach((c, s) {
      if (s > bestScore) {
        best = c;
        bestScore = s;
      }
    });
    if (bestScore < 2.0) return a.isLocal ? Category.local : fallback;
    return best;
  }

  /// Decay old counts so the model tracks what is in the news now.
  void decay({double factor = 0.7}) {
    for (final cat in _counts.keys.toList()) {
      final m = _counts[cat]!;
      m.updateAll((_, v) => (v * factor).floor());
      m.removeWhere((_, v) => v == 0);
      _totals[cat] = m.values.fold(0, (a, b) => a + b);
      _docs[cat] = ((_docs[cat] ?? 0) * factor).floor();
    }
    _allDocs = _docs.values.fold(0, (a, b) => a + b);
    _vocab
      ..clear()
      ..addAll(_counts.values.expand((m) => m.keys));
  }

  String toJsonString() => jsonEncode({
        'c': _counts.map((k, v) => MapEntry(k.name, v)),
        'd': _docs.map((k, v) => MapEntry(k.name, v)),
      });

  void loadJsonString(String s) {
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      _counts.clear();
      _docs.clear();
      _totals.clear();
      _vocab.clear();
      (j['c'] as Map<String, dynamic>).forEach((k, v) {
        final cat = Category.byName(k);
        if (cat == null || v is! Map) return;
        final m = v.map((t, n) => MapEntry(t.toString(), (n as num).toInt()));
        _counts[cat] = m;
        _totals[cat] = m.values.fold(0, (a, b) => a + b);
        _vocab.addAll(m.keys);
      });
      (j['d'] as Map<String, dynamic>).forEach((k, v) {
        final cat = Category.byName(k);
        if (cat != null) _docs[cat] = (v as num).toInt();
      });
      _allDocs = _docs.values.fold(0, (a, b) => a + b);
    } catch (_) {
      // Corrupt model: start fresh.
    }
  }

  int get trainedDocs => _allDocs;
}
