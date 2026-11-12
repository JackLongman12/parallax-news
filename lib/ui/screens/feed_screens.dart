import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../models/story.dart';
import '../../services/curator.dart';
import '../../state/app_state.dart';
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
      loader: (force) => app.repo.briefing(
        places: app.followed,
        topics: app.followedTopics,
        profile: app.profile,
        force: force,
      ),
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
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          app.followed.isEmpty
              ? 'Your daily briefing. Follow places in Explore to add local news.'
              : 'Your daily briefing · ${app.followed.length} place${app.followed.length == 1 ? '' : 's'} · ${app.followedTopics.length} topics',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
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
