import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/geo.dart';
import '../../models/category.dart';
import '../../state/app_state.dart';
import '../../services/provider_health.dart';
import '../../services/updater.dart';
import '../update_flow.dart';
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
        SwitchListTile(
          title: const Text('Lite mode'),
          subtitle: const Text('For older phones & slow data: no images, fewer parallel requests and outlets'),
          value: s.lite,
          onChanged: (v) => app.updateSettings((x) => x.lite = v),
        ),
        SwitchListTile(
          title: const Text('Discover local outlets'),
          subtitle: const Text('Find community papers, radio & TV for each place via Wikidata'),
          value: s.discoverLocal,
          onChanged: (v) => app.updateSettings((x) => x.discoverLocal = v),
        ),
        ListTile(
          title: const Text('Local outlets fetched per place'),
          subtitle: Slider(
            value: s.maxLocalOutlets.toDouble(),
            min: 3,
            max: 25,
            divisions: 22,
            label: '${s.maxLocalOutlets}',
            onChanged: (v) => app.updateSettings((x) => x.maxLocalOutlets = v.round()),
          ),
        ),
        const Divider(),
        SwitchListTile(
          title: const Text('News sources: Auto (recommended)'),
          subtitle: const Text('Uses Google + Bing, adds GDELT where it helps, and automatically '
              'routes around any source that is slow or rate-limited'),
          value: s.autoSources,
          onChanged: (v) => app.updateSettings((x) => x.autoSources = v),
        ),
        if (!s.autoSources) ...[
          SwitchListTile(
            title: const Text('Use Bing News'),
            subtitle: const Text('Second index for wider local coverage'),
            value: s.useBing,
            onChanged: (v) => app.updateSettings((x) => x.useBing = v),
          ),
          SwitchListTile(
            title: const Text('Use GDELT'),
            subtitle: const Text('Global multilingual index (slower, rate limited)'),
            value: s.useGdelt,
            onChanged: (v) => app.updateSettings((x) => x.useGdelt = v),
          ),
        ],
        const _SourceHealth(),
        ListTile(
          title: const Text('Clear image cache'),
          subtitle: const Text('Photos are cached on the phone (max 300, 7 days) so feeds load instantly'),
          trailing: const Icon(Icons.delete_outline_rounded),
          onTap: () async {
            await ImageCacheStore.clear();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image cache cleared')));
            }
          },
        ),
        const Divider(),
        const ListTile(title: Text('Muted topics')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in Category.values.where((c) => c != Category.general))
              FilterChip(label: Text(c.label), selected: app.profile.muted.contains(c), onSelected: (_) => app.toggleMute(c)),
          ]),
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
        const AboutListTile(
          applicationName: 'Parallax News',
          applicationLegalese: 'Open source (MIT). Ratings are a community seed + Wikidata (CC0). '
              'Place search © OpenStreetMap contributors. Headlines link to their publishers.',
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
