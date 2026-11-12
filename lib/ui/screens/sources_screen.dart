import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bias.dart';
import '../../models/source.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  String _q = '';
  Bias? _bias;
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
    var list = map.values.where((s) {
      if (_localOnly && !s.isLocal) return false;
      if (_bias != null && s.bias != _bias) return false;
      if (_q.isNotEmpty && !s.name.toLowerCase().contains(_q) && !s.domain.contains(_q)) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search sources', border: OutlineInputBorder(), isDense: true),
          onChanged: (v) => setState(() => _q = v.toLowerCase().trim()),
        ),
      ),
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: FilterChip(label: const Text('Local'), selected: _localOnly, onSelected: (v) => setState(() => _localOnly = v)),
          ),
          for (final b in Bias.values)
            Padding(
              padding: const EdgeInsets.all(4),
              child: ChoiceChip(
                label: Text(b.label),
                selected: _bias == b,
                onSelected: (v) => setState(() => _bias = v ? b : null),
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('${list.length} sources · local outlets are added as you explore places',
            style: Theme.of(context).textTheme.bodySmall),
      ),
      Expanded(child: ListView.builder(itemCount: list.length, itemBuilder: (_, i) => SourceTile(source: list[i]))),
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
