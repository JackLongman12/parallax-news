import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/geo.dart';
import '../../models/place.dart';
import '../../models/source.dart';
import '../../services/places.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'sources_screen.dart';
import 'story_list.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _ctrl = TextEditingController();
  List<Place>? _results;
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.length < 2) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final r = await PlaceService.search(q);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _ctrl,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: 'Search any city, town, suburb or village…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searching
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : (_results != null
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() { _results = null; _ctrl.clear(); }))
                    : null),
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
      if (_results != null) ...[
        if (_results!.isEmpty) const ListTile(title: Text('No places found')),
        for (final p in _results!) PlaceTile(place: p),
        const Divider(),
      ],
      if (app.followed.isNotEmpty) ...[
        const _Header('Your places'),
        for (final p in app.followed) PlaceTile(place: p),
      ],
      const _Header('Browse the world'),
      PlaceTile(place: Place.world),
      for (final c in continents) PlaceTile(place: c.place),
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Place search © OpenStreetMap contributors. Places & local outlets from Wikidata (CC0).',
            style: TextStyle(fontSize: 11)),
      ),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class PlaceTile extends StatelessWidget {
  const PlaceTile({super.key, required this.place});
  final Place place;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final f = app.isFollowed(place);
    return ListTile(
      leading: Icon(_icon(place.level)),
      title: Text(place.name),
      subtitle: Text(place.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: place.level == PlaceLevel.world
          ? null
          : IconButton(
              tooltip: f ? 'Unfollow' : 'Follow',
              icon: Icon(f ? Icons.bookmark : Icons.bookmark_border),
              onPressed: () => app.toggleFollow(place),
            ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaceScreen(place: place))),
    );
  }

  static IconData _icon(PlaceLevel l) {
    switch (l) {
      case PlaceLevel.world:
        return Icons.public;
      case PlaceLevel.continent:
        return Icons.travel_explore;
      case PlaceLevel.country:
        return Icons.flag_outlined;
      case PlaceLevel.region:
        return Icons.map_outlined;
      case PlaceLevel.district:
        return Icons.layers_outlined;
      case PlaceLevel.city:
        return Icons.location_city;
      case PlaceLevel.locality:
        return Icons.holiday_village_outlined;
    }
  }
}

class PlaceScreen extends StatelessWidget {
  const PlaceScreen({super.key, required this.place});
  final Place place;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final f = app.isFollowed(place);
    final showOutlets = place.level.index >= PlaceLevel.country.index;
    final tabs = [
      const Tab(text: 'Stories'),
      if (showOutlets) const Tab(text: 'Local sources'),
      if (place.level != PlaceLevel.locality) const Tab(text: 'Places within'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(place.name),
            Text(place.subtitle, style: Theme.of(context).textTheme.bodySmall),
          ]),
          actions: [
            if (place.level != PlaceLevel.world)
              IconButton(
                icon: Icon(f ? Icons.bookmark : Icons.bookmark_border),
                tooltip: f ? 'Unfollow' : 'Follow',
                onPressed: () => app.toggleFollow(place),
              ),
          ],
          bottom: TabBar(tabs: tabs),
        ),
        body: TabBarView(children: [
          StoryList(
            key: ValueKey('place:${place.id}'),
            loader: (force) async => (await app.repo.place(place, force: force)).stories,
          ),
          if (showOutlets) _OutletsTab(place: place),
          if (place.level != PlaceLevel.locality) _ChildrenTab(place: place),
        ]),
      ),
    );
  }
}

class _OutletsTab extends StatelessWidget {
  const _OutletsTab({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    if (place.level != PlaceLevel.country && place.wikidataId == null) {
      return const EmptyOrError(
          message: 'Local outlet discovery needs a Wikidata-linked place. Stories still include local results from news search.');
    }
    return FutureBuilder<List<SourceInfo>>(
      future: app.repo.outletsFor(place),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return const EmptyOrError(message: 'No outlets for this place are listed on Wikidata yet.\nYou can add them at wikidata.org and they will appear here.');
        }
        final sorted = [...list]..sort((a, b) => a.name.compareTo(b.name));
        return ListView.builder(
          itemCount: sorted.length,
          itemBuilder: (_, i) => SourceTile(source: app.bias.lookup(sorted[i].domain, name: sorted[i].name)),
        );
      },
    );
  }
}

class _ChildrenTab extends StatefulWidget {
  const _ChildrenTab({required this.place});
  final Place place;

  @override
  State<_ChildrenTab> createState() => _ChildrenTabState();
}

class _ChildrenTabState extends State<_ChildrenTab> {
  late final Future<List<Place>> _future = _load();
  String _filter = '';

  Future<List<Place>> _load() async {
    final p = widget.place;
    if (p.level == PlaceLevel.world) return [for (final c in continents) c.place];
    if (p.level == PlaceLevel.continent) {
      return [for (final c in countries.where((c) => c.continent == p.continentCode)) c.place]
        ..sort((a, b) => a.name.compareTo(b.name));
    }
    return PlaceService.childrenOf(p).timeout(const Duration(seconds: 30));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Place>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return EmptyOrError(message: 'Could not load places: ${snap.error}');
        final all = snap.data ?? const [];
        if (all.isEmpty) {
          return const EmptyOrError(message: 'No subdivisions listed. Use search in Explore to find towns and neighbourhoods.');
        }
        final list = _filter.isEmpty ? all : all.where((p) => p.name.toLowerCase().contains(_filter)).toList();
        return Column(children: [
          if (all.length > 12)
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.filter_list), hintText: 'Filter', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _filter = v.toLowerCase()),
              ),
            ),
          Expanded(child: ListView.builder(itemCount: list.length, itemBuilder: (_, i) => PlaceTile(place: list[i]))),
        ]);
      },
    );
  }
}
