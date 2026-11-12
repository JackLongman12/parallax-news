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
    required this.loader,
    this.header,
    this.onLoadMore,
    this.emptyMessage = 'No stories found right now.',
    this.filter,
  });

  final Future<List<Story>> Function(bool force) loader;
  final Future<List<Story>> Function(int page)? onLoadMore;
  final Widget? header;
  final String emptyMessage;
  final bool Function(Story s)? filter;

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

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(false);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load(bool force) async {
    setState(() {
      _loading = _all.isEmpty;
      _error = null;
    });
    try {
      final stories = await widget.loader(force);
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
    return RefreshIndicator(
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
                  if (i == 0) return widget.header!;
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
  }
}
