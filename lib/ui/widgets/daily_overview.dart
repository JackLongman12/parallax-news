import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/story.dart';
import '../../services/markets.dart';
import '../../services/summarizer.dart';
import '../../state/app_state.dart';
import '../nav.dart';
import '../screens/story_screen.dart';
import '../theme.dart';

/// "Today in brief": a purple button, collapsed by default.
///  * Tap to open: the most widely covered story from each area of the news.
///  * Closes itself when you switch tabs or leave the app.
///  * Shows a "New" badge only when 5+ new top stories appeared since you last
///    read it, or a new day started.
class DailyOverview extends StatefulWidget {
  const DailyOverview({super.key});

  @override
  State<DailyOverview> createState() => _DailyOverviewState();
}

class _DailyOverviewState extends State<DailyOverview> with WidgetsBindingObserver {
  bool _open = false;
  Future<List<Story>>? _brief;
  Future<List<Quote>>? _markets;
  int _newCount = 0;
  Timer? _peek;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TabReselect.tops[0].addListener(_collapse);
    // Quietly check (after the feed has loaded) whether there's enough new
    // to badge the button. Uses the same cached data as the feed.
    _peek = Timer(const Duration(seconds: 6), _checkNew);
  }

  @override
  void dispose() {
    _peek?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    TabReselect.tops[0].removeListener(_collapse);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _collapse();
    if (state == AppLifecycleState.resumed) _checkNew();
  }

  void _collapse() {
    if (_open && mounted) setState(() => _open = false);
  }

  Future<void> _checkNew() async {
    if (!mounted) return;
    final app = context.read<AppState>();
    _brief ??= app.repo.dailyBrief();
    final picks = await _brief!;
    if (!mounted) return;
    setState(() => _newCount = app.briefUnseen(picks));
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    final app = context.read<AppState>();
    setState(() {
      _open = !_open;
      if (_open) {
        _brief ??= app.repo.dailyBrief();
        _markets ??= Markets.load();
      }
    });
    if (_open) {
      _brief!.then((picks) {
        app.markBriefSeen(picks);
        if (mounted) setState(() => _newCount = 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final badge = _newCount > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Material(
          color: _open ? Brand.purple.withValues(alpha: 0.10) : Brand.purple,
          borderRadius: BorderRadius.circular(22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Icon(Icons.today_rounded, color: _open ? Brand.purple : Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Today in brief',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: _open ? null : Colors.white)),
                  ),
                  if (badge && !_open)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                      child: const Text('New', style: TextStyle(color: Brand.purple, fontWeight: FontWeight.w900, fontSize: 12)),
                    ),
                  const SizedBox(width: 6),
                  Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: _open ? null : Colors.white),
                ]),
              ),
            ),
            if (_open)
              FutureBuilder<List<Story>>(
                future: _brief,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
                  }
                  final picks = snap.data ?? const <Story>[];
                  if (picks.isEmpty) {
                    return const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('Nothing to summarise yet. Pull to refresh.'));
                  }
                  return _Body(picks: picks, markets: _markets);
                },
              ),
          ]),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.picks, required this.markets});
  final List<Story> picks;
  final Future<List<Quote>>? markets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outlets = {for (final s in picks) ...s.uniqueSources.map((a) => a.domain)}.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final s in picks) _Point(story: s),
        FutureBuilder<List<Quote>>(
          future: markets,
          builder: (_, snap) {
            final q = (snap.data ?? const <Quote>[])
                .where((x) => const {'S&P 500', 'Nasdaq', 'Bitcoin', 'Crude Oil'}.contains(x.label))
                .toList();
            if (q.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Text.rich(TextSpan(children: [
                const TextSpan(text: 'Markets: ', style: TextStyle(fontWeight: FontWeight.w800)),
                for (var i = 0; i < q.length; i++)
                  TextSpan(
                    text:
                        '${q[i].label} ${q[i].changePct >= 0 ? '+' : '-'}${q[i].changePct.abs().toStringAsFixed(1)}%${i < q.length - 1 ? ' · ' : ''}',
                    style: TextStyle(color: q[i].changePct >= 0 ? const Color(0xFF16A34A) : Brand.red, fontWeight: FontWeight.w700),
                  ),
              ])),
            );
          },
        ),
        const SizedBox(height: 8),
        Text('One top story from each area of the news, across $outlets outlets. Extracted from their own reporting.',
            style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
      ]),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.story});
  final Story story;

  @override
  Widget build(BuildContext context) {
    final sum = Summarizer.summarize(story, maxPoints: 1);
    final detail = sum.points.isEmpty ? null : sum.points.first.text;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StoryScreen(story: story))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 6, 8, 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 10),
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: Brand.purple, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(story.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (detail != null)
                Padding(padding: const EdgeInsets.only(top: 2), child: Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis)),
              Text('${story.category.label} · ${story.uniqueSources.length} outlets', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}
