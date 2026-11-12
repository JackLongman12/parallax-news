import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parallax_news/models/article.dart';
import 'package:parallax_news/models/bias.dart';
import 'package:parallax_news/models/category.dart';
import 'package:parallax_news/models/source.dart';
import 'package:parallax_news/models/story.dart';
import 'package:parallax_news/services/bias_service.dart';
import 'package:parallax_news/services/classifier.dart';
import 'package:parallax_news/services/clustering.dart';
import 'package:parallax_news/services/country_detect.dart';
import 'package:parallax_news/services/cover_images.dart';
import 'package:parallax_news/services/markets.dart';
import 'package:parallax_news/services/curator.dart';
import 'package:parallax_news/services/feed_parser.dart';
import 'package:parallax_news/services/net.dart';
import 'package:parallax_news/services/places.dart';
import 'package:parallax_news/services/provider_health.dart';
import 'package:parallax_news/services/summarizer.dart';

Article art(String title, String domain, {Bias bias = Bias.unrated, Category? hint}) {
  final a = Article(
    title: title,
    url: 'https://$domain/${title.hashCode}',
    sourceName: domain,
    domain: domain,
    published: DateTime.now().toUtc(),
    provider: 'test',
    hintCategory: hint,
  );
  a.source = SourceInfo(domain: domain, name: domain, bias: bias);
  return a;
}

void main() {
  group('FeedParser', () {
    test('parses Google News RSS, strips publisher suffix, reads <source>', () {
      const xml = '''<?xml version="1.0"?><rss><channel>
<item><title>City council approves new park - Springfield Gazette</title>
<link>https://news.google.com/rss/articles/abc</link>
<pubDate>Thu, 12 Nov 2026 10:00:00 GMT</pubDate>
<source url="https://www.springfieldgazette.com">Springfield Gazette</source></item>
</channel></rss>''';
      final items = FeedParser.parse(xml, provider: 'google');
      expect(items, hasLength(1));
      expect(items.first.title, 'City council approves new park');
      expect(items.first.domain, 'springfieldgazette.com');
      expect(items.first.published, DateTime.utc(2026, 11, 12, 10));
    });

    test('parses Atom and rejects javascript: links', () {
      const xml = '''<feed xmlns="http://www.w3.org/2005/Atom">
<entry><title>Good</title><link href="https://ex.com/a"/><updated>2026-11-12T09:00:00Z</updated></entry>
<entry><title>Evil</title><link href="javascript:alert(1)"/></entry>
</feed>''';
      final items = FeedParser.parse(xml, provider: 'rss', sourceName: 'Ex', sourceDomain: 'ex.com');
      expect(items.map((a) => a.title), ['Good']);
    });

    test('cleanText strips tags including entity-escaped ones', () {
      expect(FeedParser.cleanText('<p>Hi &lt;script&gt;x&lt;/script&gt; &amp; bye</p>'), 'Hi x & bye');
    });

    test('malformed XML does not throw', () {
      expect(FeedParser.parse('<rss><item><title>x', provider: 'rss'), isEmpty);
    });

    test('RFC822 with offset', () {
      expect(FeedParser.parseFeedDate('Wed, 11 Nov 2026 08:30:00 +0200'), DateTime.utc(2026, 11, 11, 6, 30));
    });
  });

  group('Clustering', () {
    test('groups the same event across outlets', () {
      final stories = StoryClusterer.cluster([
        art('Earthquake of magnitude 6.1 strikes central Chile', 'a.com'),
        art('Magnitude 6.1 earthquake strikes central Chile, no tsunami', 'b.com'),
        art('Chile earthquake: magnitude 6.1 quake strikes central region', 'c.com'),
        art('Apple unveils new MacBook Pro with M6 chip', 'd.com'),
      ]);
      expect(stories, hasLength(2));
      expect(stories.map((s) => s.articles.length).toList()..sort(), [1, 3]);
    });
  });

  group('Bias', () {
    test('blindspot detection', () {
      final s = Story(id: '1', category: Category.general, articles: [
        art('x', 'r1.com', bias: Bias.right),
        art('x', 'r2.com', bias: Bias.right),
        art('x', 'r3.com', bias: Bias.leanRight),
        art('x', 'c1.com', bias: Bias.center),
      ]);
      expect(s.distribution.blindspotFor, Side.left);
      expect(Curator.balanceOf(s.distribution), lessThan(0.5));
    });

    test('mostly-unrated coverage is "lean unknown", never a blindspot', () {
      final s = Story(id: '2', category: Category.general, articles: [
        art('x', 'c1.com', bias: Bias.center),
        art('x', 'u1.com'),
        art('x', 'u2.com'),
      ]);
      expect(s.distribution.isReliable, isFalse);
      expect(s.distribution.blindspotFor, isNull);
      final s2 = Story(id: '3', category: Category.general, articles: [
        art('x', 'r1.com', bias: Bias.right),
        art('x', 'r2.com', bias: Bias.right),
        art('x', 'r3.com', bias: Bias.right),
        art('x', 'u1.com'),
        art('x', 'u2.com'),
        art('x', 'u3.com'),
      ]);
      // 3 rated of 6 = 50% rated, all right-leaning: a (minimal) blindspot.
      expect(s2.distribution.isReliable, isTrue);
      expect(s2.distribution.blindspotFor, Side.left);
      expect(s2.distribution.skewedTo, Side.right);
    });

    test('wikidata labels map to bias', () {
      expect(biasFromWikidataLabel('centre-left'), Bias.leanLeft);
      expect(biasFromWikidataLabel('right-wing populism'), Bias.right);
      expect(biasFromWikidataLabel('far-right politics'), Bias.farRight);
      expect(biasFromWikidataLabel('conservatism'), Bias.right);
    });

    test('bundled catalog is valid and has no duplicate domains', () {
      final json = jsonDecode(File('assets/sources.json').readAsStringSync()) as Map<String, dynamic>;
      final list = (json['sources'] as List).cast<Map<String, dynamic>>();
      final domains = <String>{};
      for (final e in list) {
        expect(BiasService.isValidCatalogEntry(e), isTrue, reason: 'invalid entry ${e['d']}');
        final s = SourceInfo.fromCatalog(e);
        expect(domains.add(s.domain), isTrue, reason: 'duplicate ${s.domain}');
        if (s.feedUrl != null) expect(s.feedUrl!.startsWith('https://'), isTrue, reason: s.domain);
      }
      expect(list.length, greaterThan(250));
    });
  });

  group('Classifier', () {
    test('lexicon works before any training', () {
      final c = TopicClassifier();
      expect(c.classify(art('OpenAI releases new ChatGPT model', 'x.com')), Category.ai);
      expect(c.classify(art('Lakers beat Celtics in NBA thriller', 'x.com')), Category.sports);
    });

    test('learns from labelled feeds and round-trips', () {
      final c = TopicClassifier();
      for (var i = 0; i < 60; i++) {
        c.learn(art('Quidditch league final $i draws record crowd', 'x.com', hint: Category.sports));
        c.learn(art('Parliament debates widget tax bill $i', 'x.com', hint: Category.politics));
      }
      final c2 = TopicClassifier()..loadJsonString(c.toJsonString());
      expect(c2.trainedDocs, 120);
      expect(c2.classify(art('Quidditch final tonight', 'x.com')), Category.sports);
    });
  });

  group('Personalisation', () {
    Story story(String id, String title, Category c, String domain) =>
        Story(id: id, category: c, articles: [art(title, domain)]);

    test('opens and dwell raise, skips and bounces lower', () {
      final p = InterestProfile();
      final ai = story('a', 'New AI chip doubles inference speed', Category.ai, 'tech.com');
      final golf = story('g', 'Golf open final round delayed by rain', Category.sports, 'sport.com');
      for (var i = 0; i < 5; i++) {
        p.recordOpen(ai);
        p.recordDwell(ai, const Duration(seconds: 60));
        p.recordDwell(golf, const Duration(seconds: 1)); // bounced
      }
      expect(p.score(ai), greaterThan(p.score(golf)));
      // Keyword learning generalises to a new story about the same thing.
      final ai2 = story('a2', 'AI chip startup raises funding', Category.business, 'other.com');
      final golf2 = story('g2', 'Golf star wins playoff', Category.business, 'other.com');
      expect(p.score(ai2), greaterThan(p.score(golf2)));
    });

    test('profile round-trips through JSON', () {
      final p = InterestProfile()..moreLikeThis(story('a', 'Quantum computing breakthrough', Category.science, 'x.com'));
      p.hiddenSources.add('spam.com');
      final q = InterestProfile()..loadJsonString(p.toJsonString());
      expect(q.signals, 1);
      expect(q.hiddenSources, contains('spam.com'));
      expect(q.keywords.keys, contains('quantum'));
    });
  });

  group('Auto source routing', () {
    final h = ProviderHealth.instance;
    setUp(h.reset);

    test('rate limit pauses a provider immediately', () async {
      await expectLater(h.run('bing', () async => throw NetException('HTTP 429', status: 429)), throwsA(isA<NetException>()));
      expect(h.available('bing'), isFalse);
      await expectLater(h.run('bing', () async => 1), throwsA(isA<ProviderUnavailable>()));
      expect(h.stats['bing']!.status, contains('rate limited'));
    });

    test('three failures in a row pause; a success resets the streak', () async {
      for (var i = 0; i < 2; i++) {
        await expectLater(h.run('google', () async => throw NetException('boom')), throwsA(anything));
      }
      expect(h.available('google'), isTrue);
      expect(await h.run('google', () async => 42), 42);
      expect(h.stats['google']!.consecutiveFailures, 0);
      for (var i = 0; i < 3; i++) {
        await expectLater(h.run('google', () async => throw NetException('boom')), throwsA(anything));
      }
      expect(h.available('google'), isFalse);
    });
  });

  group('TL;DR', () {
    Article withSnippet(String title, String domain, String snippet, Bias bias) {
      final a = Article(
          title: title, url: 'https://$domain/x', sourceName: domain, domain: domain, provider: 'rss', snippet: snippet);
      a.source = SourceInfo(domain: domain, name: domain, bias: bias);
      return a;
    }

    test('picks corroborated sentences, attributed, never invented', () {
      final s = Story(id: 's', category: Category.politics, articles: [
        withSnippet('Senate passes budget', 'a.com',
            'The Senate passed the budget bill by 52 votes to 48 on Tuesday. Critics called it reckless spending.', Bias.left),
        withSnippet('Budget clears Senate', 'b.com',
            'The budget bill passed the Senate 52 to 48 on Tuesday night. It now goes to the House for a vote.', Bias.right),
        withSnippet('Budget vote', 'c.com',
            'Lawmakers in the Senate passed the budget bill on Tuesday, 52-48. Markets barely reacted to the news today.', Bias.center),
      ]);
      final sum = Summarizer.summarize(s);
      expect(sum.points, isNotEmpty);
      // The corroborated fact (52-48 vote) ranks first.
      expect(sum.points.first.text, contains('52'));
      // Every point is verbatim text from one outlet.
      for (final p in sum.points) {
        expect(p.article.snippet, contains(p.text));
      }
      expect(sum.framing.keys, containsAll([Side.left, Side.center, Side.right]));
    });
  });

  group('Home country & markets', () {
    test('country from network trace and locale', () {
      expect(CountryDetector.parseTrace('fl=1\nip=1.2.3.4\nloc=DE\ntls=TLSv1.3\n'), 'DE');
      expect(CountryDetector.parseTrace('loc=XX\n'), isNull);
      expect(CountryDetector.parseTrace('garbage'), isNull);
      expect(CountryDetector.fromLocale('en_GB'), 'GB');
      expect(CountryDetector.fromLocale('pt-BR'), 'BR');
      expect(CountryDetector.fromLocale('fr_CA.UTF-8'), 'CA');
      expect(CountryDetector.fromLocale('en'), isNull);
    });

    test('Yahoo chart JSON parses to a quote with % change', () {
      final q = Markets.parseChart('S&P 500', {
        'chart': {
          'result': [
            {'meta': {'regularMarketPrice': 5050.0, 'chartPreviousClose': 5000.0}}
          ]
        }
      })!;
      expect(q.changePct, closeTo(1.0, 1e-9));
      expect(Markets.parseChart('x', {'chart': {'result': []}}), isNull);
      expect(Markets.parseChart('x', 'nonsense'), isNull);
    });
  });

  group('Unique covers', () {
    test('generic logos are rejected; image queries go specific to broad', () {
      expect(CoverImages.looksGeneric('https://site.com/static/logo-share.png'), isTrue);
      expect(CoverImages.looksGeneric('https://site.com/img/2026/11/flood-scene.jpg'), isFalse);
      final s = Story(id: 'q', category: Category.environment, articles: [art('Floods hit Valencia as storm Dana returns', 'x.com')]);
      final qs = CoverImages.imageQueries(s);
      expect(qs.first, contains('Valencia'));
      expect(qs.last, Category.environment.label);
      expect(qs.toSet().length, qs.length);
    });
  });

  group('Snapshot', () {
    test('stories round-trip through JSON', () {
      final s = Story(id: 'x1', category: Category.ai, articles: [art('Chip news', 'a.com', hint: Category.ai)]);
      final back = Story.fromJson(s.toJson())!;
      expect(back.id, 'x1');
      expect(back.category, Category.ai);
      expect(back.articles.single.title, 'Chip news');
      expect(Story.fromJson({'id': 1}), isNull); // malformed data is ignored
    });
  });

  group('Cover images', () {
    test('Bing thumbnails are upscaled and flagged low-res', () {
      final up = FeedParser.upscaleImage('https://www.bing.com/th?id=OVFT.abc&pid=News');
      expect(up, contains('w=1200'));
      expect(up, isNot(contains('pid=')));
      expect(CoverImages.isLowRes('https://www.bing.com/th?id=OVFT.abc'), isTrue);
      expect(CoverImages.isLowRes('https://cdn.site.com/big.jpg'), isFalse);
    });

    test('image keywords prefer proper nouns', () {
      final s = Story(id: 'k', category: Category.space, articles: [art('NASA delays Artemis launch over heat shield worries', 'x.com')]);
      final k = CoverImages.keywordsFor(s);
      expect(k, contains('NASA'));
      expect(k, contains('Artemis'));
    });

    test('extracts og:image and rejects private/http hosts', () {
      final base = Uri.parse('https://news.example.com/a/b');
      expect(
          CoverImages.extractMetaImage(
              '<head><meta property="og:image" content="https://cdn.example.com/p.jpg?a=1&amp;b=2"></head>', base),
          'https://cdn.example.com/p.jpg?a=1&b=2');
      expect(CoverImages.extractMetaImage('<meta content="/img/x.png" name="twitter:image">', base),
          'https://news.example.com/img/x.png');
      expect(CoverImages.extractMetaImage('<meta property="og:image" content="https://10.0.0.1/x.jpg">', base), isNull);
      expect(CoverImages.extractMetaImage('<p>no meta</p>', base), isNull);
    });
  });

  group('Security helpers', () {
    test('only http(s) URLs are openable', () {
      expect(isSafeWebUrl('https://ok.com/a'), isTrue);
      expect(isSafeWebUrl('javascript:alert(1)'), isFalse);
      expect(isSafeWebUrl('intent://x#Intent;end'), isFalse);
      expect(isSafeWebUrl('file:///etc/passwd'), isFalse);
    });

    test('SPARQL ids are validated', () {
      expect(PlaceService.isQid('Q1490'), isTrue);
      expect(PlaceService.isQid('Q1 } DROP'), isFalse);
      expect(PlaceService.isQid(null), isFalse);
    });

    test('private hosts are blocked', () {
      expect(isPublicHost('news.google.com'), isTrue);
      expect(isPublicHost('8.8.8.8'), isTrue);
      for (final h in ['localhost', '127.0.0.1', '10.0.0.5', '192.168.1.1', '172.20.0.1', '169.254.169.254', '[::1]', 'printer.local']) {
        expect(isPublicHost(h), isFalse, reason: h);
      }
    });

    test('IPv4-mapped IPv6 private addresses are blocked', () {
      expect(isPublicHost('::ffff:192.168.1.1'), isFalse);
      expect(isPublicHost('fd12::1'), isFalse);
    });

    test('bidi overrides and invisible chars are stripped from text', () {
      expect(FeedParser.cleanText('Safe‮txt.exe​ title'), 'Safetxt.exe title');
    });

    test('feed images must be public https', () {
      const xml = '''<rss><channel>
<item><title>A</title><link>https://ex.com/a</link><enclosure url="https://192.168.0.1/x.jpg" type="image/jpeg"/></item>
<item><title>B</title><link>https://ex.com/b</link><enclosure url="http://cdn.ex.com/x.jpg" type="image/jpeg"/></item>
<item><title>C</title><link>https://ex.com/c</link><enclosure url="https://cdn.ex.com/x.jpg" type="image/jpeg"/></item>
</channel></rss>''';
      final items = FeedParser.parse(xml, provider: 'rss', sourceName: 'Ex', sourceDomain: 'ex.com');
      expect(items.map((a) => a.imageUrl).toList(), [null, null, 'https://cdn.ex.com/x.jpg']);
    });

    test('catalog entries are validated', () {
      expect(BiasService.isValidCatalogEntry({'d': 'bbc.co.uk', 'n': 'BBC'}), isTrue);
      expect(BiasService.isValidCatalogEntry({'d': 'evil.com/@x', 'n': 'X'}), isFalse);
      expect(BiasService.isValidCatalogEntry({'d': 'localhost', 'n': 'X'}), isFalse);
      expect(BiasService.isValidCatalogEntry({'d': '10.0.0.1', 'n': 'X'}), isFalse);
      expect(BiasService.isValidCatalogEntry({'d': 'ok.com', 'n': 'X', 'rss': 'http://ok.com/feed'}), isFalse);
      expect(BiasService.isValidCatalogEntry({'d': 'ok.com', 'n': 'X', 'rss': 'https://ok.com/feed'}), isTrue);
    });

    test('domainOf strips www', () {
      expect(domainOf('https://www.bbc.co.uk/news'), 'bbc.co.uk');
    });
  });
}
