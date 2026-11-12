import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/article.dart';
import '../../models/bias.dart';
import '../../models/category.dart';
import '../../models/source.dart';
import '../../models/story.dart';
import '../../services/cover_images.dart';
import '../../services/net.dart';
import '../../state/app_state.dart';
import '../screens/sources_screen.dart';
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

/// Network image with a persistent disk cache (instant on later launches),
/// a quick fade-in and silent failure.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.width, this.fit = BoxFit.cover, this.fallback});
  final String url;

  /// Shown if the image fails to load (so nothing is ever left blank).
  final Widget? fallback;
  final int? width;
  final BoxFit fit;

  /// Off in widget tests (no disk cache there): shows [fallback] instead.
  static bool enabled = true;

  @override
  Widget build(BuildContext context) => !enabled
      ? (fallback ?? const SizedBox.shrink())
      : CachedNetworkImage(
        imageUrl: url,
        cacheManager: ImageCacheStore.instance,
        fit: fit,
        memCacheWidth: width,
        fadeInDuration: const Duration(milliseconds: 220),
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => fallback ?? const SizedBox.shrink(),
      );
}

/// Disk cache for images. Limited by count (100 photos, 3 days) AND by total
/// size: [trim] keeps the folder under [maxBytes] by deleting the oldest
/// files first (the cache simply re-downloads anything it later needs).
class ImageCacheStore {
  static const key = 'parallaxImages';
  static const maxBytes = 40 * 1024 * 1024;

  static final CacheManager instance = CacheManager(Config(
    key,
    stalePeriod: const Duration(days: 3),
    maxNrOfCacheObjects: 100,
  ));

  static Future<Directory?> _dir() async {
    try {
      final d = Directory('${(await getTemporaryDirectory()).path}/$key');
      return await d.exists() ? d : null;
    } catch (_) {
      return null;
    }
  }

  /// Current size of the image cache in bytes.
  static Future<int> size() async {
    final d = await _dir();
    if (d == null) return 0;
    var total = 0;
    try {
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  static bool _trimming = false;

  /// Deletes the oldest cached photos until the cache is under [maxBytes].
  static Future<void> trim({int limit = maxBytes}) async {
    if (_trimming) return;
    _trimming = true;
    try {
      final d = await _dir();
      if (d == null) return;
      final files = <(File, int, DateTime)>[];
      var total = 0;
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final st = await e.stat();
        files.add((e, st.size, st.modified));
        total += st.size;
      }
      if (total <= limit) return;
      files.sort((a, b) => a.$3.compareTo(b.$3)); // oldest first
      for (final f in files) {
        if (total <= limit * 0.8) break; // trim a bit below the cap
        try {
          await f.$1.delete();
          total -= f.$2;
        } catch (_) {}
      }
    } catch (_) {
    } finally {
      _trimming = false;
    }
  }

  static Future<void> clear() async {
    await instance.emptyCache();
    PaintingBinding.instance.imageCache.clear();
  }
}

/// Bundled default photo for a topic (always available, even offline).
/// Falls back to the plain brand colour if a topic has no bundled photo.
class TopicPhoto extends StatelessWidget {
  const TopicPhoto(this.category, {super.key, this.width});
  final Category category;
  final int? width;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/topics/${category.name}.jpg',
        fit: BoxFit.cover,
        cacheWidth: width,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/topics/general.jpg',
          fit: BoxFit.cover,
          cacheWidth: width,
          errorBuilder: (_, __, ___) => const ColoredBox(color: Brand.purple),
        ),
      );
}

/// Warm the disk + memory cache for an image before it's on screen.
void prefetchImage(BuildContext context, String url) {
  precacheImage(CachedNetworkImageProvider(url, maxWidth: decodeWidth(context), cacheManager: ImageCacheStore.instance), context,
      onError: (_, __) {});
}

/// Decode images at the real on-screen pixel width (sharp on any phone,
/// without wasting memory on huge originals).
int decodeWidth(BuildContext context) {
  final px = MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context);
  return px.round().clamp(480, 1440);
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

    if (!dist.isReliable) {
      // Not enough rated outlets: neutral bar, no political colour at all.
      seg(1, Bias.unrated.color);
    } else {
      seg(dist.left, Side.left.color);
      seg(dist.center, Side.center.color);
      seg(dist.right, Side.right.color);
      seg(dist.unrated, Bias.unrated.color.withValues(alpha: 0.6));
    }
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(height: height, child: Row(children: segments)),
    );
    if (!showLabels) return bar;
    if (!dist.isReliable) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        bar,
        const SizedBox(height: 6),
        Text('Lean unknown', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).hintColor)),
        Text(
          'Only ${dist.rated} of ${dist.total} outlets covering this are rated, '
          'so no left/right split is shown. Tap an outlet to see or set its rating.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ]);
    }
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
          child: Text('Based on ${dist.rated} rated outlets · ${dist.unrated} unrated (grey)',
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

class StoryCard extends StatefulWidget {
  const StoryCard({super.key, required this.story});
  final Story story;

  @override
  State<StoryCard> createState() => _StoryCardState();
}

class _StoryCardState extends State<StoryCard> {
  Timer? _impression;
  Future<String?>? _cover;

  Story get story => widget.story;

  @override
  void initState() {
    super.initState();
    // Counts as "seen" only if the card stays on screen for a moment.
    _impression = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) context.read<AppState>().recordImpression(story);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lite = context.read<AppState>().settings.lite;
    _cover ??= lite ? Future.value(story.imageUrl) : CoverImages.forStory(story);
  }

  @override
  void dispose() {
    _impression?.cancel();
    super.dispose();
  }

  void _open() {
    _impression?.cancel();
    context.read<AppState>().recordOpen(story);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StoryScreen(story: story)));
  }

  void _up() {
    final app = context.read<AppState>()..thumbsUp(story);
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: const Text('Got it: more like this'),
      action: SnackBarAction(label: 'Undo', onPressed: () => app.undoThumbsUp(story)),
    ));
  }

  void _down() {
    final app = context.read<AppState>()..thumbsDown(story);
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: const Text('Hidden. You will see fewer stories like this'),
      action: SnackBarAction(label: 'Undo', onPressed: () => app.undoThumbsDown(story)),
    ));
  }

  void _share() {
    context.read<AppState>().recordShare(story);
    SharePlus.instance.share(ShareParams(text: '${story.title}\n${story.lead.url}\n\nCompare coverage on Parallax News'));
  }

  void _menu() {
    final app = context.read<AppState>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.thumb_up_alt_outlined),
            title: const Text('More like this'),
            onTap: () {
              app.moreLikeThis(story);
              Navigator.pop(ctx);
              _toast('Got it — more stories like this');
            },
          ),
          ListTile(
            leading: const Icon(Icons.thumb_down_alt_outlined),
            title: const Text('Less like this'),
            onTap: () {
              app.lessLikeThis(story);
              Navigator.pop(ctx);
              _toast('Got it — fewer stories like this');
            },
          ),
          ListTile(
            leading: Icon(app.followsTopic(story.category) ? Icons.star_rounded : Icons.star_border_rounded),
            title: Text(app.followsTopic(story.category)
                ? 'Unfollow ${story.category.label}'
                : 'Follow ${story.category.label}'),
            onTap: () {
              app.toggleTopic(story.category);
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            leading: const Icon(Icons.volume_off_outlined),
            title: Text('Mute ${story.category.label}'),
            onTap: () {
              app.toggleMute(story.category);
              Navigator.pop(ctx);
              _toast('${story.category.label} muted — undo in Customize feed');
            },
          ),
          ListTile(
            leading: const Icon(Icons.block_rounded),
            title: Text('Hide ${story.lead.sourceName}'),
            onTap: () {
              app.toggleHiddenSource(story.lead.domain);
              Navigator.pop(ctx);
              _toast('${story.lead.sourceName} hidden from your feed');
            },
          ),
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: const Text('Share'),
            onTap: () {
              Navigator.pop(ctx);
              _share();
            },
          ),
        ]),
      ),
    );
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final dist = story.distribution;
    final sources = story.uniqueSources;
    final lite = context.select<AppState, bool>((s) => s.settings.lite);
    final blind = dist.blindspotFor;
    final skew = dist.skewedTo;
    const white70 = Color(0xB3FFFFFF);

    Widget signal() {
      if (blind != null) {
        return _Pill(icon: Icons.visibility_off_rounded, text: 'Blindspot · few ${blind.label.toLowerCase()} outlets', color: Brand.red);
      }
      if (skew != null) {
        return _Pill(icon: Icons.balance_rounded, text: 'Mostly ${skew.label.toLowerCase()}-leaning coverage', color: skew.color);
      }
      return const SizedBox.shrink();
    }

    final card = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Material(
        color: Brand.purple,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _open,
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _menu();
          },
          child: SizedBox(
            height: lite ? 250 : 340,
            child: FutureBuilder<String?>(
              future: _cover,
              initialData: CoverImages.quick(story),
              builder: (context, snap) {
                final img = snap.data;
                return Stack(fit: StackFit.expand, children: [
                  if (img == null) TopicPhoto(story.category, width: decodeWidth(context)),
                  if (img != null)
                    NetImage(img, width: decodeWidth(context), fallback: TopicPhoto(story.category, width: decodeWidth(context))),
                  // Scrim: light at the top for the labels, heavy at the bottom for the text.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.3, 0.55, 1],
                        colors: [Color(0x66000000), Color(0x00000000), Color(0x55000000), Color(0xEE000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    top: 14,
                    child: Row(children: [
                      _Pill(icon: Brand.categoryIcon(story.category), text: story.category.label),
                      if (_isBreaking(story))
                        const _Pill(icon: Icons.flash_on_rounded, text: 'Breaking', color: Brand.red)
                      else if (_isTrending(story))
                        const _Pill(icon: Icons.local_fire_department_rounded, text: 'Trending'),
                      if (story.hasLocal) const _Pill(icon: Icons.place_rounded, text: 'Local'),
                      const Spacer(),
                      Text(timeAgo(story.latest),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  if (img != null && CoverImages.needsCredit(img))
                    Positioned(
                      right: 14,
                      top: 44,
                      child: Text('Photo: ${CoverImages.creditFor(img)}', style: const TextStyle(color: white70, fontSize: 9)),
                    ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      signal(),
                      if (blind != null || skew != null) const SizedBox(height: 8),
                      Text(
                        story.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 21, height: 1.18, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 12),
                      BiasBar(dist: dist, height: 5),
                      const SizedBox(height: 8),
                      Row(children: [
                        SourceAvatars(articles: sources, ring: Colors.black),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${sources.length} source${sources.length == 1 ? '' : 's'} · ${_split(dist)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: white70, fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                        _RoundAction(icon: Icons.thumb_up_alt_outlined, tooltip: 'More like this', onTap: _up),
                        const SizedBox(width: 6),
                        _RoundAction(icon: Icons.thumb_down_alt_outlined, tooltip: 'Less like this', onTap: _down),
                        const SizedBox(width: 6),
                        _RoundAction(icon: Icons.ios_share_rounded, tooltip: 'Share', onTap: _share),
                        const SizedBox(width: 6),
                        _RoundAction(icon: Icons.more_horiz_rounded, tooltip: 'More options', onTap: _menu),
                      ]),
                    ]),
                  ),
                ]);
              },
            ),
          ),
        ),
      ),
    );
    // Cards glide in as they appear, so the feed feels alive.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: card,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child),
      ),
    );
  }

  /// New and already picked up by several outlets.
  static bool _isBreaking(Story s) {
    final t = s.latest;
    if (t == null) return false;
    final first = s.articles.map((a) => a.published).whereType<DateTime>().fold<DateTime>(t, (a, b) => b.isBefore(a) ? b : a);
    return DateTime.now().toUtc().difference(first).inMinutes < 90 && s.uniqueSources.length >= 3;
  }

  /// Widely covered in the last day.
  static bool _isTrending(Story s) {
    final t = s.latest;
    return t != null && DateTime.now().toUtc().difference(t).inHours < 24 && s.uniqueSources.length >= 6;
  }

  static String _split(BiasDistribution d) {
    if (!d.isReliable) return 'Lean unknown';
    String p(Side s) => '${(d.share(s) * 100).round()}%';
    return 'L ${p(Side.left)} · C ${p(Side.center)} · R ${p(Side.right)}';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          // Translucent "glass" without a per-card blur (cheap on weak phones).
          color: (color ?? Colors.black).withValues(alpha: color == null ? 0.38 : 0.85),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

/// Small round translucent button used over photos.
class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white.withValues(alpha: 0.16),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(padding: const EdgeInsets.all(7), child: Icon(icon, size: 18, color: Colors.white)),
          ),
        ),
      );
}

/// Overlapping outlet "avatars", ringed in each outlet's bias colour.
class SourceAvatars extends StatelessWidget {
  const SourceAvatars({super.key, required this.articles, this.max = 5, this.ring});
  final List<Article> articles;
  final int max;
  final Color? ring;

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
                border: Border.all(color: ring ?? Theme.of(context).cardTheme.color ?? Colors.white, width: 2),
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
  const ArticleTile({super.key, required this.article, this.onOpen});
  final Article article;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final s = article.source;
    return ListTile(
      title: Text(article.title, maxLines: 3, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          // Tap the outlet for its bias, factuality and ownership.
          GestureDetector(
            onTap: s == null
                ? null
                : () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => SourceSheet(source: s)),
            child: Text(article.sourceName,
                style: const TextStyle(fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
          ),
          if (s != null) BiasChip(source: s),
          if (article.isLocal) const Tag('Local', color: Brand.purple),
          if (s?.stateAffiliated ?? false) const Tag('State-affiliated', color: Colors.deepOrange),
          Text(timeAgo(article.published)),
        ]),
      ),
      onTap: () {
        onOpen?.call();
        openArticle(context, article.url);
      },
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


/// A small tip shown until the user dismisses it (remembered on the phone).
class OneTimeTip extends StatelessWidget {
  const OneTimeTip({super.key, required this.id, required this.text});
  final String id;
  final String text;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.tipSeen(id)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        decoration: BoxDecoration(
          color: Brand.purple.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          const Icon(Icons.lightbulb_outline_rounded, color: Brand.purple, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
          IconButton(
            tooltip: 'Got it',
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => app.dismissTip(id),
          ),
        ]),
      ),
    );
  }
}
