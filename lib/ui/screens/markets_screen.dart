import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/subtopics.dart';
import '../../models/category.dart';
import '../../services/curator.dart';
import '../../services/markets.dart';
import '../../state/app_state.dart';
import '../nav.dart';
import '../theme.dart';
import 'feed_screens.dart';
import 'story_list.dart';

const _up = Color(0xFF16A34A);
const _down = Color(0xFFE0406A);

String fmtPrice(double v) {
  if (v >= 1000) {
    final s = v.toStringAsFixed(0);
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
  return v < 10 ? v.toStringAsFixed(4) : v.toStringAsFixed(2);
}

class ChangeTag extends StatelessWidget {
  const ChangeTag(this.pct, {super.key, this.big = false});
  final double pct;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final up = pct >= 0;
    final c = up ? _up : _down;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: big ? 10 : 6, vertical: big ? 4 : 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded, color: c, size: big ? 24 : 18),
        Text('${pct.abs().toStringAsFixed(2)}%',
            style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: big ? 16 : 12)),
      ]),
    );
  }
}

/// Markets tab: indices, your watchlist, big movers (with the news on why),
/// and market / economy headlines.
class MarketsScreen extends StatefulWidget {
  const MarketsScreen({super.key});

  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends State<MarketsScreen> {
  late Future<List<Quote>> _indices;
  late Future<List<Quote>> _watch;
  String _watchKey = '';

  void _reload(AppState app) {
    _indices = Markets.load();
    _watch = Markets.quotes(app.watchlist);
    _watchKey = app.watchlist.join(',');
  }

  @override
  void initState() {
    super.initState();
    _reload(context.read<AppState>());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_watchKey != app.watchlist.join(',')) _watch = Markets.quotes(app.watchlist);
    _watchKey = app.watchlist.join(',');
    final theme = Theme.of(context);
    Widget section(String t, [Widget? trailing]) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
          child: Row(children: [
            Expanded(child: Text(t, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
            if (trailing != null) trailing,
          ]),
        );

    final header = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      section('Markets today'),
      FutureBuilder<List<Quote>>(
        future: _indices,
        builder: (_, snap) {
          final q = snap.data ?? const <Quote>[];
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(height: 86, child: Center(child: CircularProgressIndicator()));
          }
          if (q.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Market data unavailable right now.'));
          return SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: q.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _QuoteCard(q: q[i]),
            ),
          );
        },
      ),
      FutureBuilder<List<Quote>>(
        future: _watch,
        builder: (context, snap) {
          final q = snap.data ?? const <Quote>[];
          final movers = q.where((x) => x.bigMove).toList()..sort((a, b) => b.changePct.abs().compareTo(a.changePct.abs()));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (movers.isNotEmpty) ...[
              section('Big movers'),
              for (final m in movers.take(3)) _MoverCard(q: m),
            ],
            section(
              'Your watchlist',
              TextButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
                onPressed: () => showSymbolSearch(context),
              ),
            ),
            if (snap.connectionState != ConnectionState.done)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (q.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('Add stocks or crypto to follow them here.'))
            else
              for (final x in q) _WatchRow(q: x),
          ]);
        },
      ),
      section('Market & economy news'),
      SubPathChips(paths: [
        for (final s in subtopics[Category.finance] ?? const <Sub>[]) SubPath(Category.finance, [s]),
      ]),
    ]);

    return StoryList(
      key: const ValueKey('markets-feed'),
      scrollToTop: TabReselect.tabs[2],
      header: header,
      loader: (force) async {
        if (force) setState(() => _reload(app));
        final bundles = await Future.wait([app.repo.topic(Category.finance, force: force), app.repo.topic(Category.business, force: force)]);
        return Curator.rank([...bundles[0].stories, ...bundles[1].stories], app.profile, limit: 80);
      },
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.q});
  final Quote q;

  @override
  Widget build(BuildContext context) => Material(
        color: Brand.purple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => openStock(context, q.symbol, q.label),
          child: Container(
            width: 132,
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(q.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(fmtPrice(q.price), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ChangeTag(q.changePct),
            ]),
          ),
        ),
      );
}

class _MoverCard extends StatelessWidget {
  const _MoverCard({required this.q});
  final Quote q;

  @override
  Widget build(BuildContext context) {
    final name = q.name ?? q.symbol;
    final up = q.changePct >= 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: (up ? _up : _down).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => openStock(context, q.symbol, name),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: up ? _up : _down, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$name ${up ? 'up' : 'down'} ${q.changePct.abs().toStringAsFixed(1)}% today',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text('Tap to see why: the latest news', style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      ),
    );
  }
}

class _WatchRow extends StatelessWidget {
  const _WatchRow({required this.q});
  final Quote q;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: () => openStock(context, q.symbol, q.name ?? q.symbol),
        title: Text(q.name ?? q.symbol, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(q.symbol),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(fmtPrice(q.price), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          ChangeTag(q.changePct),
        ]),
      );
}

void openStock(BuildContext context, String symbol, String name) {
  if (symbol.isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StockPage(symbol: symbol, name: name)));
}

/// Search for a stock / ETF / crypto and add it to the watchlist.
Future<void> showSymbolSearch(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: const SizedBox(height: 520, child: _SymbolSearch()),
      ),
    );

class _SymbolSearch extends StatefulWidget {
  const _SymbolSearch();

  @override
  State<_SymbolSearch> createState() => _SymbolSearchState();
}

class _SymbolSearchState extends State<_SymbolSearch> {
  Timer? _t;
  List<SymbolMatch> _res = [];
  bool _busy = false;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _changed(String q) {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _busy = true);
      final r = await Markets.search(q);
      if (mounted) {
        setState(() {
          _res = r;
          _busy = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          autofocus: true,
          onChanged: _changed,
          decoration: InputDecoration(
            hintText: 'Company, ticker or crypto (e.g. Nvidia)',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
          ),
        ),
      ),
      Expanded(
        child: ListView(children: [
          for (final m in _res)
            ListTile(
              title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${m.symbol} · ${m.type}'),
              trailing: IconButton(
                icon: Icon(app.watches(m.symbol) ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                    color: Brand.purple),
                onPressed: () => app.toggleWatch(m.symbol),
              ),
              onTap: () => openStock(context, m.symbol, m.name),
            ),
        ]),
      ),
    ]);
  }
}

/// A stock / asset: price, chart and the news moving it.
class StockPage extends StatefulWidget {
  const StockPage({super.key, required this.symbol, required this.name});
  final String symbol;
  final String name;

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  late final Future<Quote?> _quote = Markets.quote(widget.symbol);
  String _range = '1mo';
  late Future<List<double>> _hist = Markets.history(widget.symbol, range: _range);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final watching = app.watches(widget.symbol);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FutureBuilder<Quote?>(
          future: _quote,
          builder: (_, snap) {
            final q = snap.data;
            if (q == null) return const SizedBox(height: 40);
            return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(fmtPrice(q.price), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(q.currency ?? '')),
              const SizedBox(width: 10),
              Padding(padding: const EdgeInsets.only(bottom: 4), child: ChangeTag(q.changePct, big: true)),
            ]);
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: FutureBuilder<List<double>>(
            future: _hist,
            builder: (_, snap) {
              final h = snap.data ?? const <double>[];
              if (h.length < 2) return const Center(child: Text('Chart unavailable'));
              final up = h.last >= h.first;
              return CustomPaint(painter: _LineChart(h, up ? _up : _down), size: Size.infinite);
            },
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: '1d', label: Text('1D')),
            ButtonSegment(value: '5d', label: Text('5D')),
            ButtonSegment(value: '1mo', label: Text('1M')),
            ButtonSegment(value: '6mo', label: Text('6M')),
            ButtonSegment(value: '1y', label: Text('1Y')),
          ],
          selected: {_range},
          onSelectionChanged: (s) => setState(() {
            _range = s.first;
            _hist = Markets.history(widget.symbol, range: _range);
          }),
        ),
        const SizedBox(height: 16),
        Text('News', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
      ]),
    );
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
          Text(widget.symbol, style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          IconButton(
            tooltip: watching ? 'Remove from watchlist' : 'Add to watchlist',
            icon: Icon(watching ? Icons.star_rounded : Icons.star_border_rounded),
            onPressed: () => app.toggleWatch(widget.symbol),
          ),
        ],
      ),
      body: StoryList(
        header: header,
        loader: (force) async =>
            Curator.rank((await app.repo.stockNews(widget.symbol, widget.name, force: force)).stories, app.profile, limit: 60),
        emptyMessage: 'No recent news for ${widget.name}.',
      ),
    );
  }
}

class _LineChart extends CustomPainter {
  _LineChart(this.data, this.color);
  final List<double> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = data.reduce((a, b) => a < b ? a : b);
    final hi = data.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo) == 0 ? 1 : hi - lo;
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final y = size.height - (data[i] - lo) / span * (size.height - 8) - 4;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _LineChart old) => old.data != data || old.color != color;
}
