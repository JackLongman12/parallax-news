import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/geo.dart';
import '../../state/app_state.dart';
import '../../services/crash_reporter.dart';
import '../../services/crawler_feed.dart';
import '../../services/provider_health.dart';
import '../../services/updater.dart';
import '../theme.dart';
import '../update_flow.dart';
import 'feed_editor.dart';
import 'info_pages.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _auto = 'auto';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final sorted = [...countries]..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        const _InformLevel(),
        ListTile(
          leading: const Icon(Icons.tune_rounded, color: Brand.purple),
          title: const Text('Customize feed'),
          subtitle: const Text('Topics to follow or mute, your places, hidden outlets'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => showFeedEditor(context),
        ),
        ListTile(
          title: const Text('Appearance'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'dark', label: Text('Dark')),
                ButtonSegment(value: 'light', label: Text('Light')),
                ButtonSegment(value: 'system', label: Text('System')),
              ],
              selected: {app.themeMode},
              onSelectionChanged: (x) => app.setThemeMode(x.first),
            ),
          ),
        ),
        ListTile(
          title: const Text('Home country'),
          subtitle: Text(app.homeCountryAuto
              ? 'Auto: ${countryByCode(s.homeCountry)?.name ?? s.homeCountry} (from your network)'
              : 'Set manually · edition used for World and Topics'),
          trailing: SizedBox(
            width: 150,
            child: DropdownButton<String>(
              isExpanded: true,
              value: app.homeCountryAuto ? _auto : s.homeCountry,
              items: [
                const DropdownMenuItem(value: _auto, child: Text('Auto (detect)')),
                for (final c in sorted) DropdownMenuItem(value: c.code, child: Text(c.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => app.setHomeCountry(v == null || v == _auto ? null : v),
            ),
          ),
        ),
        ListTile(
          title: const Text('Clear cache'),
          subtitle: FutureBuilder<int>(
            future: ImageCacheStore.size(),
            builder: (_, snap) => Text('Cache: ${((snap.data ?? 0) / 1048576).toStringAsFixed(1)} MB (photos are capped at 40 MB). '
                'Clearing also removes old update files. Android may add a few MB of its own.'),
          ),
          trailing: const Icon(Icons.delete_outline_rounded),
          onTap: () async {
            await ImageCacheStore.clear();
            await Updater.cleanOldApks();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache cleared')));
            }
          },
        ),
        ListTile(
          title: const Text('On-device learning'),
          subtitle: Text('Topic model trained on ${app.classifier.trainedDocs} labelled headlines. '
              'Your reading interests never leave this phone.'),
          trailing: TextButton(onPressed: app.resetLearning, child: const Text('Reset')),
        ),
        const Divider(),
        SwitchListTile(
          title: const Text('Auto-update'),
          subtitle: const Text('Check for a new build at startup and download it'),
          value: app.autoUpdate,
          onChanged: app.setAutoUpdate,
        ),
        FutureBuilder<String>(
          future: Updater.currentVersion(),
          builder: (_, snap) => ListTile(
            title: const Text('Version'),
            subtitle: Text('${snap.data ?? '…'}\n${Updater.lastResult}'),
            isThreeLine: true,
            trailing: TextButton(onPressed: () => checkForUpdate(context, manual: true), child: const Text('Check now')),
          ),
        ),
        const _CrashToggle(),
        ListTile(
          leading: const Icon(Icons.info_outline_rounded),
          title: const Text('About'),
          subtitle: const Text('How we rate outlets, privacy, report a problem'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _AboutScreen())),
        ),
      ]),
    );
  }
}

/// Live status of each news source (refreshes every few seconds).
class _SourceHealth extends StatefulWidget {
  const _SourceHealth();

  @override
  State<_SourceHealth> createState() => _SourceHealthState();
}

class _SourceHealthState extends State<_SourceHealth> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ProviderHealth.instance.stats.values;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final s in stats)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Icon(Icons.circle_rounded, size: 10, color: s.coolingDown ? Colors.orange : (s.requests == 0 ? Colors.grey : Colors.green)),
              const SizedBox(width: 8),
              SizedBox(width: 100, child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(child: Text(s.status, style: Theme.of(context).textTheme.bodySmall)),
            ]),
          ),
      ]),
    );
  }
}


/// "How should we keep you informed?" as one compact choice.
class _InformLevel extends StatelessWidget {
  const _InformLevel();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    const options = [
      ('detailed', 'Everything', 'Including single-outlet and niche stories'),
      ('aware', 'Aware', 'Stories covered by at least 2 outlets'),
      ('key', 'Key issues only', 'Major stories covered by 5+ outlets'),
      ('off', 'Minimal', 'No Catch up card, just the feed'),
    ];
    final current = options.firstWhere((o) => o.$1 == app.informLevel, orElse: () => options[1]);
    return ListTile(
      title: const Text('How much news'),
      subtitle: Text(current.$3),
      trailing: DropdownButton<String>(
        value: current.$1,
        underline: const SizedBox.shrink(),
        items: [for (final o in options) DropdownMenuItem(value: o.$1, child: Text(o.$2))],
        onChanged: (v) {
          if (v != null) app.setInformLevel(v);
        },
      ),
    );
  }
}

/// Technical status, kept out of the main Settings list.
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Diagnostics')),
        body: ListView(children: const [
          ListTile(
            title: Text('News sources'),
            subtitle: Text('Our crawler, plus Google News and Bing News on the phone. Slow or rate-limited sources '
                'are skipped automatically.'),
          ),
          CrawlerStatusTile(),
          _SourceHealth(),
        ]),
      );
}


/// Whether the crawler feed (pre-built stories with many outlets) is loaded.
class CrawlerStatusTile extends StatefulWidget {
  const CrawlerStatusTile({super.key});

  @override
  State<CrawlerStatusTile> createState() => _CrawlerStatusTileState();
}

class _CrawlerStatusTileState extends State<CrawlerStatusTile> {
  bool _busy = false;

  static String _ago(DateTime t) {
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 1) return 'just now';
    if (m < 60) return '$m min ago';
    final h = m ~/ 60;
    return h < 24 ? '$h h ago' : '${h ~/ 24} d ago';
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await CrawlerFeed.load(force: true);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ok = CrawlerFeed.count > 0;
    final built = CrawlerFeed.builtAt;
    final err = CrawlerFeed.lastError;
    final text = ok
        ? '${CrawlerFeed.count} stories via ${CrawlerFeed.via}'
            '${built != null ? ', built ${_ago(built)}' : ''}'
            '${err != null ? ' (last refresh failed: $err)' : ''}'
        : err != null
            ? 'Not loaded: $err. Using on-device sources only.'
            : 'Not loaded yet. Open For You to fetch it.';
    return ListTile(
      leading: Icon(ok ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
          color: ok ? Brand.purple : Theme.of(context).colorScheme.error),
      title: const Text('Crawler feed'),
      subtitle: Text(text),
      trailing: _busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: _refresh),
    );
  }
}


class _CrashToggle extends StatefulWidget {
  const _CrashToggle();

  @override
  State<_CrashToggle> createState() => _CrashToggleState();
}

class _CrashToggleState extends State<_CrashToggle> {
  @override
  Widget build(BuildContext context) => SwitchListTile(
        title: const Text('Send crash reports'),
        subtitle: const Text('Error details and app version only, nothing about you'),
        value: CrashReporter.enabled,
        onChanged: (v) async {
          await CrashReporter.setEnabled(v);
          if (mounted) setState(() {});
        },
      );
}


class _AboutScreen extends StatelessWidget {
  const _AboutScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('About')),
        body: ListView(children: [
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Report a problem'),
            subtitle: const Text('Opens a GitHub issue with your app version filled in'),
            onTap: () => reportProblem(context),
          ),
          ListTile(
            leading: const Icon(Icons.balance_rounded),
            title: const Text('How we rate outlets'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => InfoPage.open(context, ratingsPage),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => InfoPage.open(context, privacyPage),
          ),
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Diagnostics'),
            subtitle: const Text('Crawler feed and news source status'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen())),
          ),
          const AboutListTile(
            applicationName: 'Parallax News',
            applicationLegalese: 'Open source (MIT). Ratings are a community seed + Wikidata (CC0). '
                'Headlines link to their publishers.',
          ),
        ]),
      );
}
