import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/geo.dart';
import '../../models/bias.dart';
import '../../models/category.dart';
import '../../models/source.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'explore_screens.dart';

enum _Group { lean, country, topic }

/// Sources, grouped so you never scroll through hundreds of rows:
/// by Lean, by Country (yours first) or by Topic. Groups are collapsed with
/// counts; search jumps straight to matches.
class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  String _q = '';
  _Group _group = _Group.lean;
  bool _localOnly = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final map = <String, SourceInfo>{};
    for (final s in app.bias.discovered) {
      map[s.domain] = app.bias.lookup(s.domain, name: s.name);
    }
    for (final s in app.bias.curated) {
      map[s.domain] = app.bias.lookup(s.domain, name: s.name);
    }
    final all = map.values.where((s) {
      if (_localOnly && !s.isLocal) return false;
      if (_q.isNotEmpty && !s.name.toLowerCase().contains(_q) && !s.domain.contains(_q)) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Build groups.
    final groups = <(String, Widget?, List<SourceInfo>)>[];
    switch (_group) {
      case _Group.lean:
        for (final b in Bias.values) {
          final items = all.where((s) => s.bias == b).toList();
          if (items.isNotEmpty) {
            groups.add((b.label, CircleAvatar(radius: 7, backgroundColor: b.color), items));
          }
        }
      case _Group.country:
        final byCc = <String, List<SourceInfo>>{};
        for (final s in all) {
          byCc.putIfAbsent(s.country ?? '??', () => []).add(s);
        }
        final home = app.settings.homeCountry;
        final keys = byCc.keys.toList()
          ..sort((a, b) {
            if (a == home) return -1;
            if (b == home) return 1;
            return (countryByCode(a)?.name ?? 'zz').compareTo(countryByCode(b)?.name ?? 'zz');
          });
        for (final k in keys) {
          groups.add((countryByCode(k)?.name ?? 'International / other', Text(flagEmoji(k == '??' ? null : k)), byCc[k]!));
        }
      case _Group.topic:
        final general = all.where((s) => s.topics.isEmpty).toList();
        for (final c in Category.values) {
          final items = all.where((s) => s.topics.contains(c)).toList();
          if (items.isNotEmpty) groups.add((c.label, Icon(Brand.categoryIcon(c), size: 18), items));
        }
        if (general.isNotEmpty) groups.add(('General news', const Icon(Icons.newspaper, size: 18), general));
    }

    final searching = _q.isNotEmpty;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search ${map.length} sources',
            filled: true,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
          ),
          onChanged: (v) => setState(() => _q = v.toLowerCase().trim()),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Expanded(
            child: SegmentedButton<_Group>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _Group.lean, label: Text('Lean')),
                ButtonSegment(value: _Group.country, label: Text('Country')),
                ButtonSegment(value: _Group.topic, label: Text('Topic')),
              ],
              selected: {_group},
              onSelectionChanged: (s) => setState(() => _group = s.first),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(label: const Text('Local'), selected: _localOnly, onSelected: (v) => setState(() => _localOnly = v)),
        ]),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: all.isEmpty
            ? const Center(child: Text('No sources match.'))
            : ListView.builder(
                itemCount: groups.length,
                itemBuilder: (_, i) {
                  final g = groups[i];
                  return ExpansionTile(
                    key: PageStorageKey('src-${_group.name}-${g.$1}'),
                    // While searching, open every group so matches are visible.
                    initiallyExpanded: searching || groups.length == 1,
                    leading: g.$2,
                    title: Text(g.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: Brand.purple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: Text('${g.$3.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    children: [for (final s in g.$3) SourceTile(source: s)],
                  );
                },
              ),
      ),
    ]);
  }
}

class SourceTile extends StatelessWidget {
  const SourceTile({super.key, required this.source});
  final SourceInfo source;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(source.name),
        subtitle: Text([source.domain, if (source.country != null) source.country!, if (source.topics.isNotEmpty) source.topics.map((t) => t.label).join(', ')].join(' · '),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: BiasChip(source: source),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => SourceSheet(source: source),
        ),
      );
}

class SourceSheet extends StatelessWidget {
  const SourceSheet({super.key, required this.source});
  final SourceInfo source;

  String _origin(RatingOrigin o) {
    switch (o) {
      case RatingOrigin.curated:
        return 'Community catalog (bundled with the app)';
      case RatingOrigin.wikidata:
        return 'Wikidata political alignment';
      case RatingOrigin.userOverride:
        return 'Your own rating';
      case RatingOrigin.none:
        return 'Not rated yet';
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final s = source;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.name, style: Theme.of(context).textTheme.titleLarge),
          Text(s.domain),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            BiasChip(source: s, dense: false),
            if (s.isLocal) const Tag('Local', color: Colors.teal),
            if (s.stateAffiliated) const Tag('State-affiliated', color: Colors.deepOrange),
          ]),
          const SizedBox(height: 12),
          _row('Rating source', _origin(s.origin)),
          if (s.alignmentLabel != null) _row('Wikidata label', s.alignmentLabel!),
          _row('Factuality', s.factuality.label),
          if (s.owner != null) _row('Owner', s.owner!),
          if (s.country != null) _row('Country', s.country!),
          const SizedBox(height: 16),
          const Text('Disagree? Set your own rating (stored only on this device):'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final b in Bias.values.where((b) => b != Bias.unrated))
              ActionChip(
                label: Text(b.label),
                onPressed: () {
                  app.setOverride(s.domain, b);
                  Navigator.pop(context);
                },
              ),
            if (s.origin == RatingOrigin.userOverride)
              ActionChip(
                label: const Text('Reset'),
                onPressed: () {
                  app.setOverride(s.domain, null);
                  Navigator.pop(context);
                },
              ),
          ]),
          const SizedBox(height: 12),
          TextButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: const Text('Visit website'),
            onPressed: () => openArticle(context, 'https://${s.domain}'),
          ),
        ]),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v)),
        ]),
      );
}
