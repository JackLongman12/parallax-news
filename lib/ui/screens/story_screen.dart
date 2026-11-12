import 'package:flutter/material.dart';

import '../../models/article.dart';
import '../../models/bias.dart';
import '../../models/story.dart';
import '../widgets/common.dart';

class StoryScreen extends StatelessWidget {
  const StoryScreen({super.key, required this.story});
  final Story story;

  @override
  Widget build(BuildContext context) {
    final dist = story.distribution;
    final all = story.uniqueSources;
    List<Article> bySide(Side? side) => all.where((a) => a.source?.bias.side == side).toList();
    final tabs = <(String, List<Article>)>[
      ('All (${all.length})', all),
      ('Left (${dist.left})', bySide(Side.left)),
      ('Center (${dist.center})', bySide(Side.center)),
      ('Right (${dist.right})', bySide(Side.right)),
      if (dist.unrated > 0) ('Unrated (${dist.unrated})', bySide(null)),
    ];
    final blind = dist.blindspotFor;
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(title: Text(story.category.label)),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(story.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('${all.length} sources · updated ${timeAgo(story.latest)}',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 14),
                  BiasBar(dist: dist, height: 12, showLabels: true),
                  if (blind != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Colors.orange.withValues(alpha: 0.12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Blindspot: few ${blind.label.toLowerCase()}-leaning outlets are covering this story. '
                          'Readers who rely on ${blind.label.toLowerCase()} media may not see it.',
                        ),
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
            SliverPersistentHeader(pinned: true, delegate: _TabHeader(TabBar(isScrollable: true, tabs: [for (final t in tabs) Tab(text: t.$1)]))),
          ],
          body: TabBarView(children: [
            for (final t in tabs)
              t.$2.isEmpty
                  ? const EmptyOrError(message: 'No sources from this side covered the story.')
                  : ListView.separated(
                      itemCount: t.$2.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => ArticleTile(article: t.$2[i]),
                    ),
          ]),
        ),
      ),
    );
  }
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
