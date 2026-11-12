import 'package:flutter/material.dart';

import '../models/category.dart';

/// Brand palette: solid purple, white and black. No gradients.
/// (Blue/red are used only to encode political lean in bias bars.)
class Brand {
  static const purple = Color(0xFF7C3AED);
  static const deep = Color(0xFF5B21B6);
  static const violet = Color(0xFFC4B5FD);
  static const black = Color(0xFF0A0A0C);
  static const white = Color(0xFFFFFFFF);
  static const red = Color(0xFFE0406A);
  static const blue = Color(0xFF3F5BEA);

  static IconData categoryIcon(Category c) {
    switch (c) {
      case Category.general:
        return Icons.bolt;
      case Category.politics:
        return Icons.account_balance;
      case Category.world:
        return Icons.public;
      case Category.business:
        return Icons.business_center;
      case Category.technology:
        return Icons.memory;
      case Category.ai:
        return Icons.auto_awesome;
      case Category.science:
        return Icons.science;
      case Category.space:
        return Icons.rocket_launch;
      case Category.health:
        return Icons.favorite;
      case Category.sports:
        return Icons.sports_soccer;
      case Category.entertainment:
        return Icons.movie;
      case Category.gaming:
        return Icons.sports_esports;
      case Category.environment:
        return Icons.eco;
      case Category.crime:
        return Icons.gavel;
      case Category.education:
        return Icons.school;
      case Category.finance:
        return Icons.trending_up;
      case Category.autos:
        return Icons.directions_car;
      case Category.travel:
        return Icons.flight;
      case Category.lifestyle:
        return Icons.spa;
      case Category.local:
        return Icons.holiday_village;
    }
  }

  static ThemeData theme(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: purple, brightness: b).copyWith(
      primary: dark ? const Color(0xFFA78BFA) : purple,
      secondary: dark ? violet : deep,
      surface: dark ? black : white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF16141C) : white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? black : white,
        indicatorColor: purple.withValues(alpha: dark ? 0.45 : 0.16),
        labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: dark ? white : black)),
      ),
      chipTheme: ChipThemeData(shape: StadiumBorder(side: BorderSide(color: purple.withValues(alpha: 0.25)))),
    );
  }
}

/// "parallax" wordmark for the app bar.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) => Text('parallax',
      style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.8,
          color: Theme.of(context).colorScheme.primary));
}

/// Instagram-style ring around an avatar (solid purple).
class GradientRing extends StatelessWidget {
  const GradientRing({super.key, required this.child, this.size = 66, this.active = true});
  final Widget child;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(shape: BoxShape.circle, color: active ? Brand.purple : const Color(0xFFBDB6CC)),
        child: Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).scaffoldBackgroundColor),
          child: ClipOval(child: child),
        ),
      );
}
