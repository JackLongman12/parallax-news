// Generates UI screenshots and promo images from the real widgets.
// Run:  flutter test screenshots/screenshot_test.dart --update-goldens
// Output: screenshots/out/*.png
//
// Sample stories use FICTIONAL outlets so no real publisher is shown with
// invented headlines. The Sources screen shows the real bundled catalog.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parallax_news/data/geo.dart';
import 'package:parallax_news/main.dart';
import 'package:parallax_news/models/article.dart';
import 'package:parallax_news/models/bias.dart';
import 'package:parallax_news/models/category.dart';
import 'package:parallax_news/models/place.dart';
import 'package:parallax_news/models/source.dart';
import 'package:parallax_news/models/story.dart';
import 'package:parallax_news/state/app_state.dart';
import 'package:parallax_news/ui/screens/feed_screens.dart';
import 'package:parallax_news/ui/screens/story_list.dart';
import 'package:parallax_news/ui/theme.dart';
import 'package:parallax_news/ui/screens/story_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _outlets = <(String, String, Bias, bool)>[
  ('harbordaily.example', 'Harbor Daily', Bias.left, false),
  ('metroledger.example', 'Metro Ledger', Bias.leanLeft, false),
  ('civicwire.example', 'Civic Wire', Bias.center, false),
  ('plainsgazette.example', 'Plains Gazette', Bias.center, true),
  ('northstarherald.example', 'Northstar Herald', Bias.leanRight, false),
  ('libertyreport.example', 'Liberty Report', Bias.right, false),
  ('oakvalleyvoice.example', 'Oak Valley Voice', Bias.unrated, true),
  ('techpulse.example', 'TechPulse', Bias.unrated, false),
  ('sciencenow.example', 'Science Now', Bias.center, false),
];

Article _a(String title, String domain, {int hoursAgo = 2}) {
  final o = _outlets.firstWhere((o) => o.$1 == domain);
  final a = Article(
    title: title,
    url: 'https://$domain/${title.hashCode.abs()}',
    sourceName: o.$2,
    domain: domain,
    published: DateTime.now().toUtc().subtract(Duration(hours: hoursAgo)),
    provider: 'rss',
    isLocal: o.$4,
    snippet: 'The package funds roads, bridges and broadband over five years, with a final vote expected next week.',
  );
  a.source = SourceInfo(
      domain: domain, name: o.$2, bias: o.$3, origin: RatingOrigin.curated, isLocal: o.$4, factuality: Factuality.high);
  return a;
}

Story _s(String id, Category c, List<Article> arts) => Story(id: id, category: c, articles: arts);

List<Story> sampleStories() => [
      _s('1', Category.politics, [
        _a('Lawmakers reach late-night deal on national infrastructure budget', 'civicwire.example'),
        _a('Infrastructure budget deal struck after marathon session', 'harbordaily.example'),
        _a('Budget deal: what the infrastructure package means for you', 'metroledger.example'),
        _a('Infrastructure deal passes with bipartisan support', 'northstarherald.example'),
        _a('Critics warn infrastructure deal adds to the deficit', 'libertyreport.example'),
      ]),
      _s('2', Category.local, [
        _a('Oak Valley council approves new riverside park and bike lanes', 'oakvalleyvoice.example', hoursAgo: 1),
        _a('Riverside park plan gets green light in Oak Valley', 'plainsgazette.example', hoursAgo: 3),
      ]),
      _s('3', Category.ai, [
        _a('New open-weight AI model runs on a mid-range phone', 'techpulse.example', hoursAgo: 4),
        _a('Researchers shrink language model to fit on low-end devices', 'sciencenow.example', hoursAgo: 5),
        _a('On-device AI model challenges cloud assistants', 'metroledger.example', hoursAgo: 6),
      ]),
      _s('4', Category.crime, [
        _a('Report finds rise in border crossings at northern checkpoints', 'libertyreport.example', hoursAgo: 3),
        _a('Border crossings climb, new figures show', 'northstarherald.example', hoursAgo: 4),
        _a('Northern checkpoints see uptick in crossings', 'civicwire.example', hoursAgo: 5),
      ]),
      _s('5', Category.science, [
        _a('Astronomers spot water vapour on a nearby rocky exoplanet', 'sciencenow.example', hoursAgo: 7),
        _a('Water detected in atmosphere of nearby world', 'harbordaily.example', hoursAgo: 8),
        _a('Exoplanet discovery raises hopes in search for life', 'civicwire.example', hoursAgo: 9),
      ]),
      _s('6', Category.environment, [
        _a('Heatwave pushes regional power grid to record demand', 'metroledger.example', hoursAgo: 2),
        _a('Grid operators urge conservation as temperatures soar', 'plainsgazette.example', hoursAgo: 3),
        _a('Record heat strains power supply across the region', 'harbordaily.example', hoursAgo: 4),
      ]),
    ];

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  final roboto = FontLoader('Roboto');
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (RegExp(r'^Roboto-[A-Za-z]+\.ttf$').hasMatch(name)) {
      roboto.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
    }
    if (name.startsWith('MaterialIcons')) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
      await icons.load();
    }
  }
  await roboto.load();
}

Widget _app(AppState state, Widget home, {Brightness b = Brightness.light}) => ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: Brand.theme(b),
        home: home,
      ),
    );

Widget _feedShell(int tab, List<Story> stories, {bool blind = false}) => HomeShell(
      initialTab: tab,
      pageOverride: (i) {
        if (i == 0) {
          return StoryList(
            loader: (_) async => stories,
            header: const BriefingHeader(),
          );
        }
        if (i == 3) {
          return StoryList(
            loader: (_) async => stories,
            filter: (s) => s.distribution.blindspotFor != null,
            header: const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Stories mostly ignored by one side of the spectrum.'),
            ),
          );
        }
        return null;
      },
    );

/// Promo frame: fixed-height caption area + fixed-size phone, so every
/// promo image shows the phone at exactly the same size and position.
Widget _promo(String headline, String sub, Widget screen, Color bg) => Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: bg,
        child: Column(children: [
          SizedBox(
            height: 250,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(36, 56, 36, 0),
              child: Column(children: [
                Text(headline,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(fontFamily: 'Roboto', fontSize: 40, height: 1.1, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 14),
                Text(sub,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(fontFamily: 'Roboto', fontSize: 18, height: 1.3, color: Color(0xE6FFFFFF))),
              ]),
            ),
          ),
          SizedBox(
            width: 440,
            height: 830,
            child: Container(
              decoration: const BoxDecoration(
                color: Brand.black,
                borderRadius: BorderRadius.vertical(top: Radius.circular(44)),
              ),
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                child: FittedBox(
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                  child: SizedBox(width: 412, height: 830, child: screen),
                ),
              ),
            ),
          ),
        ]),
      ),
    );

Widget _feature() => Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: Brand.black,
        padding: const EdgeInsets.all(48),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Parallax News',
                  style: TextStyle(fontFamily: 'Roboto', fontSize: 64, fontWeight: FontWeight.w900, color: Brand.purple)),
              const SizedBox(height: 10),
              const Text('Every side of every story —\nfrom the world to your street.',
                  style: TextStyle(fontFamily: 'Roboto', fontSize: 28, height: 1.25, color: Color(0xE6FFFFFF))),
              const SizedBox(height: 28),
              Container(width: 120, height: 8, decoration: BoxDecoration(color: Brand.purple, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 10),
              const Text('Open source · No account · No tracking · Free',
                  style: TextStyle(fontFamily: 'Roboto', fontSize: 20, color: Color(0xCCFFFFFF))),
            ]),
          ),
        ]),
      ),
    );

void main() {
  late AppState state;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  Future<void> setup(WidgetTester tester, Size size, {double dpr = 2.625}) async {
    SharedPreferences.setMockInitialValues({
      'autoUpdate': false,
      'topics': ['technology', 'ai', 'science', 'sports'],
      'followed': '[{"id":"cc:US","name":"United States","level":"country","cc":"US","cont":"NA","parents":["North America"]},'
          '{"id":"wd:Q1","name":"Oak Valley","level":"city","cc":"US","parents":["Plains County","United States"]}]',
    });
    state = (await tester.runAsync(AppState.create))!;
    tester.view.physicalSize = size * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  const phone = Size(412, 892);
  final stories = sampleStories();

  testWidgets('feed', (tester) async {
    await setup(tester, phone);
    await tester.pumpWidget(_app(state, _feedShell(0, stories)));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/01_for_you.png'));
  });

  testWidgets('feed dark', (tester) async {
    await setup(tester, phone);
    await tester.pumpWidget(_app(state, _feedShell(0, stories), b: Brightness.dark));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/02_for_you_dark.png'));
  });

  testWidgets('story', (tester) async {
    await setup(tester, phone);
    await tester.pumpWidget(_app(state, StoryScreen(story: stories.first)));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/03_story_coverage.png'));
  });

  testWidgets('blindspot', (tester) async {
    await setup(tester, phone);
    await tester.pumpWidget(_app(state, _feedShell(3, stories)));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/04_blindspot.png'));
  });

  testWidgets('explore', (tester) async {
    await setup(tester, phone);
    await tester.pumpWidget(_app(state, const HomeShell(initialTab: 2, pageOverride: _noOverride)));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/05_explore.png'));
  });

  testWidgets('sources', (tester) async {
    await setup(tester, phone);
    await tester.pumpWidget(_app(state, const HomeShell(initialTab: 4, pageOverride: _noOverride)));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/06_sources.png'));
  });

  const promoSize = Size(540, 1080);
  final promos = <(String, String, String, Widget Function(), Color)>[
    ('promo_1', 'See every side\nof every story', 'Coverage from left, center and right — side by side.',
        () => _feedShell(0, stories), Brand.purple),
    ('promo_2', 'Know who is\ntelling it', 'Bias, factuality, ownership and state affiliation for every outlet.',
        () => StoryScreen(story: stories.first), Brand.black),
    ('promo_3', 'From the world\nto your street', 'Continents, countries, states, cities and neighbourhood papers.',
        () => const HomeShell(initialTab: 2, pageOverride: _noOverride), Brand.purple),
    ('promo_4', 'Break out of\nyour bubble', 'Blindspots reveal stories one side is ignoring.',
        () => _feedShell(3, stories), Brand.black),
  ];

  for (final p in promos) {
    testWidgets(p.$1, (tester) async {
      await setup(tester, promoSize, dpr: 2);
      await tester.pumpWidget(_promo(p.$2, p.$3, _app(state, p.$4()), p.$5));
      await settle(tester);
      await expectLater(find.byType(Container).first, matchesGoldenFile('out/${p.$1}.png'));
    });
  }

  testWidgets('feature graphic', (tester) async {
    await setup(tester, const Size(1024, 500), dpr: 1);
    await tester.pumpWidget(_feature());
    await settle(tester);
    await expectLater(find.byType(Container).first, matchesGoldenFile('out/feature_graphic.png'));
  });

  // Silence unused-import lint for geo (kept for future country shots).
  test('geo loaded', () => expect(countries, isNotEmpty));
  test('place type', () => expect(Place.world.level, PlaceLevel.world));
}

Widget? _noOverride(int _) => null;
