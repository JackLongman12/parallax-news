import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/article.dart';
import '../../models/bias.dart';
import '../../models/story.dart';
import '../../services/cover_images.dart';
import '../../services/summarizer.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key, required this.story});
  final Story story;

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  final _watch = Stopwatch()..start();
  late final AppState _app;
  late final Future<List<Story>> _related = _app.repo.related(widget.story, _app.profile);
  late final Future<String?> _cover = CoverImages.forStory(widget.story);
  late final StorySummary _summary = Summarizer.summarize(widget.story);

  Story get story => widget.story;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
  }

  @override
  void dispose() {
    // Reading time is one of the strongest interest signals.
    _app.recordDwell(story, _watch.elapsed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dist = story.distribution;
    final all = story.uniqueSources;
    List<Article> bySide(Side? side) => all.where((a) => a.source?.bias.side == side).toList();
    // Short labels so every tab fits on screen without swiping.
    final tabs = <(String, List<Article>?)>[
      ('All ${all.length}', all),
      ('Left ${dist.left}', bySide(Side.left)),
      ('Ctr ${dist.center}', bySide(Side.center)),
      ('Right ${dist.right}', bySide(Side.right)),
      if (dist.unrated > 0) ('N/R ${dist.unrated}', bySide(null)),
      ('More', null),
    ];
    final blind = dist.blindspotFor;

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 300,
              backgroundColor: Brand.black,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.thumb_up_alt_outlined),
                  tooltip: 'More like this',
                  onPressed: () {
                    _app.moreLikeThis(story);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Got it — more stories like this')));
                  },
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(background: _hero()),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${all.length} sources · updated ${timeAgo(story.latest)}', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 10),
                  BiasBar(dist: dist, height: 12, showLabels: true),
                  if (blind != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Brand.purple.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'Blindspot: few ${blind.label.toLowerCase()}-leaning outlets are covering this story. '
                        'Readers who rely on ${blind.label.toLowerCase()} media may not see it.',
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SummaryCard(summary: _summary),
                ]),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabHeader(TabBar(
                isScrollable: false,
                labelPadding: EdgeInsets.zero,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                tabs: [for (final t in tabs) Tab(child: FittedBox(fit: BoxFit.scaleDown, child: Text(t.$1)))],
              )),
            ),
          ],
          body: TabBarView(children: [
            for (final t in tabs)
              if (t.$2 == null)
                _relatedTab()
              else if (t.$2!.isEmpty)
                const EmptyOrError(message: 'No outlets from this side covered the story.')
              else
                ListView.separated(
                  itemCount: t.$2!.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => ArticleTile(
                    article: t.$2![i],
                    onOpen: () => _app.recordClickThrough(story, t.$2![i]),
                  ),
                ),
          ]),
        ),
      ),
    );
  }

  /// Cover image with the headline over it (same look as the feed card).
  Widget _hero() => FutureBuilder<String?>(
        future: _cover,
        initialData: CoverImages.cached(story),
        builder: (context, snap) {
          final img = snap.data;
          return Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Brand.purple),
            if (img == null)
              Positioned(
                right: -20,
                bottom: -20,
                child: Icon(Brand.categoryIcon(story.category), size: 190, color: Colors.white.withValues(alpha: 0.10)),
              ),
            if (img != null)
              Image.network(img, fit: BoxFit.cover, cacheWidth: decodeWidth(context), errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            if (img != null && CoverImages.needsCredit(img))
              const Positioned(
                right: 10,
                bottom: 4,
                child: Text('Photo: Wikimedia Commons', style: TextStyle(color: Colors.white70, fontSize: 9)),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x66000000), Color(0x11000000), Color(0xD0000000)],
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Brand.categoryIcon(story.category), size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(story.category.label,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(height: 10),
                Text(
                  story.title,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 23, height: 1.2, fontWeight: FontWeight.w800),
                ),
              ]),
            ),
          ]);
        },
      );

  Widget _relatedTab() => FutureBuilder<List<Story>>(
        future: _related,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final list = snap.data ?? const [];
          if (list.isEmpty) return const EmptyOrError(message: 'No related stories yet.');
          return ListView.builder(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            itemCount: list.length,
            itemBuilder: (_, i) => StoryCard(story: list[i]),
          );
        },
      );
}

class _TabHeader extends SliverPersistentHeaderDelegate {
  _TabHeader(this.bar);
  final TabBar bar;

  @override
  double get minExtent => bar.preferredSize.height;
  @override
  double get maxExtent => bar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Material(color: Theme.of(context).scaffoldBackgroundColor, child: bar);

  @override
  bool shouldRebuild(covariant _TabHeader old) => old.bar != bar;
}

/// TL;DR: extracted (never generated) key points, each attributed to its
/// outlet, plus how each side of the spectrum headlined the story.
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.summary});
  final StorySummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    Widget sourceTag(Article a) {
      final b = a.source?.bias ?? Bias.unrated;
      return Text(' — ${a.sourceName}${b == Bias.unrated ? '' : ' (${b.label})'}',
          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: b == Bias.unrated ? null : b.color));
    }

    const sides = [Side.left, Side.center, Side.right, null];
    final framing = [for (final s in sides) if (summary.framing[s] != null) (s, summary.framing[s]!)];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.purple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.purple.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bolt, size: 18, color: Brand.purple),
          const SizedBox(width: 6),
          Text('TL;DR', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 8),
        for (final p in summary.points)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('•  ', style: TextStyle(fontWeight: FontWeight.w900)),
              Expanded(child: Text.rich(TextSpan(children: [TextSpan(text: p.text), WidgetSpan(child: sourceTag(p.article))]))),
            ]),
          ),
        if (framing.length >= 2) ...[
          if (summary.points.isNotEmpty) const Divider(),
          Text('How each side headlined it', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final f in framing)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 52,
                  margin: const EdgeInsets.only(right: 8, top: 2),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (f.$1?.color ?? Bias.unrated.color).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(f.$1?.label ?? 'N/R',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: f.$1?.color)),
                ),
                Expanded(child: Text.rich(TextSpan(children: [TextSpan(text: f.$2.title), WidgetSpan(child: sourceTag(f.$2))]))),
              ]),
            ),
        ],
        const SizedBox(height: 4),
        Text('Auto-extracted from ${summary.outlets} outlets — quotes their own words, never rewritten. '
            'Read the full coverage below for every detail.',
            style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
      ]),
    );
  }
}
