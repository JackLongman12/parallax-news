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
  late final Future<String?> _img = Future.value(CoverImages.variantFor(widget.category, DateTime.now().day));

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
        if (path == null && (category == Category.business || category == Category.finance)) const MarketsStrip(),
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

/// One collection of stories (blindspots, underreported, ...).
class _Collection {
  const _Collection(this.id, this.title, this.blurb, this.colors, this.art);
  final String id;
  final String title;
  final String blurb;
  final List<Color> colors;
  final CustomPainter Function() art;
}

final _collections = <_Collection>[
  _Collection('blindspot', 'Blindspots', 'Stories one side of the spectrum barely covers',
      [const Color(0xFF3B1E8C), Brand.purple], () => _BlindspotArt()),
  _Collection('underreported', 'Underreported', 'Few outlets, reliable sources',
      [const Color(0xFF1D1B26), const Color(0xFF3A3550)], () => _UnderreportedArt()),
  _Collection('divergent', 'Divergent takes', 'Left and right both cover it: compare the framing',
      [const Color(0xFF2B2F7A), const Color(0xFF7A2B4F)], () => _DivergentArt()),
  _Collection('left', 'Popular with the left', 'Mostly covered by left-leaning outlets',
      [const Color(0xFF1E2F9E), const Color(0xFF3F5BEA)], () => _SideArt(Side.left)),
  _Collection('right', 'Popular with the right', 'Mostly covered by right-leaning outlets',
      [const Color(0xFF8C1430), const Color(0xFFE0406A)], () => _SideArt(Side.right)),
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
    case 'left':
      return d.rated >= 3 && d.share(Side.left) >= 0.6;
    case 'right':
      return d.rated >= 3 && d.share(Side.right) >= 0.6;
  }
  return false;
}

/// Blindspot tab: big illustrated tiles, one per collection.
class BlindspotScreen extends StatelessWidget {
  const BlindspotScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ReselectScroll(
      tab: 4,
      builder: (ctrl) => ListView(
        controller: ctrl,
        padding: EdgeInsets.fromLTRB(14, 8, 14, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          for (final c in _collections) ...[
            _CollectionTile(c: c),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({required this.c});
  final _Collection c;

  @override
  Widget build(BuildContext context) => Material(
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CollectionPage(c: c))),
          child: Ink(
            height: 132,
            decoration: BoxDecoration(gradient: LinearGradient(colors: c.colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
            child: Stack(children: [
              Positioned(right: 0, top: 0, bottom: 0, width: 150, child: CustomPaint(painter: c.art())),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 150, 18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(c.title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  const SizedBox(height: 6),
                  Text(c.blurb, maxLines: 2, style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 13, height: 1.3)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key, required this.c});
  final _Collection c;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(c.title)),
      body: StoryList(
        loader: (force) async {
          final all = await app.repo.broadPool(places: app.followed, topics: app.followedTopics, force: force);
          return all.where((s) => _inCollection(c.id, s)).toList()
            ..sort((a, b) => b.uniqueSources.length.compareTo(a.uniqueSources.length));
        },
        emptyMessage: 'Nothing here right now. More outlets get rated as you browse, so check back later.',
        header: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(c.blurb, style: Theme.of(context).textTheme.bodySmall),
        ),
      ),
    );
  }
}

// ---- Illustrations (drawn in code: crisp, tiny, no image files) ----

/// An eye with a slash over a lopsided left/right bar.
class _BlindspotArt extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final cx = s.width * 0.5, cy = s.height * 0.42;
    final eye = Path()
      ..moveTo(cx - 44, cy)
      ..quadraticBezierTo(cx, cy - 34, cx + 44, cy)
      ..quadraticBezierTo(cx, cy + 34, cx - 44, cy);
    canvas.drawPath(eye, w);
    canvas.drawCircle(Offset(cx, cy), 11, Paint()..color = Colors.white.withValues(alpha: 0.9));
    canvas.drawLine(Offset(cx - 40, cy + 32), Offset(cx + 40, cy - 32), w..strokeWidth = 6);
    final bar = RRect.fromLTRBR(cx - 50, s.height * 0.78, cx + 50, s.height * 0.78 + 10, const Radius.circular(5));
    canvas.save();
    canvas.clipRRect(bar);
    canvas.drawRect(Rect.fromLTWH(cx - 50, bar.top, 10, 10), Paint()..color = Side.left.color);
    canvas.drawRect(Rect.fromLTWH(cx - 40, bar.top, 90, 10), Paint()..color = Side.right.color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// A tiny spotlight on a single small bar among tall empty ones.
class _UnderreportedArt extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final faint = Paint()..color = Colors.white.withValues(alpha: 0.12);
    final bright = Paint()..color = const Color(0xFFFFD166);
    final base = s.height * 0.82;
    final xs = [s.width * 0.18, s.width * 0.38, s.width * 0.58, s.width * 0.78];
    final hs = [70.0, 55.0, 16.0, 62.0];
    for (var i = 0; i < 4; i++) {
      final rect = RRect.fromLTRBR(xs[i] - 10, base - hs[i], xs[i] + 10, base, const Radius.circular(6));
      canvas.drawRRect(rect, i == 2 ? bright : faint);
    }
    final beam = Path()
      ..moveTo(xs[2] - 6, s.height * 0.08)
      ..lineTo(xs[2] - 26, base - 18)
      ..lineTo(xs[2] + 26, base - 18)
      ..lineTo(xs[2] + 6, s.height * 0.08)
      ..close();
    canvas.drawPath(beam, Paint()..color = const Color(0xFFFFD166).withValues(alpha: 0.18));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Two arrows leaving one point in opposite directions (blue / red).
class _DivergentArt extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final o = Offset(s.width * 0.5, s.height * 0.78);
    void arrow(Offset to, Color c) {
      final p = Paint()
        ..color = c
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(o, to, p);
      final dir = (to - o) / (to - o).distance;
      final n = Offset(-dir.dy, dir.dx);
      final head = Path()
        ..moveTo(to.dx + dir.dx * 10, to.dy + dir.dy * 10)
        ..lineTo(to.dx - dir.dx * 8 + n.dx * 11, to.dy - dir.dy * 8 + n.dy * 11)
        ..lineTo(to.dx - dir.dx * 8 - n.dx * 11, to.dy - dir.dy * 8 - n.dy * 11)
        ..close();
      canvas.drawPath(head, Paint()..color = c);
    }

    arrow(Offset(s.width * 0.2, s.height * 0.22), const Color(0xFF7D93FF));
    arrow(Offset(s.width * 0.8, s.height * 0.22), const Color(0xFFFF8FA8));
    canvas.drawCircle(o, 8, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Stacked "outlet" bubbles tilted to one side.
class _SideArt extends CustomPainter {
  _SideArt(this.side);
  final Side side;

  @override
  void paint(Canvas canvas, Size s) {
    final light = Paint()..color = Colors.white.withValues(alpha: 0.85);
    final faint = Paint()..color = Colors.white.withValues(alpha: 0.18);
    final left = side == Side.left;
    for (var row = 0; row < 3; row++) {
      for (var i = 0; i < 4; i++) {
        final x = s.width * (0.2 + i * 0.2);
        final y = s.height * (0.28 + row * 0.24);
        final onSide = left ? i < 3 : i > 0;
        canvas.drawCircle(Offset(x, y), 11, onSide ? light : faint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SideArt old) => old.side != side;
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
                ? Future.value(CoverImages.variantFor(Category.world, DateTime.now().day))
                : CoverImages.placeImage(p.name, p.id),
          ),
          'p:${p.id}',
          () => toggle('p:${p.id}'),
          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaceScreen(place: p))),
        ),
      for (final c in app.followedTopics)
        (
          c.label,
          _RingPhoto(icon: Brand.categoryIcon(c), image: photo('topic:${c.name}'), fetch: () => Future.value(CoverImages.variantFor(c, DateTime.now().day))),
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
