import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../data/geo.dart';
import '../../models/place.dart';
import '../../models/source.dart';
import '../../services/places.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'sources_screen.dart';
import 'story_list.dart';

/// Search-as-you-type for any place on earth, plus "Near me" and recents.
/// Tapping a result calls [onPick] (default: open the place's page).
class PlaceSearchPanel extends StatefulWidget {
  const PlaceSearchPanel({super.key, this.onPick, this.autofocus = false, this.shrinkWrap = false});
  final void Function(Place p)? onPick;
  final bool autofocus;
  final bool shrinkWrap;

  @override
  State<PlaceSearchPanel> createState() => _PlaceSearchPanelState();
}

class _PlaceSearchPanelState extends State<PlaceSearchPanel> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Place>? _results;
  bool _busy = false;
  String? _error;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _pick(Place p) {
    context.read<AppState>().addRecent(p);
    if (widget.onPick != null) {
      widget.onPick!(p);
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaceScreen(place: p)));
    }
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    // Nominatim allows ~1 request/second; debounce typing.
    _debounce = Timer(const Duration(milliseconds: 650), () => _search(q));
  }

  Future<void> _search(String q) async {
    final mySeq = ++_seq;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await PlaceService.search(q);
      if (mounted && mySeq == _seq) setState(() => _results = r);
    } catch (e) {
      if (mounted && mySeq == _seq) setState(() => _error = 'Search failed. Check your connection.');
    } finally {
      if (mounted && mySeq == _seq) setState(() => _busy = false);
    }
  }

  Future<void> _nearMe() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw 'Location is turned off';
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw 'Location permission denied';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)),
      );
      final place = await PlaceService.reverse(pos.latitude, pos.longitude);
      if (!mounted) return;
      if (place == null) throw 'Could not find your area';
      _pick(place);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: TextField(
          controller: _ctrl,
          autofocus: widget.autofocus,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: 'City, town, suburb, village, state, country…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : (_ctrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                              _ctrl.clear();
                              _results = null;
                            }))
                    : null),
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
          ),
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(avatar: const Icon(Icons.my_location, size: 18), label: const Text('Near me'), onPressed: _busy ? null : _nearMe),
          ),
          for (final p in app.recentPlaces)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(avatar: const Icon(Icons.history, size: 18), label: Text(p.name), onPressed: () => _pick(p)),
            ),
        ]),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text(_error!)),
      if (_results != null) ...[
        if (_results!.isEmpty) const ListTile(title: Text('No places found')),
        for (final p in _results!) PlaceTile(place: p, onTap: () => _pick(p)),
      ],
    ];
    if (widget.shrinkWrap) return Column(mainAxisSize: MainAxisSize.min, children: children);
    return Column(children: children);
  }
}

/// Opens the place search as a bottom sheet; returns the picked place.
Future<Place?> showPlacePicker(BuildContext context) => showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.75,
          child: SingleChildScrollView(
            child: PlaceSearchPanel(autofocus: true, shrinkWrap: true, onPick: (p) => Navigator.pop(ctx, p)),
          ),
        ),
      ),
    );

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ListView(children: [
      const PlaceSearchPanel(shrinkWrap: true),
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
  const PlaceTile({super.key, required this.place, this.onTap});
  final Place place;
  final VoidCallback? onTap;

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
      onTap: onTap ?? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaceScreen(place: place))),
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
    app.addRecent(place);
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
