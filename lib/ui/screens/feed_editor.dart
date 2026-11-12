import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'explore_screens.dart';

enum TopicState { neutral, following, muted }

extension TopicStateX on AppState {
  TopicState topicState(Category c) {
    if (followsTopic(c)) return TopicState.following;
    if (profile.muted.contains(c)) return TopicState.muted;
    return TopicState.neutral;
  }

  void setTopicState(Category c, TopicState s) {
    final cur = topicState(c);
    if (cur == s) return;
    if (cur == TopicState.following) toggleTopic(c);
    if (cur == TopicState.muted) toggleMute(c);
    if (s == TopicState.following) toggleTopic(c);
    if (s == TopicState.muted) toggleMute(c);
  }
}

final _pickable = Category.values.where((c) => c != Category.general && c != Category.local).toList();

/// Grid of topics. Tap cycles: neutral -> following -> muted -> neutral.
class TopicPicker extends StatelessWidget {
  const TopicPicker({super.key, this.allowMute = true});
  final bool allowMute;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final c in _pickable) _TopicChip(category: c, state: app.topicState(c), onTap: () {
        final s = app.topicState(c);
        final next = switch (s) {
          TopicState.neutral => TopicState.following,
          TopicState.following => allowMute ? TopicState.muted : TopicState.neutral,
          TopicState.muted => TopicState.neutral,
        };
        app.setTopicState(c, next);
      }),
    ]);
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({required this.category, required this.state, required this.onTap});
  final Category category;
  final TopicState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (bg, fg, icon) = switch (state) {
      TopicState.following => (Brand.purple, Colors.white, Icons.check),
      TopicState.muted => (dark ? const Color(0xFF26232E) : const Color(0xFFEDEBF1), Colors.grey, Icons.block),
      TopicState.neutral => (Colors.transparent, dark ? Colors.white : Brand.black, Brand.categoryIcon(category)),
    };
    return Material(
      color: bg,
      shape: StadiumBorder(side: BorderSide(color: state == TopicState.neutral ? Brand.purple.withValues(alpha: 0.4) : bg)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: fg),
            const SizedBox(width: 6),
            Text(category.label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  decoration: state == TopicState.muted ? TextDecoration.lineThrough : null,
                )),
          ]),
        ),
      ),
    );
  }
}

/// "Customize feed": topics, places and hidden outlets in one place.
Future<void> showFeedEditor(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => const _FeedEditor().withScroll(scroll),
      ),
    );

class _FeedEditor extends StatelessWidget {
  const _FeedEditor({this.scroll});
  final ScrollController? scroll;

  _FeedEditor withScroll(ScrollController c) => _FeedEditor(scroll: c);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    Widget h(String t, [String? sub]) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            if (sub != null) Text(sub, style: theme.textTheme.bodySmall),
          ]),
        );
    return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(18, 0, 18, 32), children: [
      Text('Customize your feed', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
      h('Topics', 'Tap once to follow ✓, twice to mute ⦸, again to reset.'),
      const TopicPicker(),
      h('Places', 'News from these places is mixed into For You.'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in app.followed)
          InputChip(label: Text(p.name), onDeleted: () => app.toggleFollow(p)),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: const Text('Add place'),
          onPressed: () async {
            final p = await showPlacePicker(context);
            if (p != null && !app.isFollowed(p)) app.toggleFollow(p);
          },
        ),
      ]),
      if (app.profile.hiddenSources.isNotEmpty) ...[
        h('Hidden outlets', 'Tap ✕ to show an outlet again.'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in app.profile.hiddenSources)
            InputChip(label: Text(d), onDeleted: () => app.toggleHiddenSource(d)),
        ]),
      ],
      h('What the app has learned'),
      Text(
        app.profile.signals == 0
            ? 'Nothing yet — it learns from what you open, read and skip. It all stays on this phone.'
            : 'Learned from ${app.profile.signals} interactions on this phone. Top interests: '
                '${_topInterests(app).join(', ')}.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.restart_alt),
          label: const Text('Reset learning'),
          onPressed: app.resetLearning,
        ),
      ),
    ]);
  }

  static List<String> _topInterests(AppState app) {
    final e = app.profile.weights.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    final names = e.take(3).map((e) => e.key.label).toList();
    return names.isEmpty ? ['still learning'] : names;
  }
}

/// First-run setup: pick topics and your area in one screen.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 16), children: [
              const Wordmark(size: 34),
              const SizedBox(height: 12),
              Text('What do you want to follow?',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('Pick a few topics. You can change this any time, and the app keeps learning from what you read.',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 18),
              const TopicPicker(allowMute: false),
              const SizedBox(height: 28),
              Text('Your area', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Get local news from your city or neighbourhood.', style: theme.textTheme.bodySmall),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in app.followed) InputChip(label: Text(p.name), onDeleted: () => app.toggleFollow(p)),
                ActionChip(
                  avatar: const Icon(Icons.add_location_alt_outlined, size: 18),
                  label: const Text('Add your city'),
                  onPressed: () async {
                    final p = await showPlacePicker(context);
                    if (p != null && !app.isFollowed(p)) app.toggleFollow(p);
                  },
                ),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: onDone,
                child: Text(app.followedTopics.isEmpty ? 'Skip for now' : 'Start reading'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
