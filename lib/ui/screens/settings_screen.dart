import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/geo.dart';
import '../../models/category.dart';
import '../../state/app_state.dart';
import '../../services/updater.dart';
import '../update_flow.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final sorted = [...countries]..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        ListTile(
          title: const Text('Home country'),
          subtitle: const Text('Edition used for World and Topics'),
          trailing: SizedBox(
            width: 150,
            child: DropdownButton<String>(
              isExpanded: true,
              value: s.homeCountry,
              items: [for (final c in sorted) DropdownMenuItem(value: c.code, child: Text(c.name, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => app.updateSettings((x) => x.homeCountry = v ?? 'US'),
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
            subtitle: Text(snap.data ?? '…'),
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
