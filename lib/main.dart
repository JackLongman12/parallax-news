import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';

import 'services/home_widgets.dart';
import 'state/app_state.dart';
import 'ui/screens/explore_screens.dart';
import 'ui/screens/feed_editor.dart';
import 'ui/screens/feed_screens.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/sources_screen.dart';
import 'ui/theme.dart';
import 'ui/update_flow.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.create();
  runApp(ChangeNotifierProvider.value(value: state, child: const ParallaxApp()));
}

class ParallaxApp extends StatelessWidget {
  const ParallaxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parallax News',
      debugShowCheckedModeBanner: false,
      theme: Brand.theme(Brightness.light),
      darkTheme: Brand.theme(Brightness.dark),
      home: const _Start(),
    );
  }
}

/// Shows the one-time topic/area picker, then the app.
class _Start extends StatefulWidget {
  const _Start();

  @override
  State<_Start> createState() => _StartState();
}

class _StartState extends State<_Start> {
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    if (!app.onboarded) {
      return OnboardingScreen(onDone: () => setState(app.finishOnboarding));
    }
    return const HomeShell();
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 0, this.pageOverride});

  final int initialTab;

  /// Used by the screenshot generator to inject sample content.
  final Widget? Function(int tab)? pageOverride;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late int _tab = widget.initialTab;
  late final _built = <int>{widget.initialTab};

  static const _titles = ['For You', 'Topics', 'Explore', 'Blindspot', 'Sources'];

  @override
  void initState() {
    super.initState();
    if (widget.pageOverride != null) return;
    _listenToWidgets();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCheckUpdate());
  }

  DateTime _lastUpdateCheck = DateTime.fromMillisecondsSinceEpoch(0);

  /// Android usually *resumes* the app rather than restarting it, so check on
  /// every return to the app too (at most every 2 minutes).
  void _maybeCheckUpdate() {
    if (!mounted || !context.read<AppState>().autoUpdate) return;
    if (DateTime.now().difference(_lastUpdateCheck) < const Duration(minutes: 2)) return;
    _lastUpdateCheck = DateTime.now();
    checkForUpdate(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _maybeCheckUpdate();
  }

  StreamSubscription<Uri?>? _widgetSub;

  /// Tapping a home-screen widget opens the matching tab.
  Future<void> _listenToWidgets() async {
    if (!Platform.isAndroid) return;
    try {
      _go(HomeWidgets.tabFor(await HomeWidget.initiallyLaunchedFromHomeWidget()));
      _widgetSub = HomeWidget.widgetClicked.listen((uri) => _go(HomeWidgets.tabFor(uri)));
    } catch (_) {}
  }

  void _go(int? tab) {
    if (tab == null || !mounted) return;
    setState(() {
      _tab = tab;
      _built.add(tab);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetSub?.cancel();
    super.dispose();
  }

  Widget _page(int i) {
    final o = widget.pageOverride?.call(i);
    if (o != null) return o;
    switch (i) {
      case 0:
        return const ForYouScreen();
      case 1:
        return const TopicsScreen();
      case 2:
        return const ExploreScreen();
      case 3:
        return const BlindspotScreen();
      default:
        return const SourcesScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _tab == 0 ? const Wordmark() : Text(_titles[_tab], style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      // Tabs are built lazily on first visit, then kept alive.
      body: IndexedStack(
        index: _tab,
        children: [for (var i = 0; i < 5; i++) _built.contains(i) ? _page(i) : const SizedBox.shrink()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          _built.add(i);
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'For You'),
          NavigationDestination(icon: Icon(Icons.category_outlined), selectedIcon: Icon(Icons.category), label: 'Topics'),
          NavigationDestination(icon: Icon(Icons.public_outlined), selectedIcon: Icon(Icons.public), label: 'Explore'),
          NavigationDestination(icon: Icon(Icons.visibility_off_outlined), selectedIcon: Icon(Icons.visibility_off), label: 'Blindspot'),
          NavigationDestination(icon: Icon(Icons.newspaper_outlined), selectedIcon: Icon(Icons.newspaper), label: 'Sources'),
        ],
      ),
    );
  }
}
