import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/subtopics.dart';
import '../../models/category.dart';
import '../../models/story.dart';
import '../../services/cover_images.dart';
import '../../services/curator.dart';
import '../../models/place.dart';
import '../../services/home_widgets.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../nav.dart';
import '../widgets/common.dart';
import '../widgets/daily_overview.dart';
import '../widgets/markets_strip.dart';
import 'explore_screens.dart';
import 'feed_editor.dart';
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
        scrollToTop: TabReselect.tabs[0],
        jumpToTop: TabReselect.tops[0],
        key: ValueKey('fy-place:${p.id}'),
        header: header,
        loader: (force) async => Curator.rank((await app.repo.place(p, force: force)).stories, app.profile, limit: 80),
      );
    }
    if (topic != null) {
      final c = topic;
      return StoryList(
        scrollToTop: TabReselect.tabs[0],
        jumpToTop: TabReselect.tops[0],
        key: ValueKey('fy-topic:${c.name}'),
        header: header,
        loader: (force) async => Curator.rank((await app.repo.topic(c, force: force)).stories, app.profile, limit: 80),
      );
    }

    final key = ValueKey('${app.followed.map((p) => p.id).join(',')}|${app.followedTopics.map((c) => c.name).join(',')}|${app.settings.homeCountry}');
    return StoryList(
      key: key,
      scrollToTop: TabReselect.tabs[0],
        jumpToTop: TabReselect.tops[0],
      // Opens instantly with last session's feed, then streams fresh news in
      // stages (World + 3 topics first, then places, then other topics).
      initial: app.snapshot,
      autoRefresh: const Duration(minutes: 8),
      streamLoader: (force) async* {
        List<Story>? last;
        await for (final stories in app.repo.briefingStream(
          places: app.followed,
          topics: app.followedTopics,
          profile: app.profile,
          force: force,
        )) {
          last = stories;
          yield stories;
        }
        if (last != null && last.isNotEmpty) {
          app.saveSnapshot(last);
          unawaited(HomeWidgets.publish(last));
        }
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

/// Topics: a photo grid. Your topics first, then everything else.
/// Tap a tile to read it; follow / mute from the topic page.
class TopicsScreen extends StatefulWidget {
  const TopicsScreen({super.key});

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    TabReselect.tabs[1].addListener(_toTop);
    TabReselect.tops[1].addListener(_jump);
  }

  void _jump() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    TabReselect.tabs[1].removeListener(_toTop);
    TabReselect.tops[1].removeListener(_jump);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final all = Category.values.where((c) => c != Category.general && c != Category.local).toList();
    final mine = all.where(app.followsTopic).toList();
    final rest = all.where((c) => !app.followsTopic(c)).toList();
    Widget header(String t, [Widget? trailing]) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 8, 10),
          child: Row(children: [
            Expanded(child: Text(t, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
            if (trailing != null) trailing,
          ]),
        );
    SliverPadding grid(List<Category> cats) => SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.45),
            delegate: SliverChildBuilderDelegate((_, i) => TopicTile(category: cats[i]), childCount: cats.length),
          ),
        );
    final forYou = SubtopicSuggester.forYou(app.profile);
    final breakOut = SubtopicSuggester.breakOut(app.profile);
    return CustomScrollView(controller: _scroll, slivers: [
      if (forYou.isNotEmpty) ...[
        SliverToBoxAdapter(child: header('Picked for you')),
        SliverToBoxAdapter(child: SubPathChips(paths: forYou)),
      ],
      const SliverToBoxAdapter(
        child: OneTimeTip(id: 'topicsTip', text: 'Tap a topic to read it, long-press to follow it. Inside a topic, pick a subtopic, then a niche.'),
      ),
      SliverToBoxAdapter(child: header('Outside your bubble')),
      SliverToBoxAdapter(child: SubPathChips(paths: breakOut, icon: Icons.explore_rounded)),
      if (mine.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: header('Your topics',
              TextButton.icon(icon: const Icon(Icons.tune_rounded, size: 18), label: const Text('Edit'), onPressed: () => showFeedEditor(context))),
        ),
        grid(mine),
      ],
      SliverToBoxAdapter(child: header(mine.isEmpty ? 'Pick topics you like' : 'Discover more')),
      grid(rest),
      SliverToBoxAdapter(child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom)),
    ]);
  }
}

/// Photo tile for a topic, with a follow badge.
class TopicTile extends StatefulWidget {
  const TopicTile({super.key, required this.category});
  final Category category;

  @override
  State<TopicTile> createState() => _TopicTileState();
}

class _TopicTileState extends State<TopicTile> {
  late final Future<String?> _img = CoverImages.topicImage(widget.category);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = widget.category;
    final following = app.followsTopic(c);
    final muted = app.profile.muted.contains(c);
    return Material(
      color: Brand.purple,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TopicPage(category: c))),
        onLongPress: () => app.toggleTopic(c),
        child: Stack(fit: StackFit.expand, children: [
          FutureBuilder<String?>(
            future: _img,
            builder: (context, snap) => snap.data == null
                ? Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Brand.categoryIcon(c), size: 64, color: Colors.white.withValues(alpha: 0.15)),
                    ),
                  )
                : NetImage(snap.data!, width: 600),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x22000000), Color(0xB0000000)],
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: Row(children: [
              Icon(Brand.categoryIcon(c), color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(c.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        decoration: muted ? TextDecoration.lineThrough : null)),
              ),
            ]),
          ),
          if (following)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 14, color: Brand.purple),
              ),
            ),
        ]),
      ),
    );
  }
}

class TopicPage extends StatefulWidget {
  const TopicPage({super.key, required this.category, this.initial});
  final Category category;

  /// Open directly on a subtopic or niche.
  final SubPath? initial;

  @override
  State<TopicPage> createState() => _TopicPageState();
}

class _TopicPageState extends State<TopicPage> {
  Sub? _sub;
  Sub? _niche;

  Category get category => widget.category;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _sub = init.chain.first;
      _niche = init.chain.length > 1 ? init.chain[1] : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final following = app.followsTopic(category);
    final muted = app.profile.muted.contains(category);
    final subs = subtopics[category] ?? const <Sub>[];
    final chain = [if (_sub != null) _sub!, if (_niche != null) _niche!];
    final path = chain.isEmpty ? null : SubPath(category, chain);

    Widget chips(List<Sub> items, Sub? selected, void Function(Sub?) onPick, {bool small = false}) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Wrap(
            spacing: 0,
            runSpacing: 6,
            children: [
              for (final s in items)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s.label, style: TextStyle(fontSize: small ? 12 : 13, fontWeight: FontWeight.w700)),
                    selected: selected == s,
                    showCheckmark: false,
                    selectedColor: Brand.purple,
                    labelStyle: TextStyle(color: selected == s ? Colors.white : null),
                    onSelected: (v) => onPick(v ? s : null),
                  ),
                ),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(path == null ? category.label : path.leaf.label, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (_) => app.toggleMute(category),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'mute', child: Text(muted ? 'Unmute ${category.label}' : 'Mute ${category.label}')),
            ],
          ),
        ],
      ),
      // One-handed: follow / unfollow from the bottom of the screen.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          height: 52,
          child: following
              ? OutlinedButton.icon(
                  icon: const Icon(Icons.check_rounded),
                  label: Text('Following ${category.label}'),
                  onPressed: () => app.toggleTopic(category),
                )
              : FilledButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: Text('Follow ${category.label}'),
                  onPressed: () => app.toggleTopic(category),
                ),
        ),
      ),
      body: Column(children: [
        if (subs.isNotEmpty)
          chips(subs, _sub, (s) => setState(() {
                _sub = s;
                _niche = null;
              })),
        if (_sub != null && _sub!.niches.isNotEmpty)
          chips(_sub!.niches, _niche, (n) => setState(() => _niche = n), small: true),
        if (path != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(path.path, style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
        if (path == null && (category == Category.business || category == Category.finance)) const MarketsStrip(),
        Expanded(
          child: StoryList(
            key: ValueKey('tp:${category.name}:${path?.leaf.label ?? ''}'),
            loader: (force) async {
              final bundle = path == null
                  ? await app.repo.topic(category, force: force)
                  : await app.repo.subtopic(path, force: force);
              return Curator.rank(bundle.stories, app.profile, limit: 80);
            },
          ),
        ),
      ]),
    );
  }
}

/// Chips for a list of subtopic paths; tap opens the topic page on it.
class SubPathChips extends StatelessWidget {
  const SubPathChips({super.key, required this.paths, this.icon});
  final List<SubPath> paths;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    // Wraps onto several lines: everything visible, no sideways scrolling.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final sp in paths)
          ActionChip(
            avatar: Icon(icon ?? Brand.categoryIcon(sp.category), size: 16),
            label: Text(sp.chain.map((s) => s.label).join(' > '), style: const TextStyle(fontWeight: FontWeight.w700)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => TopicPage(category: sp.category, initial: sp))),
          ),
      ]),
    );
  }
}

class BlindspotScreen extends StatelessWidget {
  const BlindspotScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return StoryList(
      scrollToTop: TabReselect.tabs[4],
      jumpToTop: TabReselect.tops[4],
      key: ValueKey('blind:${app.followed.length}:${app.followedTopics.length}:${app.settings.homeCountry}'),
      loader: (force) => app.repo.blindspotPool(places: app.followed, topics: app.followedTopics, force: force),
      emptyMessage: 'No one-sided stories right now. More outlets get rated as you browse, '
          'so check back later or pull to refresh.',
      header: const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text('Blindspots first: stories one side is barely covering. Then stories covered mostly by one side.'),
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

    // Tapping the ring that is already selected goes back to the full feed.
    void toggle(String id) => select(selected == id ? null : id);
    String? photo(String key) {
      final top = app.repo.cached(key)?.stories.firstOrNull;
      return top == null ? null : CoverImages.cached(top);
    }

    final items = <(String, Widget, String?, VoidCallback, VoidCallback?)>[
      ('Add place', const _RingPhoto(icon: Icons.add_rounded, light: true), '+', add, null),
      for (final p in [Place.world, ...app.followed])
        (
          p.name,
          _RingPhoto(
            icon: p.level == PlaceLevel.world ? Icons.public_rounded : (p.isLocalLevel ? Icons.holiday_village_rounded : Icons.flag_rounded),
            image: photo('place:${p.id}'),
            fetch: () => p.level == PlaceLevel.world
                ? CoverImages.topicImage(Category.world)
                : CoverImages.placeImage(p.name, p.id),
          ),
          'p:${p.id}',
          () => toggle('p:${p.id}'),
          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaceScreen(place: p))),
        ),
      for (final c in app.followedTopics)
        (
          c.label,
          _RingPhoto(icon: Brand.categoryIcon(c), image: photo('topic:${c.name}'), fetch: () => CoverImages.topicImage(c)),
          't:${c.name}',
          () => toggle('t:${c.name}'),
          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TopicPage(category: c))),
        ),
    ];
    var title = "Today's briefing";
    for (final it in items) {
      if (selected != null && it.$3 == selected) title = it.$1;
    }
    // The circular "stories" row was removed as redundant: places and topics
    // live in Explore / Topics and the Customize sheet.
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
        child: Row(children: [
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
          ),
          if (selected != null) TextButton(onPressed: () => select(null), child: const Text('Show all')),
          IconButton(
            tooltip: 'Customize feed',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => showFeedEditor(context),
          ),
        ]),
      ),
      if (selected == null)
        const OneTimeTip(
          id: 'feedGestures',
          text: 'Long-press any story for options: more or less like it, follow or mute its topic, or hide an outlet. '
              'Tap the For You tab again to jump to the top; tap once more to refresh.',
        ),
      if (selected == null) const DailyOverview(),
    ]);
  }
}

/// Ring content: the latest story's photo, else a photo of the place/topic.
class _RingPhoto extends StatefulWidget {
  const _RingPhoto({required this.icon, this.image, this.fetch, this.light = false});
  final IconData icon;
  final String? image;
  final Future<String?> Function()? fetch;
  final bool light;

  @override
  State<_RingPhoto> createState() => _RingPhotoState();
}

class _RingPhotoState extends State<_RingPhoto> {
  Future<String?>? _future;

  @override
  void initState() {
    super.initState();
    if (widget.image == null && widget.fetch != null) _future = widget.fetch!();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: widget.light ? Brand.purple : Brand.black,
      child: Center(child: Icon(widget.icon, color: Colors.white, size: 26)),
    );
    Widget photo(String url) => Stack(fit: StackFit.expand, children: [
          fallback,
          NetImage(url, width: 200),
        ]);
    if (widget.image != null) return photo(widget.image!);
    if (_future == null) return fallback;
    return FutureBuilder<String?>(
      future: _future,
      builder: (_, snap) => snap.data == null ? fallback : photo(snap.data!),
    );
  }
}
