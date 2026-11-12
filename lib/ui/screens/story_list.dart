import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/story.dart';
import '../widgets/common.dart';

/// A lazily-built, paginated story list. Only the visible cards are built,
/// and more are revealed as you scroll — cheap on low-end phones.
/// When the list is exhausted, [onLoadMore] can fetch an extra page
/// (e.g. topics you don't follow yet) so the feed keeps going.
class StoryList extends StatefulWidget {
  const StoryList({
    super.key,
    this.loader,
    this.streamLoader,
    this.initial,
    this.header,
    this.onLoadMore,
    this.emptyMessage = 'No stories found right now.',
    this.filter,
    this.autoRefresh,
  });

  final Future<List<Story>> Function(bool force)? loader;

  /// Progressive loading: each emission adds stories as they arrive.
  final Stream<List<Story>> Function(bool force)? streamLoader;

  /// Shown immediately (e.g. last session's feed) while fresh news loads.
  final List<Story>? initial;
  final Future<List<Story>> Function(int page)? onLoadMore;
  final Widget? header;
  final String emptyMessage;
  final bool Function(Story s)? filter;

  /// Quietly re-check for news this often and offer a "new stories" pill.
  final Duration? autoRefresh;

  @override
  State<StoryList> createState() => _StoryListState();
}

class _StoryListState extends State<StoryList> {
  static const _pageSize = 15;
  List<Story> _all = [];
  int _visible = _pageSize;
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  int _extraPage = 0;
  String? _error;
  final _scroll = ScrollController();
  StreamSubscription<List<Story>>? _sub;
  bool _refreshing = false;
  Timer? _autoTimer;
  List<Story> _pending = [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    final init = widget.initial;
    if (init != null && init.isNotEmpty) {
      _all = _filtered(init);
      _loading = false;
    }
    _load(false);
    final every = widget.autoRefresh;
    if (every != null) _autoTimer = Timer.periodic(every, (_) => _backgroundRefresh());
  }

  Future<void> _backgroundRefresh() async {
    if (_refreshing || _loading || !mounted) return;
    try {
      final latest = widget.streamLoader != null ? await widget.streamLoader!(true).last : await widget.loader!(true);
      final have = {for (final s in _all) for (final a in s.articles) a.url};
      final fresh = _filtered(latest).where((s) => !s.articles.any((a) => have.contains(a.url))).toList();
      if (fresh.isNotEmpty && mounted) setState(() => _pending = fresh);
    } catch (_) {}
  }

  void _showPending() {
    setState(() {
      _all = [..._pending, ..._all];
      _visible += _pending.length;
      _pending = [];
    });
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  List<Story> _filtered(List<Story> s) => widget.filter == null ? s : s.where(widget.filter!).toList();

  /// Adds newly arrived stories without moving the ones already on screen.
  void _merge(List<Story> incoming) {
    final byUrl = <String, int>{};
    for (var i = 0; i < _all.length; i++) {
      for (final a in _all[i].articles) {
        byUrl[a.url] = i;
      }
    }
    final next = [..._all];
    final fresh = <Story>[];
    for (final s in _filtered(incoming)) {
      final hit = s.articles.map((a) => byUrl[a.url]).whereType<int>().firstOrNull;
      if (hit != null) {
        next[hit] = s; // same story, now with more outlets
      } else {
        fresh.add(s);
      }
    }
    _all = [...next, ...fresh];
  }

  Future<void> _load(bool force) {
    if (widget.streamLoader != null) return _loadStream(force);
    return _loadOnce(force);
  }

  Future<void> _loadStream(bool force) {
    _sub?.cancel();
    final firstDone = Completer<void>();
    var first = true;
    setState(() {
      _loading = _all.isEmpty;
      _error = null;
      _refreshing = true;
    });
    _sub = widget.streamLoader!(force).listen(
      (stories) {
        if (!mounted) return;
        setState(() {
          if (first) {
            // First fresh batch replaces the cached snapshot.
            _all = _filtered(stories);
            _visible = _pageSize;
            _extraPage = 0;
            _exhausted = false;
          } else {
            _merge(stories);
          }
          _loading = false;
        });
        if (first) {
          first = false;
          if (!firstDone.isCompleted) firstDone.complete();
        }
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          if (_all.isEmpty) _error = 'Could not load news. Check your connection.\n($e)';
          _loading = false;
        });
        if (!firstDone.isCompleted) firstDone.complete();
      },
      onDone: () {
        if (mounted) setState(() => _refreshing = false);
        if (!firstDone.isCompleted) firstDone.complete();
      },
    );
    return firstDone.future;
  }

  Future<void> _loadOnce(bool force) async {
    setState(() {
      _loading = _all.isEmpty;
      _error = null;
    });
    try {
      final stories = await widget.loader!(force);
      if (!mounted) return;
      setState(() {
        _all = widget.filter == null ? stories : stories.where(widget.filter!).toList();
        _visible = _pageSize;
        _extraPage = 0;
        _exhausted = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load news. Check your connection.\n($e)';
        _loading = false;
      });
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 600) return;
    if (_visible < _all.length) {
      setState(() => _visible = (_visible + _pageSize).clamp(0, _all.length));
    } else if (widget.onLoadMore != null && !_loadingMore && !_exhausted) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final more = await widget.onLoadMore!(_extraPage++);
      if (!mounted) return;
      final ids = _all.map((s) => s.id).toSet();
      final fresh = more.where((s) => ids.add(s.id)).toList();
      setState(() {
        if (fresh.isEmpty) _exhausted = true;
        _all = [..._all, ...fresh];
        _visible = (_visible + _pageSize).clamp(0, _all.length);
      });
    } catch (_) {
      _exhausted = true;
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _all.isEmpty) {
      return EmptyOrError(message: _error!, onRetry: () => _load(true));
    }
    final count = _visible.clamp(0, _all.length);
    final hasHeader = widget.header != null;
    final showFooter = _loadingMore || _exhausted || (widget.onLoadMore == null && count == _all.length);
    final list = RefreshIndicator(
      onRefresh: () => _load(true),
      child: _all.isEmpty
          ? ListView(children: [
              if (hasHeader) widget.header!,
              const SizedBox(height: 120),
              EmptyOrError(message: widget.emptyMessage, onRetry: () => _load(true)),
            ])
          : ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: count + (hasHeader ? 1 : 0) + (showFooter ? 1 : 0),
              itemBuilder: (context, i) {
                if (hasHeader) {
                  if (i == 0) {
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      widget.header!,
                      if (_refreshing) const LinearProgressIndicator(minHeight: 2),
                    ]);
                  }
                  i -= 1;
                }
                if (i < count) return StoryCard(story: _all[i]);
                if (_loadingMore) {
                  return const Padding(
                      padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                }
                return const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: Text("You're all caught up ✓\nPull down to refresh.", textAlign: TextAlign.center)),
                );
              },
            ),
    );
    if (_pending.isEmpty) return list;
    return Stack(children: [
      list,
      Positioned(
        top: 12,
        left: 0,
        right: 0,
        child: Center(
          child: Material(
            color: Theme.of(context).colorScheme.primary,
            shape: const StadiumBorder(),
            elevation: 6,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: _showPending,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.arrow_upward, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text('${_pending.length} new ${_pending.length == 1 ? 'story' : 'stories'}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
