import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../data/geo.dart';
import '../../models/place.dart';
import '../../models/source.dart';
import '../../services/places.dart';
import '../../state/app_state.dart';
import '../theme.dart';
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

String flagEmoji(String? cc) {
  if (cc == null || cc.length != 2) return '🌐';
  final up = cc.toUpperCase();
  return String.fromCharCodes(up.codeUnits.map((c) => 0x1F1E6 + c - 65));
}

void openPlace(BuildContext context, Place p) {
  context.read<AppState>().addRecent(p);
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaceScreen(place: p)));
}

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  static const _continentIcons = {
    'AF': Icons.landscape,
    'AS': Icons.temple_buddhist,
    'EU': Icons.castle,
    'NA': Icons.location_city,
    'SA': Icons.forest,
    'OC': Icons.waves,
    'AN': Icons.ac_unit,
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final home = countryByCode(app.settings.homeCountry);
    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(t, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        );

    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      const PlaceSearchPanel(shrinkWrap: true),
      if (app.followed.isNotEmpty) ...[
        section('Your places'),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: app.followed.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _PlaceCard(place: app.followed[i], width: 150),
          ),
        ),
      ],
      if (home != null) ...[
        section('Your country'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _PlaceCard(place: home.place, big: true),
        ),
      ],
      section('Browse the world'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.3,
          children: [
            _Tile(
              icon: Icons.public,
              title: 'World',
              subtitle: 'Global headlines',
              onTap: () => openPlace(context, Place.world),
            ),
            for (final c in continents)
              _Tile(
                icon: _continentIcons[c.code] ?? Icons.travel_explore,
                title: c.name,
                subtitle: '${countries.where((x) => x.continent == c.code).length} countries',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CountryGridScreen(continent: c))),
              ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Place search © OpenStreetMap contributors. Places & local outlets from Wikidata (CC0).',
            style: TextStyle(fontSize: 11)),
      ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Brand.purple.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Icon(icon, color: Brand.purple, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ]),
          ),
        ),
      );
}

/// Card for a place: flag/icon, name, follow toggle. Tap opens its news.
class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, this.width, this.big = false});
  final Place place;
  final double? width;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final followed = app.isFollowed(place);
    final leading = place.level == PlaceLevel.country
        ? Text(flagEmoji(place.countryCode), style: TextStyle(fontSize: big ? 34 : 24))
        : Icon(place.isLocalLevel ? Icons.holiday_village : Icons.map_outlined, color: Brand.purple, size: big ? 34 : 24);
    return SizedBox(
      width: width,
      child: Material(
        color: big ? Brand.purple : Brand.purple.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openPlace(context, place),
          child: Padding(
            padding: EdgeInsets.all(big ? 16 : 12),
            child: Row(children: [
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: big ? 18 : 14, color: big ? Colors.white : null)),
                  Text(big ? 'Tap for national & local news' : place.levelLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: big ? Colors.white70 : Theme.of(context).hintColor)),
                ]),
              ),
              if (big)
                IconButton(
                  tooltip: followed ? 'Unfollow' : 'Follow',
                  icon: Icon(followed ? Icons.bookmark : Icons.bookmark_border, color: Colors.white),
                  onPressed: () => app.toggleFollow(place),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Countries of a continent as a searchable grid of flags.
class CountryGridScreen extends StatefulWidget {
  const CountryGridScreen({super.key, required this.continent});
  final Continent continent;

  @override
  State<CountryGridScreen> createState() => _CountryGridScreenState();
}

class _CountryGridScreenState extends State<CountryGridScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = countries
        .where((c) => c.continent == widget.continent.code)
        .where((c) => _q.isEmpty || c.name.toLowerCase().contains(_q))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.continent.name),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.newspaper),
            label: const Text('News'),
            onPressed: () => openPlace(context, widget.continent.place),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Find a country',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => _q = v.toLowerCase().trim()),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.05),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final c = list[i];
              return Material(
                color: Brand.purple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => openPlace(context, c.place),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(flagEmoji(c.code), style: const TextStyle(fontSize: 30)),
                      const SizedBox(height: 4),
                      Text(c.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
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
