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
        return Icons.bolt_rounded;
      case Category.politics:
        return Icons.account_balance_rounded;
      case Category.world:
        return Icons.public_rounded;
      case Category.business:
        return Icons.business_center_rounded;
      case Category.technology:
        return Icons.memory_rounded;
      case Category.ai:
        return Icons.auto_awesome_rounded;
      case Category.science:
        return Icons.science_rounded;
      case Category.space:
        return Icons.rocket_launch_rounded;
      case Category.health:
        return Icons.favorite_rounded;
      case Category.sports:
        return Icons.sports_soccer_rounded;
      case Category.entertainment:
        return Icons.movie_rounded;
      case Category.gaming:
        return Icons.sports_esports_rounded;
      case Category.environment:
        return Icons.eco_rounded;
      case Category.crime:
        return Icons.gavel_rounded;
      case Category.education:
        return Icons.school_rounded;
      case Category.finance:
        return Icons.trending_up_rounded;
      case Category.autos:
        return Icons.directions_car_rounded;
      case Category.travel:
        return Icons.flight_rounded;
      case Category.lifestyle:
        return Icons.spa_rounded;
      case Category.local:
        return Icons.holiday_village_rounded;
      case Category.energy:
        return Icons.electric_bolt_rounded;
      case Category.realEstate:
        return Icons.home_work_rounded;
      case Category.defense:
        return Icons.shield_rounded;
      case Category.labor:
        return Icons.work_rounded;
      case Category.weather:
        return Icons.cloud_rounded;
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
