import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/story.dart';
import '../../services/markets.dart';
import '../../services/summarizer.dart';
import '../../state/app_state.dart';
import '../screens/story_screen.dart';
import '../theme.dart';

/// "Today in brief": the day's most widely covered stories in one card,
/// each with its most corroborated sentence (extracted, never invented),
/// plus a one-line markets summary. Collapsible.
class DailyOverview extends StatefulWidget {
  const DailyOverview({super.key});

  @override
  State<DailyOverview> createState() => _DailyOverviewState();
}

class _DailyOverviewState extends State<DailyOverview> {
  bool _open = true;
  late final Future<List<Quote>> _markets = Markets.load();
  late final Future<List<Story>> _brief = context.read<AppState>().repo.dailyBrief();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Story>>(future: _brief, builder: (context, snap) => _card(context, snap.data ?? const []));
  }

  Widget _card(BuildContext context, List<Story> picks) {
    final theme = Theme.of(context);
    if (picks.isEmpty) return const SizedBox.shrink();
    final outlets = {for (final s in picks) ...s.uniqueSources.map((a) => a.domain)}.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Material(
        color: Brand.purple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.wb_twilight_rounded, color: Brand.purple),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Today in brief', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                onPressed: () => setState(() => _open = !_open),
              ),
            ]),
            if (_open) ...[
              for (final s in picks) _Point(story: s),
              FutureBuilder<List<Quote>>(
                future: _markets,
                builder: (_, snap) {
                  final q = (snap.data ?? const <Quote>[]).where((x) => const {'S&P 500', 'Nasdaq', 'Bitcoin', 'Oil'}.contains(x.label)).toList();
                  if (q.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4, right: 8),
                    child: Text.rich(TextSpan(children: [
                      const TextSpan(text: 'Markets: ', style: TextStyle(fontWeight: FontWeight.w800)),
                      for (var i = 0; i < q.length; i++)
                        TextSpan(
                          text: '${q[i].label} ${q[i].changePct >= 0 ? '+' : '-'}${q[i].changePct.abs().toStringAsFixed(1)}%${i < q.length - 1 ? ' · ' : ''}',
                          style: TextStyle(color: q[i].changePct >= 0 ? const Color(0xFF16A34A) : Brand.red, fontWeight: FontWeight.w700),
                        ),
                    ])),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text('One top story from each area of the news, across $outlets outlets. Auto-extracted from their own reporting; tap a line for full coverage.',
                  style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            ],
          ]),
        ),
      ),
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
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis),
                ),
              Text('${story.category.label} · ${story.uniqueSources.length} outlets',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}
