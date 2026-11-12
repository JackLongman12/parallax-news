import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/article.dart';
import '../../models/bias.dart';
import '../../models/story.dart';
import '../../services/cover_images.dart';
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
    final tabs = <(String, List<Article>?)>[
      ('All (${all.length})', all),
      ('Left (${dist.left})', bySide(Side.left)),
      ('Center (${dist.center})', bySide(Side.center)),
      ('Right (${dist.right})', bySide(Side.right)),
      if (dist.unrated > 0) ('Unrated (${dist.unrated})', bySide(null)),
      ('Related', null),
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
                  if (story.lead.snippet.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(story.lead.snippet),
                  ],
                ]),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabHeader(TabBar(isScrollable: true, tabs: [for (final t in tabs) Tab(text: t.$1)])),
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
              Image.network(img, fit: BoxFit.cover, cacheWidth: 1080, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
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
