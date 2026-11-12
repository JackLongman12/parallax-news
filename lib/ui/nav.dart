import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Fired when the user taps the bottom-nav tab they are already on
/// (Instagram-style: scroll to top, tap again at the top to refresh).
class TabReselect {
  static final List<ValueNotifier<int>> tabs = List.generate(6, (_) => ValueNotifier<int>(0));

  static void fire(int tab) => tabs[tab].value++;

  /// Fired when the user switches TO a tab: jump back to the top (no refresh),
  /// so a revisited page never opens halfway down.
  static final List<ValueNotifier<int>> tops = List.generate(6, (_) => ValueNotifier<int>(0));

  static void jumpTop(int tab) => tops[tab].value++;
}

class BarItem {
  const BarItem(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Floating, translucent bottom bar. Each item gets an equal share of the
/// width and the label is scaled to fit, so nothing overflows on small phones.
class ParallaxBottomBar extends StatelessWidget {
  const ParallaxBottomBar({super.key, required this.items, required this.selected, required this.onSelect});
  final List<BarItem> items;
  final int selected;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.80),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.08)),
            ),
            child: Row(children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Semantics(
                    label: items[i].label,
                    selected: i == selected,
                    button: true,
                    child: InkResponse(
                      radius: 30,
                      onTap: () => onSelect(i),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          width: i == selected ? 46 : 36,
                          height: 30,
                          decoration: BoxDecoration(
                            color: i == selected ? scheme.primary.withValues(alpha: 0.22) : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(i == selected ? items[i].selectedIcon : items[i].icon,
                              size: 22, color: i == selected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.75)),
                        ),
                        const SizedBox(height: 3),
                        SizedBox(
                          height: 13,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(items[i].label,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: i == selected ? FontWeight.w800 : FontWeight.w600,
                                  color: i == selected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.7),
                                )),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
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
    TabReselect.tops[widget.tab].addListener(_jump);
  }

  void _jump() {
    if (_c.hasClients) _c.jumpTo(0);
  }

  @override
  void dispose() {
    TabReselect.tabs[widget.tab].removeListener(_top);
    TabReselect.tops[widget.tab].removeListener(_jump);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_c);
}
