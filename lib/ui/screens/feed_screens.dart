import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/subtopics.dart';
import '../../models/bias.dart';
import '../../models/category.dart';
import '../../models/story.dart';
import '../../services/cover_images.dart';
import '../../services/curator.dart';
import '../../services/repository.dart';
import '../../models/place.dart';
import '../../services/home_widgets.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../nav.dart';
import '../widgets/common.dart';
import '../widgets/daily_overview.dart';
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
    // Load-as-you-scroll (like IG / TikTok): the first batch is World + your
    // first 3 topics; each further page brings one more place or topic.
    final later = <Future<NewsBundle> Function()>[
      for (final p in app.followed) () => app.repo.place(p),
      for (final c in app.followedTopics.skip(3)) () => app.repo.topic(c),
      for (final c in extra) () => app.repo.topic(c),
    ];
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
          places: const [],
          topics: app.followedTopics.take(3).toList(),
          profile: app.profile,
          force: force,
        )) {
          // "How should we keep you informed?": drop stories below the chosen depth.
          final kept = app.applyInformLevel(stories);
          last = kept;
          yield kept;
        }
        if (last != null && last.isNotEmpty) {
          app.saveSnapshot(last);
          unawaited(HomeWidgets.publish(last));
        }
      },
      onLoadMore: (page) async {
        if (page >= later.length) return <Story>[];
        final b = await later[page]();
        return app.applyInformLevel(Curator.rank(b.stories, app.profile, limit: 30));
      },
      header: header,
    );
  }
}

/// Topics: a photo grid. Your topics first, then everything else.
/// Tap a tile to read it; follow / mute from the topic page.
/// Topics, shown inside Explore: suggested niches, your topics, and the rest.
class TopicsSection extends StatelessWidget {
  const TopicsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final all = Category.values.where((c) => c != Category.general && c != Category.local).toList();
    final mine = all.where(app.followsTopic).toList();
    final rest = all.where((c) => !app.followsTopic(c)).toList();
    Widget header(String t, [Widget? trailing]) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 8, 10),
          child: Row(children: [
            Expanded(child: Text(t, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
            if (trailing != null) trailing,
          ]),
        );
    Widget grid(List<Category> cats) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.45,
            children: [for (final c in cats) TopicTile(category: c)],
          ),
        );
    final forYou = SubtopicSuggester.forYou(app.profile);
    final breakOut = SubtopicSuggester.breakOut(app.profile);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (forYou.isNotEmpty) ...[header('Picked for you'), SubPathChips(paths: forYou, max: 4)],
      header('Outside your bubble'),
      SubPathChips(paths: breakOut, icon: Icons.explore_rounded, max: 4),
      if (mine.isNotEmpty) ...[
        header('Your topics',
            TextButton.icon(icon: const Icon(Icons.tune_rounded, size: 18), label: const Text('Edit'), onPressed: () => showFeedEditor(context))),
        grid(mine),
      ],
      header(mine.isEmpty ? 'Pick topics you like' : 'More topics'),
      grid(rest),
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
  late final Future<String?> _img = Future.value(CoverImages.liveFor(widget.category, DateTime.now().day));

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
            // Bundled photo shows instantly; a fresh one replaces it if found.
            builder: (context, snap) => snap.data == null ? TopicPhoto(c, width: 600) : NetImage(snap.data!, width: 600),
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
        Expanded(
          child: StoryList(
            key: ValueKey('tp:${category.name}:${path?.leaf.label ?? ''}'),
            loader: (force) async {
              final bundle = path == null
                  ? await app.repo.topic(category, force: force)
                  : await app.repo.subtopic(path, force: force);
              final stories = path == null
                  ? await app.repo.withCrawler(bundle.stories, category: category, force: force)
                  : bundle.stories;
              return Curator.rank(stories, app.profile, limit: 80);
            },
          ),
        ),
      ]),
    );
  }
}

/// Chips for a list of subtopic paths; tap opens the topic page on it.
class SubPathChips extends StatelessWidget {
  const SubPathChips({super.key, required this.paths, this.icon, this.max = 100});
  final List<SubPath> paths;
  final IconData? icon;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    // Wraps onto several lines: everything visible, no sideways scrolling.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final sp in paths.take(max))
          ActionChip(
            avatar: Icon(icon ?? Brand.categoryIcon(sp.category), size: 16, color: Brand.purple),
            label: Text(sp.chain.map((s) => s.label).join(' > '),
                style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => TopicPage(category: sp.category, initial: sp))),
          ),
      ]),
    );
  }
}

/// One collection of stories (blindspots, underreported, ...).
class _Collection {
  const _Collection(this.id, this.title, this.blurb, this.tint);
  final String id;
  final String title;
  final String blurb;
  final Color tint;
}

final _collections = <_Collection>[
  const _Collection('blindspot', 'Blindspots', 'Stories one side of the spectrum barely covers', Brand.purple),
  const _Collection('underreported', 'Underreported', 'Few outlets, reliable sources', Color(0xFF15131C)),
  const _Collection('divergent', 'Divergent takes', 'Left and right cover it equally: compare the framing', Color(0xFF4A2A8C)),
];

bool _inCollection(String id, Story s) {
  final d = s.distribution;
  switch (id) {
    case 'blindspot':
      return d.blindspotFor != null;
    case 'underreported':
      final n = s.uniqueSources.length;
      final good = s.uniqueSources
          .where((a) => a.source?.factuality == Factuality.high || a.source?.factuality == Factuality.veryHigh)
          .length;
      return n >= 2 && n <= 5 && good >= 1;
    case 'divergent':
      return d.divergent;
  }
  return false;
}

List<Story> _storiesIn(String id, List<Story> all) => all.where((s) => _inCollection(id, s)).toList()
  ..sort((a, b) => b.uniqueSources.length.compareTo(a.uniqueSources.length));

/// Blindspot tab: one screen, no scrolling. A big Blindspots tile on top and
/// two smaller ones below, each showing the photo of its top story, how many
/// stories it holds and their combined left/center/right coverage.
class BlindspotScreen extends StatefulWidget {
  const BlindspotScreen({super.key});

  @override
  State<BlindspotScreen> createState() => _BlindspotScreenState();
}

class _BlindspotScreenState extends State<BlindspotScreen> {
  Map<String, List<Story>>? _groups;
  Timer? _retry;
  int _tries = 0;

  @override
  void initState() {
    super.initState();
    TabReselect.tabs[2].addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    TabReselect.tabs[2].removeListener(_reload);
    _retry?.cancel();
    super.dispose();
  }

  void _reload() => _load(force: true);

  Future<void> _load({bool force = false}) async {
    final app = context.read<AppState>();
    try {
      final all = await app.repo.broadPool(places: app.followed, topics: app.followedTopics, force: force);
      if (!mounted) return;
      final groups = {for (final c in _collections) c.id: _storiesIn(c.id, all)};
      setState(() => _groups = groups);
      // Opened before the news finished loading (e.g. straight after app
      // start)? Try again shortly instead of showing empty tiles.
      if (groups.values.every((g) => g.isEmpty)) _scheduleRetry();
    } catch (_) {
      if (mounted) setState(() => _groups ??= const {});
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_tries >= 4) return;
    _tries++;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: 4 * _tries), () => _load(force: _tries > 2));
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context).bottom;
    Widget tile(int i, {bool big = false}) => _CollectionTile(
          c: _collections[i],
          stories: _groups?[_collections[i].id],
          loading: _groups == null,
          big: big,
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 6, 12, 12 + pad),
      child: Column(children: [
        Expanded(flex: 6, child: tile(0, big: true)),
        const SizedBox(height: 10),
        Expanded(flex: 4, child: Row(children: [Expanded(child: tile(1)), const SizedBox(width: 10), Expanded(child: tile(2))])),
      ]),
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({required this.c, required this.stories, required this.loading, this.big = false});
  final _Collection c;
  final List<Story>? stories;
  final bool loading;
  final bool big;

  String? get _photo {
    for (final s in stories ?? const <Story>[]) {
      final u = s.imageUrl;
      if (u != null && !CoverImages.isWikimediaHost(Uri.tryParse(u)?.host)) return u;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final list = stories ?? const <Story>[];
    var l = 0, ce = 0, r = 0;
    for (final s in list) {
      final d = s.distribution;
      l += d.left;
      ce += d.center;
      r += d.right;
    }
    final photo = _photo;
    final count = loading
        ? ' '
        : list.isEmpty
            ? 'None right now'
            : '${list.length} ${list.length == 1 ? 'story' : 'stories'}';
    return Material(
      color: c.tint,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // The page shows exactly the stories counted on this tile.
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CollectionPage(c: c, stories: stories))),
        child: Stack(fit: StackFit.expand, children: [
          if (photo != null) NetImage(photo, width: big ? 900 : 500),
          // Tint + darkening toward the text so it stays readable on any photo.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: photo == null
                    ? [c.tint, Color.lerp(c.tint, Colors.black, 0.45)!]
                    : [c.tint.withValues(alpha: 0.35), Colors.black.withValues(alpha: 0.85)],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(big ? 18 : 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(count.toUpperCase(),
                  style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const Spacer(),
              Text(c.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: big ? 28 : 17,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4)),
              if (big) ...[
                const SizedBox(height: 4),
                Text(c.blurb,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 13)),
              ],
              if (l + ce + r > 0) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 5,
                    child: Row(children: [
                      if (l > 0) Expanded(flex: l, child: ColoredBox(color: Side.left.color)),
                      if (ce > 0) Expanded(flex: ce, child: const ColoredBox(color: Color(0xFFE6E1F0))),
                      if (r > 0) Expanded(flex: r, child: ColoredBox(color: Side.right.color)),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key, required this.c, this.stories});
  final _Collection c;

  /// What the tile counted. Pull-to-refresh rebuilds the list from fresh news.
  final List<Story>? stories;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(c.title)),
      body: StoryList(
        initial: stories,
        loader: (force) async => !force && stories != null && stories!.isNotEmpty
            ? stories!
            : _storiesIn(c.id, await app.repo.broadPool(places: app.followed, topics: app.followedTopics, force: force)),
        emptyMessage: 'Nothing here right now. More outlets get rated as you browse, so check back later.',
        header: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(c.blurb, style: Theme.of(context).textTheme.bodySmall),
        ),
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
                ? Future.value(CoverImages.liveFor(Category.world, DateTime.now().day))
                : CoverImages.placeImage(p.name, p.id),
          ),
          'p:${p.id}',
          () => toggle('p:${p.id}'),
          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaceScreen(place: p))),
        ),
      for (final c in app.followedTopics)
        (
          c.label,
          _RingPhoto(icon: Brand.categoryIcon(c), image: photo('topic:${c.name}'), fetch: () => Future.value(CoverImages.liveFor(c, DateTime.now().day))),
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
    // The full feed starts straight with stories (Customize is in the app
    // bar); a title row appears only when filtered to one place or topic.
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (selected != null) Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
        child: Row(children: [
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
          ),
          TextButton(onPressed: () => select(null), child: const Text('Show all')),
        ]),
      ),
      const SizedBox(height: 4),
      if (selected == null && app.informLevel != 'off') const DailyOverview(),
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
