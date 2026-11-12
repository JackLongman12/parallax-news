import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bias.dart';
import '../../models/story.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// "Reading balance": what share of the outlets in the stories you open lean
/// left, center or right. Computed and stored only on this phone.
class ReadingBalanceScreen extends StatelessWidget {
  const ReadingBalanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lean = app.profile.readLean;
    final l = lean['left'] ?? 0, c = lean['center'] ?? 0, r = lean['right'] ?? 0;
    final total = l + c + r;
    final theme = Theme.of(context);
    String pct(double v) => total == 0 ? '0%' : '${(v / total * 100).round()}%';
    String verdict() {
      if (total < 3) return 'Read a few more stories with rated coverage to see your balance.';
      final maxSide = [l, c, r].reduce((a, b) => a > b ? a : b) / total;
      if (maxSide < 0.45) return 'Nicely balanced: you read across the spectrum.';
      final side = l >= c && l >= r ? 'left' : (r >= c ? 'right' : 'center');
      if (side == 'center') return 'You mostly read centrist coverage.';
      final other = side == 'left' ? 'right' : 'left';
      return 'Your reading leans $side. Try the Blindspot tab to see what $other-leaning outlets cover.';
    }

    Widget bar() => ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 22,
            child: total == 0
                ? ColoredBox(color: Bias.unrated.color)
                : Row(children: [
                    if (l > 0) Expanded(flex: (l * 1000).round(), child: ColoredBox(color: Side.left.color)),
                    if (c > 0) Expanded(flex: (c * 1000).round(), child: ColoredBox(color: Side.center.color)),
                    if (r > 0) Expanded(flex: (r * 1000).round(), child: ColoredBox(color: Side.right.color)),
                  ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Reading balance')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Based on ${total.toStringAsFixed(0)} stories you opened', style: theme.textTheme.bodySmall),
        const SizedBox(height: 14),
        bar(),
        const SizedBox(height: 10),
        Row(children: [
          Text('Left ${pct(l)}', style: TextStyle(color: Side.left.color, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('Center ${pct(c)}', style: TextStyle(color: Side.center.color, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('Right ${pct(r)}', style: TextStyle(color: Side.right.color, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 20),
        Text(verdict(), style: theme.textTheme.titleMedium),
        const SizedBox(height: 20),
        Text('How it works: each time you open a story, the left/center/right mix of the outlets covering it is added '
            'here. Nothing leaves your phone.',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset'),
            onPressed: app.resetReadingBalance,
          ),
        ),
      ]),
    );
  }
}

/// Story facts: who broke it, who owns the outlets, how factual they are.
class CoverageFacts extends StatelessWidget {
  const CoverageFacts({super.key, required this.story});
  final Story story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outlets = story.uniqueSources;
    final dated = story.articles.where((a) => a.published != null).toList()
      ..sort((a, b) => a.published!.compareTo(b.published!));
    final first = dated.isEmpty ? null : dated.first;

    var state = 0, corporate = 0, other = 0;
    final fact = <Factuality, int>{};
    for (final a in outlets) {
      final s = a.source;
      if (s == null) {
        other++;
        continue;
      }
      if (s.stateAffiliated) {
        state++;
      } else if (s.owner != null && s.owner!.isNotEmpty) {
        corporate++;
      } else {
        other++;
      }
      fact[s.factuality] = (fact[s.factuality] ?? 0) + 1;
    }
    final high = (fact[Factuality.veryHigh] ?? 0) + (fact[Factuality.high] ?? 0);
    final mixed = (fact[Factuality.mostlyFactual] ?? 0) + (fact[Factuality.mixed] ?? 0);
    final low = fact[Factuality.low] ?? 0;

    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: Brand.purple),
            const SizedBox(width: 10),
            SizedBox(width: 110, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(child: Text(value)),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Brand.card(context), borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Coverage details', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        if (first != null)
          row(Icons.flag_rounded, 'First reported', '${first.sourceName} · ${timeAgo(first.published)}'),
        row(Icons.business_rounded, 'Ownership',
            '${corporate > 0 ? '$corporate corporate' : ''}${corporate > 0 && (state > 0 || other > 0) ? ' · ' : ''}'
                '${state > 0 ? '$state state-affiliated' : ''}${state > 0 && other > 0 ? ' · ' : ''}'
                '${other > 0 ? '$other independent / unknown' : ''}'),
        row(Icons.fact_check_rounded, 'Factuality',
            high + mixed + low == 0 ? 'Not rated yet' : '$high high · $mixed mixed · $low low'),
        if (outlets.any((a) => a.isLocal)) row(Icons.place_rounded, 'Local outlets', '${outlets.where((a) => a.isLocal).length} covering it'),
      ]),
    );
  }
}

/// Explore / Settings entry to the reading balance.
class ReadingBalanceTile extends StatelessWidget {
  const ReadingBalanceTile({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.balance_rounded, color: Brand.purple),
        title: const Text('Your reading balance'),
        subtitle: const Text('Left / center / right mix of what you read'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReadingBalanceScreen())),
      );
}

