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
/// you don't follow yet (so the feed widens your view instead of narrowing it).
class ForYouScreen extends StatelessWidget {
  const ForYouScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final key = ValueKey('${app.followed.map((p) => p.id).join(',')}|${app.followedTopics.map((c) => c.name).join(',')}|${app.settings.homeCountry}');
    final extra = Category.values
        .where((c) => c != Category.general && c != Category.local && !app.followedTopics.contains(c))
        .toList();

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
      header: const BriefingHeader(),
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

/// Instagram-style row of gradient rings: your places and topics.
class BriefingHeader extends StatelessWidget {
  const BriefingHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = <(String, Widget, VoidCallback)>[
      for (final p in [Place.world, ...app.followed])
        (
          p.name,
          _bubble(p.level == PlaceLevel.world ? Icons.public : (p.isLocalLevel ? Icons.holiday_village : Icons.flag),
              const [Brand.deep, Brand.blue]),
          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaceScreen(place: p))),
        ),
      for (final c in app.followedTopics)
        (
          c.label,
          _bubble(Brand.categoryIcon(c), Brand.categoryColors(c)),
          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TopicPage(category: c))),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) => GestureDetector(
            onTap: items[i].$3,
            child: SizedBox(
              width: 68,
              child: Column(children: [
                GradientRing(child: items[i].$2),
                const SizedBox(height: 5),
                Text(items[i].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
        child: Row(children: [
          ShaderMask(
            shaderCallback: (r) => Brand.spectrum.createShader(r),
            child: const Text("Today's briefing",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
          const Spacer(),
          Text('${app.followed.length} places · ${app.followedTopics.length} topics',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    ]);
  }

  static Widget _bubble(IconData icon, List<Color> colors) => DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
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
