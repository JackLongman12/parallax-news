import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/updater.dart';
import '../theme.dart';

/// Where this build is distributed: 'github' (self-updating APK), 'play' or
/// 'fdroid' (the store updates the app, so the built-in updater is off).
const channel = String.fromEnvironment('CHANNEL', defaultValue: 'github');
bool get selfUpdates => channel == 'github';

const repoUrl = 'https://github.com/JackLongman12/parallax-news';

/// Short line shown under market data.
const marketDisclaimer = 'Not financial advice. Prices may be delayed. Data: Yahoo Finance, CNBC, Finnhub and '
    'StockTwits.';

class InfoSection {
  const InfoSection(this.heading, this.body);
  final String heading;
  final String body;
}

class InfoPage extends StatelessWidget {
  const InfoPage({super.key, required this.title, required this.intro, required this.sections});
  final String title;
  final String intro;
  final List<InfoSection> sections;

  static void open(BuildContext context, InfoPage page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        Text(intro, style: t.bodyLarge),
        for (final s in sections) ...[
          const SizedBox(height: 20),
          Text(s.heading, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: Brand.purple)),
          const SizedBox(height: 6),
          Text(s.body, style: t.bodyMedium?.copyWith(height: 1.45)),
        ],
      ]),
    );
  }
}

const privacyPage = InfoPage(
  title: 'Privacy policy',
  intro: 'Parallax News has no accounts, no ads, no analytics and no tracking. We do not run a server that '
      'collects anything about you. Last updated November 2026.',
  sections: [
    InfoSection('What stays on your phone',
        'Your followed places and topics, watchlist, reading history, thumbs up/down, and the interest model '
            'the app learns from what you open. None of it is uploaded. Uninstalling the app or using '
            '"Reset" in Settings deletes it.'),
    InfoSection('Services the app contacts',
        'To show news and prices the app downloads public data directly from these services. Like any website, '
            'they see your IP address and the request (for example, a search term or a ticker), under their own '
            'privacy policies:\n'
            '- News: Google News, Bing News, GDELT, publisher RSS feeds, and article pages for preview images.\n'
            '- Outlet and place data: Wikidata and OpenStreetMap Nominatim.\n'
            '- Markets: Yahoo Finance and CNBC.\n'
            '- Our crawler feed, market snapshot and updates: GitHub, and our Cloudflare Worker, which stores '
            'nothing about you.'),
    InfoSection('Location',
        'Only used if you tap "Near me", and only after Android asks your permission. The app requests your '
            'approximate location, rounds it to about 1 km, and sends that to OpenStreetMap to find your town. '
            'It is not stored anywhere else. Your home country is otherwise guessed from your network\'s region.'),
    InfoSection('Children', 'The app is a general news reader and is not directed at children under 13.'),
    InfoSection('Changes and contact',
        'Changes to this policy ship with app updates and are listed in the project\'s history on GitHub. '
            'Questions: open an issue at github.com/JackLongman12/parallax-news.'),
  ],
);

const ratingsPage = InfoPage(
  title: 'How we rate outlets',
  intro: 'Every story shows which outlets cover it and how they lean. These labels describe the outlet, not '
      'the individual article, and they are estimates, not verdicts.',
  sections: [
    InfoSection('Political lean',
        'Seven steps from Far left to Far right, judged relative to the outlet\'s own country (a "center" '
            'outlet in one country can sit left or right of one elsewhere). Ratings start from an open, '
            'community-edited catalog in the app\'s source code, based on each outlet\'s editorial stance, '
            'ownership and endorsements. Anyone can propose a correction on GitHub.'),
    InfoSection('Factuality',
        'Very high to Low, based on an outlet\'s record of corrections, sourcing and failed fact checks. It is '
            'shown only where the catalog has a rating.'),
    InfoSection('Ownership and state affiliation',
        'Owners and state funding come from Wikidata (public, CC0). State-affiliated media are labelled.'),
    InfoSection('Unrated outlets',
        'Outlets not in the catalog are looked up on Wikidata. If nothing reliable is found they stay '
            '"Unrated" and are left out of the left/center/right bar instead of being guessed.'),
    InfoSection('Blindspots and divergent takes',
        'A blindspot is a story covered mostly by one side, with 3 or more rated outlets. A divergent take is a '
            'story both left and right cover in similar numbers, so you can compare the framing.'),
    InfoSection('What we don\'t do',
        'We don\'t use other companies\' proprietary ratings, and we don\'t rate individual journalists or '
            'articles. Headlines link to the publishers; we never copy article text.'),
  ],
);

const marketsPage = InfoPage(
  title: 'About market data',
  intro: 'Market data in Parallax News is for information only and is not financial, investment or trading advice.',
  sections: [
    InfoSection('Sources',
        'Prices and charts come from Yahoo Finance. When Yahoo is unavailable they come from CNBC, and from '
            'Finnhub for US stocks and crypto. Top movers can be built from the 100 largest US companies and '
            'trending tickers from StockTwits.'),
    InfoSection('Delays and accuracy',
        'Quotes can be delayed by 15 minutes or more and may be refreshed only every few minutes. Always check '
            'with your broker before making any decision.'),
  ],
);

/// Opens a pre-filled GitHub issue (app version only; nothing personal).
Future<void> reportProblem(BuildContext context) async {
  final v = await Updater.currentVersion();
  final uri = Uri.parse('$repoUrl/issues/new').replace(queryParameters: {
    'title': 'Problem: ',
    'body': 'What happened:\n\n\nWhat you expected:\n\n\nSteps to reproduce:\n\n\n'
        '---\nApp version: $v ($channel)',
  });
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open GitHub')));
  }
}
