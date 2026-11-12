import 'package:flutter/material.dart';

import '../../models/bias.dart';
import '../../services/markets.dart';

/// Horizontal ticker of key market numbers (S&P 500, Bitcoin, oil…).
/// Hides itself if the data can't be loaded.
class MarketsStrip extends StatefulWidget {
  const MarketsStrip({super.key});

  @override
  State<MarketsStrip> createState() => _MarketsStripState();
}

class _MarketsStripState extends State<MarketsStrip> {
  late final Future<List<Quote>> _quotes = Markets.load();

  static String _fmt(double v) {
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      final buf = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
        buf.write(s[i]);
      }
      return buf.toString();
    }
    return v < 10 ? v.toStringAsFixed(4) : v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Quote>>(
      future: _quotes,
      builder: (context, snap) {
        final q = snap.data ?? const [];
        if (q.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: q.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final up = q[i].changePct >= 0;
              final color = up ? const Color(0xFF16A34A) : Side.right.color;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(q[i].label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  Text('${_fmt(q[i].price)}  ${up ? '▲' : '▼'}${q[i].changePct.abs().toStringAsFixed(2)}%',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
                ]),
              );
            },
          ),
        );
      },
    );
  }
}
