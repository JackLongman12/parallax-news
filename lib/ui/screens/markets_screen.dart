import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/subtopics.dart';
import '../../models/category.dart';
import '../../services/curator.dart';
import '../../services/markets.dart';
import '../../state/app_state.dart';
import '../nav.dart';
import '../theme.dart';
import 'feed_screens.dart';
import 'info_pages.dart';
import 'story_list.dart';

const _up = Color(0xFF16A34A);
const _down = Color(0xFFE0406A);
Color _tone(double v) => v >= 0 ? _up : _down;

String fmtPrice(double v) {
  final neg = v < 0;
  v = v.abs();
  String s;
  if (v >= 1000) {
    final parts = v.toStringAsFixed(2).split('.');
    final b = StringBuffer();
    final i = parts[0];
    for (var k = 0; k < i.length; k++) {
      if (k > 0 && (i.length - k) % 3 == 0) b.write(',');
      b.write(i[k]);
    }
    s = '$b.${parts[1]}';
  } else {
    s = v < 2 ? v.toStringAsFixed(4) : v.toStringAsFixed(2);
  }
  return neg ? '-$s' : s;
}

String fmtVolume(int? v) {
  if (v == null) return '--';
  if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
  if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
  if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
  return '$v';
}

String _signed(double v, {String suffix = ''}) => '${v >= 0 ? '+' : ''}${fmtPrice(v)}$suffix';

class ChangeTag extends StatelessWidget {
  const ChangeTag(this.pct, {super.key, this.big = false});
  final double pct;
  final bool big;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: big ? 10 : 7, vertical: big ? 4 : 3),
        decoration: BoxDecoration(color: _tone(pct), borderRadius: BorderRadius.circular(8)),
        child: Text('${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: big ? 15 : 12)),
      );
}

/// Tiny line chart (no axes) for lists and cards.
class Sparkline extends StatelessWidget {
  const Sparkline(this.data, {super.key, this.baseline, this.width = 64, this.height = 28});
  final List<double> data;
  final double? baseline;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) return SizedBox(width: width, height: height);
    final up = data.last >= (baseline ?? data.first);
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _ChartPainter(data, _tone(up ? 1 : -1), baseline: baseline, fill: false)),
    );
  }
}

/// Markets tab: market summary, watchlist, trending, top movers, news.
class MarketsScreen extends StatefulWidget {
  const MarketsScreen({super.key});

  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends State<MarketsScreen> {
  late Future<List<Quote>> _indices;
  late Future<List<Quote>> _watch;
  late Future<List<Quote>> _trending;
  String _moverScreen = 'day_gainers';
  late Future<List<Quote>> _movers;
  String _watchKey = '';

  void _reload(AppState app) {
    _indices = Markets.load();
    _watch = Markets.quotes(app.watchlist);
    _watchKey = app.watchlist.join(',');
    _trending = Markets.trending().then((s) => Markets.quotes(s.take(8).toList()));
    _movers = Markets.movers(_moverScreen);
  }

  @override
  void initState() {
    super.initState();
    _reload(context.read<AppState>());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_watchKey != app.watchlist.join(',')) {
      _watch = Markets.quotes(app.watchlist);
      _watchKey = app.watchlist.join(',');
    }
    final theme = Theme.of(context);
    Widget section(String t, [Widget? trailing]) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
          child: Row(children: [
            Expanded(child: Text(t, style: theme.textTheme.titleLarge)),
            if (trailing != null) trailing,
          ]),
        );

    Widget loading() => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));

    final header = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      section('Market summary'),
      FutureBuilder<List<Quote>>(
        future: _indices,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) return loading();
          final q = snap.data ?? const <Quote>[];
          if (q.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Market data unavailable right now.'));
          return GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.9,
            children: [for (final x in q) _SummaryCard(q: x)],
          );
        },
      ),
      section('My watchlist',
          TextButton.icon(icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add'), onPressed: () => showSymbolSearch(context))),
      FutureBuilder<List<Quote>>(
        future: _watch,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) return loading();
          final q = snap.data ?? const <Quote>[];
          if (q.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Add stocks or crypto to follow them here.'));
          final movers = q.where((x) => x.bigMove).toList()..sort((a, b) => b.changePct.abs().compareTo(a.changePct.abs()));
          return Column(children: [
            for (final m in movers.take(2)) _MoverCard(q: m),
            for (final x in q) QuoteRow(q: x),
          ]);
        },
      ),
      section('Trending tickers'),
      FutureBuilder<List<Quote>>(
        future: _trending,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) return loading();
          final q = snap.data ?? const <Quote>[];
          if (q.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Trending list unavailable right now.'));
          return Column(children: [for (final x in q) QuoteRow(q: x)]);
        },
      ),
      section('Top movers'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'day_gainers', label: Text('Gainers')),
            ButtonSegment(value: 'day_losers', label: Text('Losers')),
            ButtonSegment(value: 'most_actives', label: Text('Most active')),
          ],
          selected: {_moverScreen},
          onSelectionChanged: (s) => setState(() {
            _moverScreen = s.first;
            _movers = Markets.movers(_moverScreen);
          }),
        ),
      ),
      FutureBuilder<List<Quote>>(
        future: _movers,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) return loading();
          final q = snap.data ?? const <Quote>[];
          if (q.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Movers unavailable right now.'));
          return Column(children: [for (final x in q) QuoteRow(q: x, showVolume: _moverScreen == 'most_actives')]);
        },
      ),
      InkWell(
        onTap: () => InfoPage.open(context, marketsPage),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(marketDisclaimer, style: theme.textTheme.bodySmall),
        ),
      ),
      section('Market news'),
      SubPathChips(paths: [for (final s in subtopics[Category.finance] ?? const <Sub>[]) SubPath(Category.finance, [s])]),
      const SizedBox(height: 8),
    ]);

    return StoryList(
      key: const ValueKey('markets-feed'),
      scrollToTop: TabReselect.tabs[2],
      jumpToTop: TabReselect.tops[2],
      header: header,
      loader: (force) async {
        if (force) setState(() => _reload(app));
        final bundles = await Future.wait([app.repo.topic(Category.finance, force: force), app.repo.topic(Category.business, force: force)]);
        final crawl = await app.repo.withCrawler([...bundles[0].stories, ...bundles[1].stories], category: Category.finance, force: force);
        return Curator.rank(crawl, app.profile, limit: 80);
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.q});
  final Quote q;

  @override
  Widget build(BuildContext context) => Material(
        color: Brand.card(context),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openStock(context, q.symbol, q.label),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(q.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                Sparkline(q.spark, baseline: q.prevClose, width: 52, height: 22),
              ]),
              const Spacer(),
              Text(fmtPrice(q.price), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              Text('${q.change == null ? '' : '${_signed(q.change!)}  '}${_signed(q.changePct, suffix: '%')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _tone(q.changePct), fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
          ),
        ),
      );
}

/// One row: symbol + name, mini chart, price and colored % chip (Yahoo-style).
class QuoteRow extends StatelessWidget {
  const QuoteRow({super.key, required this.q, this.showVolume = false});
  final Quote q;
  final bool showVolume;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => openStock(context, q.symbol, q.name ?? q.symbol),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(q.symbol, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                Text(showVolume ? 'Vol ${fmtVolume(q.volume)}' : (q.name ?? ''),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            if (q.spark.isNotEmpty) Sparkline(q.spark, baseline: q.prevClose),
            const SizedBox(width: 12),
            SizedBox(
              width: 92,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(fmtPrice(q.price), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                ChangeTag(q.changePct),
              ]),
            ),
          ]),
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
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: _tone(q.changePct).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openStock(context, q.symbol, name),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: _tone(q.changePct), size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$name ${up ? 'up' : 'down'} ${q.changePct.abs().toStringAsFixed(1)}% today',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  Text('Tap to see why', style: Theme.of(context).textTheme.bodySmall),
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

void openStock(BuildContext context, String symbol, String name) {
  if (symbol.isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StockPage(symbol: symbol, name: name)));
}

/// Search for a stock / ETF / crypto and add it to the watchlist.
Future<void> showSymbolSearch(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
    _t = Timer(const Duration(milliseconds: 350), () async {
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
            hintText: 'Search symbols or companies',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _busy
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                : null,
          ),
        ),
      ),
      Expanded(
        child: ListView(children: [
          for (final m in _res)
            ListTile(
              title: Text(m.symbol, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${m.name} · ${m.type}', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: Icon(app.watches(m.symbol) ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, color: Brand.purple),
                onPressed: () => app.toggleWatch(m.symbol),
              ),
              onTap: () => openStock(context, m.symbol, m.name),
            ),
        ]),
      ),
    ]);
  }
}

/// Quote page: price, change, "as of" time, scrubbable chart, key stats, news.
class StockPage extends StatefulWidget {
  const StockPage({super.key, required this.symbol, required this.name});
  final String symbol;
  final String name;

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  late Future<Quote?> _quote = Markets.quote(widget.symbol);
  String _range = '1d';
  late Future<History?> _hist = Markets.history(widget.symbol, range: _range);
  int? _scrub;

  static const _labels = {'1d': '1D', '5d': '5D', '1mo': '1M', '6mo': '6M', 'ytd': 'YTD', '1y': '1Y', '5y': '5Y', 'max': 'Max'};

  String _time(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0'), mm = t.minute.toString().padLeft(2, '0');
    if (_range == '1d' || _range == '5d') return '${t.month}/${t.day} $hh:$mm';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final watching = app.watches(widget.symbol);
    final theme = Theme.of(context);

    final header = FutureBuilder<Quote?>(
      future: _quote,
      builder: (_, qs) {
        final q = qs.data;
        return FutureBuilder<History?>(
          future: _hist,
          builder: (_, hs) {
            final h = hs.data;
            // While scrubbing, show the price under the finger, like Yahoo.
            final scrubbing = _scrub != null && h != null && !h.isEmpty && _scrub! < h.closes.length;
            final base = _range == '1d' ? (q?.prevClose ?? h?.prevClose) : (h != null && !h.isEmpty ? h.closes.first : null);
            final shown = scrubbing ? h.closes[_scrub!] : q?.price;
            final diff = (shown != null && base != null) ? shown - base : null;
            final pct = (diff != null && base != null && base != 0) ? diff / base * 100 : q?.changePct;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (q == null && qs.connectionState != ConnectionState.done)
                  const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))
                else if (q == null)
                  const Text('Quote unavailable right now.')
                else ...[
                  Text(fmtPrice(shown ?? q.price), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1)),
                  if (diff != null && pct != null)
                    Text('${_signed(diff)} (${_signed(pct, suffix: '%')})',
                        style: TextStyle(color: _tone(diff), fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    scrubbing
                        ? _time(h.times[_scrub!])
                        : 'As of ${q.marketTime == null ? '--' : _time(q.marketTime!)} · ${q.currency ?? ''} · ${q.exchange ?? ''} · may be delayed',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  height: 200,
                  child: h == null || h.isEmpty
                      ? Center(
                          child: hs.connectionState == ConnectionState.done ? const Text('Chart unavailable') : const CircularProgressIndicator())
                      : LayoutBuilder(builder: (context, c) {
                          void at(double x) {
                            final i = (x / c.maxWidth * (h.closes.length - 1)).round().clamp(0, h.closes.length - 1);
                            if (i != _scrub) {
                              HapticFeedback.selectionClick();
                              setState(() => _scrub = i);
                            }
                          }

                          final up = h.closes.last >= (base ?? h.closes.first);
                          return GestureDetector(
                            onHorizontalDragStart: (d) => at(d.localPosition.dx),
                            onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
                            onHorizontalDragEnd: (_) => setState(() => _scrub = null),
                            onLongPressStart: (d) => at(d.localPosition.dx),
                            onLongPressMoveUpdate: (d) => at(d.localPosition.dx),
                            onLongPressEnd: (_) => setState(() => _scrub = null),
                            child: CustomPaint(
                              size: Size(c.maxWidth, 200),
                              painter: _ChartPainter(h.closes, _tone(up ? 1 : -1),
                                  baseline: _range == '1d' ? base : null, scrub: _scrub, labels: true),
                            ),
                          );
                        }),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final r in Markets.ranges)
                    ChoiceChip(
                      label: Text(_labels[r]!),
                      selected: _range == r,
                      showCheckmark: false,
                      selectedColor: Brand.purple,
                      labelStyle: TextStyle(color: _range == r ? Colors.white : null, fontWeight: FontWeight.w700),
                      onSelected: (_) => setState(() {
                        _range = r;
                        _scrub = null;
                        _hist = Markets.history(widget.symbol, range: r);
                      }),
                    ),
                ]),
                if (q != null) ...[
                  const SizedBox(height: 16),
                  _Stats(q: q),
                ],
                const SizedBox(height: 16),
                Text('News', style: theme.textTheme.titleLarge),
              ]),
            );
          },
        );
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.symbol, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
        ]),
      ),
      // One-handed: watchlist toggle at the bottom.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          height: 52,
          child: watching
              ? OutlinedButton.icon(
                  icon: const Icon(Icons.star_rounded), label: const Text('In your watchlist'), onPressed: () => app.toggleWatch(widget.symbol))
              : FilledButton.icon(
                  icon: const Icon(Icons.star_border_rounded),
                  label: const Text('Add to watchlist'),
                  onPressed: () => app.toggleWatch(widget.symbol)),
        ),
      ),
      body: StoryList(
        header: header,
        loader: (force) async {
          if (force) {
            setState(() {
              _quote = Markets.quote(widget.symbol);
              _hist = Markets.history(widget.symbol, range: _range);
            });
          }
          return Curator.rank((await app.repo.stockNews(widget.symbol, widget.name, force: force)).stories, app.profile, limit: 60);
        },
        emptyMessage: 'No recent news for ${widget.name}.',
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.q});
  final Quote q;

  @override
  Widget build(BuildContext context) {
    String p(double? v) => v == null ? '--' : fmtPrice(v);
    final rows = <(String, String)>[
      ('Previous close', p(q.prevClose)),
      ('Open', p(q.open)),
      ('Day range', q.dayLow == null ? '--' : '${p(q.dayLow)} - ${p(q.dayHigh)}'),
      ('52-week range', q.yearLow == null ? '--' : '${p(q.yearLow)} - ${p(q.yearHigh)}'),
      ('Volume', fmtVolume(q.volume)),
      ('Currency', q.currency ?? '--'),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Brand.card(context), borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(child: Text(r.$1, style: Theme.of(context).textTheme.bodyMedium)),
              Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
      ]),
    );
  }
}

/// Line chart with optional dashed baseline (previous close), price labels
/// and a scrub cursor.
class _ChartPainter extends CustomPainter {
  _ChartPainter(this.data, this.color, {this.baseline, this.scrub, this.labels = false, this.fill = true});
  final List<double> data;
  final Color color;
  final double? baseline;
  final int? scrub;
  final bool labels;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    var lo = data.reduce((a, b) => a < b ? a : b);
    var hi = data.reduce((a, b) => a > b ? a : b);
    final bl = baseline;
    if (bl != null) {
      lo = lo < bl ? lo : bl;
      hi = hi > bl ? hi : bl;
    }
    final span = (hi - lo) == 0 ? 1.0 : hi - lo;
    final top = labels ? 10.0 : 2.0, bottom = labels ? 10.0 : 2.0;
    double y(double v) => size.height - bottom - (v - lo) / span * (size.height - top - bottom);
    double x(int i) => size.width * i / (data.length - 1);

    if (bl != null) {
      final by = y(bl);
      final dash = Paint()
        ..color = Colors.grey.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      for (var dx = 0.0; dx < size.width; dx += 8) {
        canvas.drawLine(Offset(dx, by), Offset(dx + 4, by), dash);
      }
    }
    final path = Path()..moveTo(x(0), y(data[0]));
    for (var i = 1; i < data.length; i++) {
      path.lineTo(x(i), y(data[i]));
    }
    if (fill) {
      final area = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)],
            ).createShader(Offset.zero & size));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = labels ? 2.4 : 1.6
          ..strokeJoin = StrokeJoin.round);
    if (labels) {
      void label(String s, double yy) {
        final tp = TextPainter(
          text: TextSpan(text: s, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(size.width - tp.width, (yy - tp.height / 2).clamp(0, size.height - tp.height)));
      }

      label(fmtPrice(hi), top);
      label(fmtPrice(lo), size.height - bottom);
    }
    final sc = scrub;
    if (sc != null && sc < data.length) {
      final sx = x(sc), sy = y(data[sc]);
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), Paint()..color = Colors.grey.withValues(alpha: 0.6));
      canvas.drawCircle(Offset(sx, sy), 5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter o) =>
      o.data != data || o.color != color || o.scrub != scrub || o.baseline != baseline;
}
