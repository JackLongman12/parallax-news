import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../models/story.dart';
import '../../services/curator.dart';
import '../../models/place.dart';
import '../../services/home_widgets.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'explore_screens.dart';
import 'story_list.dart';

/// "For You": the curated daily briefing with endless scroll into topics
/// you don't follow yet. Tapping a ring above the feed filters it in place
/// (one tap to see a place or topic, no navigation).
class ForYouScreen extends StatefulWidget {
  const ForYouScreen({super.key});

  @override
  State<ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends State<ForYouScreen> {
  /// null = full briefing; otherwise 'p:<placeId>' or 't:<category>'.
  String? _sel;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final extra = Category.values
        .where((c) => c != Category.general && c != Category.local && !app.followedTopics.contains(c))
        .toList();
    final header = BriefingHeader(selected: _sel, onSelect: (id) => setState(() => _sel = id));

    Place? place;
    Category? topic;
    final sel = _sel;
    if (sel != null && sel.startsWith('p:')) {
      final id = sel.substring(2);
      place = id == Place.world.id ? Place.world : app.followed.where((p) => p.id == id).firstOrNull;
    } else if (sel != null && sel.startsWith('t:')) {
      topic = Category.byName(sel.substring(2));
    }

    if (place != null) {
      final p = place;
      return StoryList(
        key: ValueKey('fy-place:${p.id}'),
        header: header,
        loader: (force) async => Curator.rank((await app.repo.place(p, force: force)).stories, app.profile, limit: 80),
      );
    }
    if (topic != null) {
      final c = topic;
      return StoryList(
        key: ValueKey('fy-topic:${c.name}'),
        header: header,
        loader: (force) async => Curator.rank((await app.repo.topic(c, force: force)).stories, app.profile, limit: 80),
      );
    }

    final key = ValueKey('${app.followed.map((p) => p.id).join(',')}|${app.followedTopics.map((c) => c.name).join(',')}|${app.settings.homeCountry}');
    return StoryList(
      key: key,
      loader: (force) async {
        final stories = await app.repo.briefing(
          places: app.followed,
          topics: app.followedTopics,
          profile: app.profile,
          force: force,
        );
        unawaited(HomeWidgets.publish(stories));
        return stories;
      },
      onLoadMore: (page) async {
        final picks = extra.skip(page * 2).take(2).toList();
        if (picks.isEmpty) return <Story>[];
        final stories = <Story>[];
        for (final c in picks) {
          final b = await app.repo.topic(c);
          stories.addAll(b.stories);
        }
        return Curator.rank(stories, app.profile, limit: 30);
      },
      header: header,
    );
  }
}

class TopicsScreen extends StatefulWidget {
  const TopicsScreen({super.key});

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  Category _selected = Category.technology;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cats = Category.values.where((c) => c != Category.general && c != Category.local).toList();
    final followed = app.followsTopic(_selected);
    final muted = app.profile.muted.contains(_selected);
    return Column(children: [
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          children: [
            for (final c in cats)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(c.label),
                  selected: c == _selected,
                  avatar: app.followsTopic(c) ? const Icon(Icons.star, size: 16) : null,
                  onSelected: (_) => setState(() => _selected = c),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          FilledButton.tonalIcon(
            icon: Icon(followed ? Icons.star : Icons.star_border),
            label: Text(followed ? 'In your briefing' : 'Add to briefing'),
            onPressed: () => app.toggleTopic(_selected),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            icon: Icon(muted ? Icons.volume_off : Icons.volume_up_outlined),
            label: Text(muted ? 'Muted' : 'Mute'),
            onPressed: () => app.toggleMute(_selected),
          ),
        ]),
      ),
      Expanded(
        child: StoryList(
          key: ValueKey('topic:${_selected.name}'),
          loader: (force) async => (await app.repo.topic(_selected, force: force)).stories,
        ),
      ),
    ]);
  }
}

class BlindspotScreen extends StatelessWidget {
  const BlindspotScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return StoryList(
      key: ValueKey('blind:${app.followed.length}:${app.followedTopics.length}'),
      loader: (force) => app.repo.briefing(
        places: app.followed,
        topics: app.followedTopics,
        profile: app.profile,
        force: force,
      ),
      filter: (s) => s.distribution.blindspotFor != null,
      emptyMessage: 'No blindspots right now. A blindspot is a story covered mostly by one side of the political spectrum.',
      header: const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text('Stories mostly ignored by one side of the spectrum.'),
      ),
    );
  }
}

/// Instagram-style rings: For You, +Add, then your places and topics.
/// Tap = filter the feed in place. Long-press = open the full page.
class BriefingHeader extends StatelessWidget {
  const BriefingHeader({super.key, this.selected, this.onSelect});
  final String? selected;
  final void Function(String? id)? onSelect;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    void select(String? id) => onSelect?.call(id);

    Future<void> add() async {
      final p = await showPlacePicker(context);
      if (p == null || !context.mounted) return;
      if (!app.isFollowed(p)) app.toggleFollow(p);
      select('p:${p.id}');
    }

    final items = <(String, Widget, String?, VoidCallback, VoidCallback?)>[
      ('For You', _bubble(Icons.auto_awesome), null, () => select(null), null),
      ('Add place', _bubble(Icons.add, light: true), '+', add, null),
      for (final p in [Place.world, ...app.followed])
        (
          p.name,
          _bubble(p.level == PlaceLevel.world ? Icons.public : (p.isLocalLevel ? Icons.holiday_village : Icons.flag)),
          'p:${p.id}',
          () => select('p:${p.id}'),
          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaceScreen(place: p))),
        ),
      for (final c in app.followedTopics)
        (
          c.label,
          _bubble(Brand.categoryIcon(c)),
          't:${c.name}',
          () => select('t:${c.name}'),
          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TopicPage(category: c))),
        ),
    ];
    var title = "Today's briefing";
    for (final it in items) {
      if (selected != null && it.$3 == selected) title = it.$1;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final it = items[i];
            final active = it.$3 == selected;
            return GestureDetector(
              onTap: it.$4,
              onLongPress: it.$5,
              child: SizedBox(
                width: 68,
                child: Column(children: [
                  GradientRing(active: active || it.$3 == '+', child: it.$2),
                  const SizedBox(height: 5),
                  Text(it.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w900 : FontWeight.w600)),
                ]),
              ),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
        child: Row(children: [
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
          ),
          if (selected == null)
            Text('${app.followed.length} places · ${app.followedTopics.length} topics',
                style: Theme.of(context).textTheme.bodySmall)
          else
            TextButton(onPressed: () => select(null), child: const Text('Show all')),
        ]),
      ),
    ]);
  }

  static Widget _bubble(IconData icon, {bool light = false}) => ColoredBox(
        color: light ? Brand.purple : Brand.black,
        child: Center(child: Icon(icon, color: Colors.white, size: 26)),
      );
}

class TopicPage extends StatelessWidget {
  const TopicPage({super.key, required this.category});
  final Category category;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(category.label)),
      body: StoryList(loader: (force) async => (await app.repo.topic(category, force: force)).stories),
    );
  }
}
