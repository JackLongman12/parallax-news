import 'package:flutter/material.dart';

import '../models/category.dart';

/// Brand palette: purple-led, fading into blue (left) or red (right) at the edges.
class Brand {
  static const deep = Color(0xFF3A1786);
  static const purple = Color(0xFF6E35D9);
  static const violet = Color(0xFF9B6BFF);
  static const blue = Color(0xFF3F5BEA);
  static const red = Color(0xFFE0406A);

  static const gradient = LinearGradient(
    colors: [deep, purple, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// The signature "spectrum" fade used for rings, bars and highlights.
  static const spectrum = LinearGradient(colors: [blue, purple, red]);

  /// Each category gets purple with an occasional fade to blue or red.
  static List<Color> categoryColors(Category c) {
    final fade = c.index % 3 == 0 ? red : (c.index % 3 == 1 ? blue : violet);
    return [deep, purple, fade];
  }

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
      primary: dark ? violet : purple,
      secondary: dark ? const Color(0xFFC6A8FF) : deep,
      surface: dark ? const Color(0xFF120B22) : const Color(0xFFF8F5FF),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF1C1233) : Colors.white,
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
        backgroundColor: dark ? const Color(0xFF170E2B) : Colors.white,
        indicatorColor: purple.withValues(alpha: dark ? 0.45 : 0.16),
        labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: dark ? Colors.white : deep)),
      ),
      chipTheme: ChipThemeData(shape: StadiumBorder(side: BorderSide(color: purple.withValues(alpha: 0.25)))),
    );
  }
}

/// Gradient "Parallax" wordmark for the app bar.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => Brand.spectrum.createShader(r),
        child: Text('parallax',
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, letterSpacing: -0.8, color: Colors.white)),
      );
}

/// Instagram-style gradient ring around an avatar.
class GradientRing extends StatelessWidget {
  const GradientRing({super.key, required this.child, this.size = 66, this.colors});
  final Widget child;
  final double size;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(colors: colors ?? const [Brand.blue, Brand.purple, Brand.red, Brand.violet, Brand.blue]),
        ),
        child: Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).scaffoldBackgroundColor),
          child: ClipOval(child: child),
        ),
      );
}
