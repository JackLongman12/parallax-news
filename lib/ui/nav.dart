import 'package:flutter/material.dart';

/// Fired when the user taps the bottom-nav tab they are already on
/// (Instagram-style: scroll to top, tap again at the top to refresh).
class TabReselect {
  static final List<ValueNotifier<int>> tabs = List.generate(6, (_) => ValueNotifier<int>(0));

  static void fire(int tab) => tabs[tab].value++;
}

/// Gives [builder] a scroll controller that jumps to the top when the
/// bottom-nav [tab] is tapped again.
class ReselectScroll extends StatefulWidget {
  const ReselectScroll({super.key, required this.tab, required this.builder});
  final int tab;
  final Widget Function(ScrollController controller) builder;

  @override
  State<ReselectScroll> createState() => _ReselectScrollState();
}

class _ReselectScrollState extends State<ReselectScroll> {
  final _c = ScrollController();

  void _top() {
    if (_c.hasClients) _c.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }

  @override
  void initState() {
    super.initState();
    TabReselect.tabs[widget.tab].addListener(_top);
  }

  @override
  void dispose() {
    TabReselect.tabs[widget.tab].removeListener(_top);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_c);
}
