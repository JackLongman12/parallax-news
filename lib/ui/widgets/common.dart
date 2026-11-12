import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/article.dart';
import '../../models/bias.dart';
import '../../models/source.dart';
import '../../models/story.dart';
import '../../services/net.dart';
import '../../state/app_state.dart';
import '../screens/story_screen.dart';

String timeAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().toUtc().difference(t.toUtc());
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

Future<void> openArticle(BuildContext context, String url) async {
  if (!isSafeWebUrl(url)) return;
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link')));
  }
}

/// Horizontal bar showing the Left / Center / Right share of coverage.
class BiasBar extends StatelessWidget {
  const BiasBar({super.key, required this.dist, this.height = 8, this.showLabels = false});
  final BiasDistribution dist;
  final double height;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[];
    void seg(int n, Color c) {
      if (n > 0) segments.add(Expanded(flex: n, child: Container(color: c)));
    }

    if (dist.rated == 0) {
      seg(1, Bias.unrated.color);
    } else {
      seg(dist.left, Side.left.color);
      seg(dist.center, Side.center.color);
      seg(dist.right, Side.right.color);
    }
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(height: height, child: Row(children: segments)),
    );
    if (!showLabels) return bar;
    final pct = (Side s) => '${(dist.share(s) * 100).round()}%';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      bar,
      const SizedBox(height: 6),
      Row(children: [
        Text('Left ${pct(Side.left)}', style: TextStyle(color: Side.left.color, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('Center ${pct(Side.center)}', style: TextStyle(color: Side.center.color, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('Right ${pct(Side.right)}', style: TextStyle(color: Side.right.color, fontWeight: FontWeight.w600)),
      ]),
      if (dist.unrated > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${dist.unrated} unrated source${dist.unrated == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall),
        ),
    ]);
  }
}

class BiasChip extends StatelessWidget {
  const BiasChip({super.key, required this.source, this.dense = true});
  final SourceInfo source;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final b = source.bias;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: b.color.withValues(alpha: 0.15),
        border: Border.all(color: b.color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        b.label + (source.origin == RatingOrigin.wikidata ? ' · WD' : '') + (source.origin == RatingOrigin.userOverride ? ' · you' : ''),
        style: TextStyle(fontSize: dense ? 11 : 13, color: b == Bias.unrated ? null : b.color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.secondary;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
    );
  }
}

class StoryCard extends StatelessWidget {
  const StoryCard({super.key, required this.story});
  final Story story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dist = story.distribution;
    final sources = story.uniqueSources;
    final lite = context.select<AppState, bool>((s) => s.settings.lite);
    final img = lite ? null : story.imageUrl;
    final blind = dist.blindspotFor;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          context.read<AppState>().recordOpen(story);
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StoryScreen(story: story)));
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Tag(story.category.label),
              if (story.hasLocal) Tag('Local', color: Colors.teal),
              if (blind != null) Tag('Blindspot · ${blind.label}', color: Colors.orange),
              const Spacer(),
              Text(timeAgo(story.latest), style: theme.textTheme.bodySmall),
            ]),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(story.title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (img != null) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(img,
                      width: 84,
                      height: 64,
                      fit: BoxFit.cover,
                      cacheWidth: 168,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
              ],
            ]),
            const SizedBox(height: 10),
            BiasBar(dist: dist),
            const SizedBox(height: 6),
            Text(
              '${sources.length} source${sources.length == 1 ? '' : 's'} · '
              '${sources.take(3).map((a) => a.sourceName).join(', ')}${sources.length > 3 ? '…' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ]),
        ),
      ),
    );
  }
}

class ArticleTile extends StatelessWidget {
  const ArticleTile({super.key, required this.article});
  final Article article;

  @override
  Widget build(BuildContext context) {
    final s = article.source;
    return ListTile(
      title: Text(article.title, maxLines: 3, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(article.sourceName, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (s != null) BiasChip(source: s),
          if (article.isLocal) const Tag('Local', color: Colors.teal),
          if (s?.stateAffiliated ?? false) const Tag('State-affiliated', color: Colors.deepOrange),
          Text(timeAgo(article.published)),
        ]),
      ),
      onTap: () => openArticle(context, article.url),
    );
  }
}

class EmptyOrError extends StatelessWidget {
  const EmptyOrError({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ]
          ]),
        ),
      );
}
