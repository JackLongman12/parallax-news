import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/article.dart';
import '../../models/bias.dart';
import '../../models/source.dart';
import '../../models/story.dart';
import '../../services/net.dart';
import '../../state/app_state.dart';
import '../screens/story_screen.dart';
import '../theme.dart';

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

  void _open(BuildContext context) {
    context.read<AppState>().recordOpen(story);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StoryScreen(story: story)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dist = story.distribution;
    final sources = story.uniqueSources;
    final lite = context.select<AppState, bool>((s) => s.settings.lite);
    final img = lite ? null : story.imageUrl;
    final blind = dist.blindspotFor;

    // Hero: photo with a dark scrim, or a category gradient "post".
    final hero = SizedBox(
      height: lite ? 150 : 190,
      child: Stack(fit: StackFit.expand, children: [
        ColoredBox(color: theme.brightness == Brightness.dark ? Brand.deep : Brand.purple),
        if (img == null)
          Positioned(
            right: -18,
            bottom: -24,
            child: Icon(Brand.categoryIcon(story.category), size: 150, color: Colors.white.withValues(alpha: 0.10)),
          ),
        if (img != null)
          Image.network(img, fit: BoxFit.cover, cacheWidth: 720, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        if (img != null)
          const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x22000000), Color(0xB3000000)],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 14,
          child: Row(children: [
            _Pill(icon: Brand.categoryIcon(story.category), text: story.category.label),
            if (story.hasLocal) const _Pill(icon: Icons.place, text: 'Local'),
            const Spacer(),
            Text(timeAgo(story.latest),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 14,
          child: Text(
            story.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 19, height: 1.2, fontWeight: FontWeight.w800),
          ),
        ),
      ]),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Material(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        elevation: 3,
        shadowColor: Brand.purple.withValues(alpha: 0.25),
        child: InkWell(
          onTap: () => _open(context),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            hero,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (blind != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      const Icon(Icons.visibility_off, size: 15, color: Brand.red),
                      const SizedBox(width: 6),
                      Text('Blindspot · barely covered by the ${blind.label.toLowerCase()}',
                          style: const TextStyle(color: Brand.red, fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: BiasBar(dist: dist, height: 8),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  SourceAvatars(articles: sources),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${sources.length} source${sources.length == 1 ? '' : 's'} · ${_split(dist)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Share',
                    icon: const Icon(Icons.ios_share, size: 20),
                    onPressed: () => SharePlus.instance.share(ShareParams(
                        text: '${story.title}\n${story.lead.url}\n\nCompare coverage on Parallax News')),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  static String _split(BiasDistribution d) {
    if (d.rated == 0) return 'not yet rated';
    String p(Side s) => '${(d.share(s) * 100).round()}%';
    return 'L ${p(Side.left)} · C ${p(Side.center)} · R ${p(Side.right)}';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Overlapping outlet "avatars", ringed in each outlet's bias colour.
class SourceAvatars extends StatelessWidget {
  const SourceAvatars({super.key, required this.articles, this.max = 5});
  final List<Article> articles;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = articles.take(max).toList();
    const size = 26.0;
    return SizedBox(
      width: size + (shown.length - 1).clamp(0, max) * 17.0,
      height: size,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++)
          Positioned(
            left: i * 17.0,
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (shown[i].source?.bias ?? Bias.unrated).color,
                border: Border.all(color: Theme.of(context).cardTheme.color ?? Colors.white, width: 2),
              ),
              child: Text(
                shown[i].sourceName.isEmpty ? '?' : shown[i].sourceName.characters.first.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          ),
      ]),
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
          if (article.isLocal) const Tag('Local', color: Brand.purple),
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
