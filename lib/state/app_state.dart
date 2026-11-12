import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/article.dart';
import '../models/bias.dart';
import '../models/category.dart';
import '../models/place.dart';
import '../models/source.dart';
import '../models/story.dart';
import '../services/bias_service.dart';
import '../services/country_detect.dart';
import '../services/cover_images.dart';
import '../services/markets.dart';
import '../services/classifier.dart';
import '../services/curator.dart';
import '../services/repository.dart';

/// App-wide state. Everything is stored locally on the device.
class AppState extends ChangeNotifier {
  AppState._(this._prefs, this.bias, this.classifier, this.repo, this.settings);

  final SharedPreferences _prefs;
  final BiasService bias;
  final TopicClassifier classifier;
  final NewsRepository repo;
  final FetchSettings settings;
  final InterestProfile profile = InterestProfile();

  List<Place> followed = [];
  List<Category> followedTopics = [Category.technology, Category.ai, Category.science];
  bool autoUpdate = true;
  Timer? _saveModelTimer;

  static Future<AppState> create() async {
    final prefs = await SharedPreferences.getInstance();
    final bias = BiasService();
    await bias.load();
    await CoverImages.loadVariants();
    final classifier = TopicClassifier();
    final settings = FetchSettings();
    final repo = NewsRepository(bias: bias, classifier: classifier, settings: settings);
    final s = AppState._(prefs, bias, classifier, repo, settings);
    s._load();
    repo.onModelUpdated = s._scheduleModelSave;
    repo.store = prefs;
    repo.onRatingsUpdated = s._scheduleRatingsSave;
    unawaited(bias.refreshRemote());
    unawaited(s.detectHomeCountry());
    if (!NewsRepository.offline) {
      unawaited(CoverImages.init(prefs, [...Category.values.where((c) => c != Category.local)]));
    }
    return s;
  }

  void _load() {
    final p = _prefs;
    try {
      followed = (jsonDecode(p.getString('followed') ?? '[]') as List)
          .map((e) => Place.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      followed = [];
    }
    final topics = p.getStringList('topics');
    if (topics != null) {
      followedTopics = topics.map(Category.byName).whereType<Category>().toList();
    }
    try {
      final ov = jsonDecode(p.getString('overrides') ?? '{}') as Map<String, dynamic>;
      bias.overrides = ov.map((k, v) => MapEntry(k, Bias.fromCode(v as String)));
    } catch (_) {}
    settings
      ..useBing = p.getBool('useBing') ?? true
      ..useGdelt = p.getBool('useGdelt') ?? false
      ..autoSources = true
      ..discoverLocal = p.getBool('discoverLocal') ?? true
      ..lite = false
      ..maxLocalOutlets = (p.getBool('outletsMaxV2') ?? false) ? (p.getInt('maxLocalOutlets') ?? 25) : 25
      ..homeCountry = p.getString('homeCountry') ?? CountryDetector.fromDevice() ?? 'US';
    homeCountryAuto = p.getBool('homeCountryAuto') ?? true;
    autoUpdate = p.getBool('autoUpdate') ?? true;
    // One-time migration: local outlets now default to the maximum.
    if (!(p.getBool('outletsMaxV2') ?? false)) {
      p.setBool('outletsMaxV2', true);
      p.setInt('maxLocalOutlets', 25);
    }
    try {
      final disc = jsonDecode(p.getString('discovered') ?? '[]') as List;
      bias.addDiscovered(disc.whereType<Map<String, dynamic>>().map(SourceInfo.fromJson));
      bias.lookedUp.addAll(p.getStringList('lookedUp') ?? const []);
    } catch (_) {}
    final model = p.getString('nbModel');
    if (model != null) classifier.loadJsonString(model);
    // Age the model once a day so it follows the current news cycle.
    final last = DateTime.tryParse(p.getString('nbDecayed') ?? '');
    if (last == null || DateTime.now().difference(last).inHours >= 24) {
      classifier.decay();
      p.setString('nbDecayed', DateTime.now().toIso8601String());
    }
    try {
      recentPlaces = (jsonDecode(p.getString('recentPlaces') ?? '[]') as List)
          .map((e) => Place.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}
    _loadSnapshot();
    final prof = p.getString('profile');
    if (prof != null) profile.loadJsonString(prof);
  }

  Timer? _saveRatingsTimer;

  void _scheduleRatingsSave() {
    _saveRatingsTimer?.cancel();
    _saveRatingsTimer = Timer(const Duration(seconds: 4), () {
      final list = bias.discovered.take(4000).map((s) => s.toJson()).toList();
      _prefs.setString('discovered', jsonEncode(list));
      _prefs.setStringList('lookedUp', bias.lookedUp.take(8000).toList());
    });
  }

  void _scheduleModelSave() {
    _saveModelTimer?.cancel();
    _saveModelTimer = Timer(const Duration(seconds: 5), () {
      _prefs.setString('nbModel', classifier.toJsonString());
    });
  }

  bool isFollowed(Place p) => followed.contains(p);

  void toggleFollow(Place p) {
    if (followed.contains(p)) {
      followed.remove(p);
    } else {
      followed.add(p);
    }
    _prefs.setString('followed', jsonEncode(followed.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  bool followsTopic(Category c) => followedTopics.contains(c);

  void toggleTopic(Category c) {
    if (followedTopics.contains(c)) {
      followedTopics.remove(c);
    } else {
      followedTopics.add(c);
    }
    _prefs.setStringList('topics', followedTopics.map((c) => c.name).toList());
    notifyListeners();
  }

  void toggleMute(Category c) {
    if (!profile.muted.remove(c)) profile.muted.add(c);
    _prefs.setString('profile', profile.toJsonString());
    notifyListeners();
  }

  // ---- Engagement signals (all on-device) ----
  Timer? _saveProfileTimer;
  /// Tests set this to false to avoid timers outliving a widget test.
  static bool debounceSaves = true;

  void _saveProfileSoon() {
    if (!debounceSaves) {
      _prefs.setString('profile', profile.toJsonString());
      return;
    }
    _saveProfileTimer?.cancel();
    _saveProfileTimer = Timer(const Duration(seconds: 3), () => _prefs.setString('profile', profile.toJsonString()));
  }

  void recordOpen(Story s) {
    profile.recordOpen(s);
    _saveProfileSoon();
  }

  void recordImpression(Story s) {
    profile.recordImpression(s);
    _saveProfileSoon();
  }

  void recordDwell(Story s, Duration d) {
    profile.recordDwell(s, d);
    _saveProfileSoon();
  }

  void recordClickThrough(Story s, Article a) {
    profile.recordClickThrough(s, a);
    _saveProfileSoon();
  }

  void recordShare(Story s) {
    profile.recordShare(s);
    _saveProfileSoon();
  }

  void moreLikeThis(Story s) {
    profile.moreLikeThis(s);
    _saveProfileSoon();
    notifyListeners();
  }

  void lessLikeThis(Story s) {
    profile.lessLikeThis(s);
    _saveProfileSoon();
    notifyListeners();
  }

  void toggleHiddenSource(String domain) {
    if (!profile.hiddenSources.remove(domain)) profile.hiddenSources.add(domain);
    _saveProfileSoon();
    notifyListeners();
  }

  // ---- Instant-start snapshot of the last feed ----
  List<Story> snapshot = [];

  void _loadSnapshot() {
    try {
      final list = jsonDecode(_prefs.getString('snapshot') ?? '[]') as List;
      final out = <Story>[];
      for (final e in list.whereType<Map<String, dynamic>>()) {
        final s = Story.fromJson(e);
        if (s == null) continue;
        final cover = e['cv'];
        if (cover is String) CoverImages.seed(s.id, cover);
        out.add(s);
      }
      bias.annotate([for (final s in out) ...s.articles]);
      snapshot = out;
    } catch (_) {
      snapshot = [];
    }
  }

  void saveSnapshot(List<Story> stories) {
    snapshot = stories;
    final data = [
      for (final s in stories.take(40)) {...s.toJson(), 'cv': CoverImages.cached(s)}
    ];
    _prefs.setString('snapshot', jsonEncode(data));
    notifyListeners(); // refreshes "Today in brief"
  }

  // ---- Home country: auto-detected from the network unless set manually ----
  bool homeCountryAuto = true;

  Future<void> detectHomeCountry() async {
    if (!homeCountryAuto || NewsRepository.offline) return;
    final cc = await CountryDetector.detect();
    if (cc == null || !homeCountryAuto || cc == settings.homeCountry) return;
    updateSettings((s) => s.homeCountry = cc);
  }

  /// [code] null = Auto (detect from network); otherwise a manual choice.
  void setHomeCountry(String? code) {
    homeCountryAuto = code == null;
    _prefs.setBool('homeCountryAuto', homeCountryAuto);
    if (code != null) {
      updateSettings((s) => s.homeCountry = code);
    } else {
      notifyListeners();
      unawaited(detectHomeCountry());
    }
  }

  // ---- Appearance: dark (default), light or follow the system ----
  String get themeMode => _prefs.getString('themeMode') ?? 'dark';

  void setThemeMode(String m) {
    _prefs.setString('themeMode', m);
    notifyListeners();
  }

  // ---- Markets watchlist ----
  List<String> get watchlist => _prefs.getStringList('watchlist') ?? Markets.defaultWatchlist;

  bool watches(String symbol) => watchlist.contains(symbol);

  void toggleWatch(String symbol) {
    if (!Markets.isValidSymbol(symbol)) return;
    final w = [...watchlist];
    if (!w.remove(symbol)) w.add(symbol);
    _prefs.setStringList('watchlist', w);
    notifyListeners();
  }

  // ---- Today in brief: what has been read ----
  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  /// How many brief stories are new since it was last opened. A new day
  /// always counts as new (returns the full count).
  int briefUnseen(List<Story> picks) {
    if (_prefs.getString('briefDay') != _today()) return picks.length >= 1 ? picks.length : 0;
    final seen = (_prefs.getStringList('briefSeen') ?? const []).toSet();
    final fresh = picks.where((s) => !seen.contains(s.title)).length;
    return fresh >= 5 ? fresh : 0;
  }

  void markBriefSeen(List<Story> picks) {
    _prefs.setString('briefDay', _today());
    final seen = {...?_prefs.getStringList('briefSeen'), ...picks.map((s) => s.title)}.toList();
    _prefs.setStringList('briefSeen', seen.length > 200 ? seen.sublist(seen.length - 200) : seen);
  }

  void resetReadingBalance() {
    profile.readLean.updateAll((_, __) => 0);
    _prefs.setString('profile', profile.toJsonString());
    notifyListeners();
  }

  // ---- Idle preloading: use quiet moments to fetch what's likely next ----
  Timer? _idleTimer;
  int _idleGen = 0;

  /// Call on every touch. After 4 s without one, preloading starts; any new
  /// touch stops it after the current small task.
  void touch() {
    if (NewsRepository.offline) return;
    _idleGen++;
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 4), _idleWork);
  }

  Future<void> _idleWork() async {
    final gen = _idleGen;
    final tasks = <Future<Object?> Function()>[
      for (final s in snapshot.take(12)) () => CoverImages.forStory(s),
      for (final c in followedTopics) () => repo.topic(c),
      for (final p in followed) () => repo.place(p),
      () => repo.dailyBrief(),
      () => Markets.load(),
      () => Markets.quotes(watchlist),
    ];
    for (final task in tasks) {
      if (gen != _idleGen) return; // user is interacting again
      try {
        await task().timeout(const Duration(seconds: 12));
      } catch (_) {}
    }
  }

  // ---- One-time tips ----
  bool tipSeen(String id) => (_prefs.getStringList('tipsSeen') ?? const []).contains(id);

  void dismissTip(String id) {
    _prefs.setStringList('tipsSeen', {...?_prefs.getStringList('tipsSeen'), id}.toList());
    notifyListeners();
  }

  // ---- First-run setup ----
  bool get onboarded => _prefs.getBool('onboardedV1') ?? false;
  void finishOnboarding() => _prefs.setBool('onboardedV1', true);

  // ---- Recent places ----
  List<Place> recentPlaces = [];

  void addRecent(Place p) {
    if (p.level == PlaceLevel.world || (recentPlaces.isNotEmpty && recentPlaces.first == p)) return;
    recentPlaces = [p, ...recentPlaces.where((x) => x != p)].take(10).toList();
    _prefs.setString('recentPlaces', jsonEncode(recentPlaces.map((e) => e.toJson()).toList()));
  }

  void setOverride(String domain, Bias? b) {
    if (b == null) {
      bias.overrides.remove(domain);
    } else {
      bias.overrides[domain] = b;
    }
    _prefs.setString('overrides', jsonEncode(bias.overrides.map((k, v) => MapEntry(k, v.code))));
    notifyListeners();
  }

  void updateSettings(void Function(FetchSettings s) change) {
    change(settings);
    _prefs
      ..setBool('useBing', settings.useBing)
      ..setBool('useGdelt', settings.useGdelt)
      ..setBool('autoSources', settings.autoSources)
      ..setBool('discoverLocal', settings.discoverLocal)
      ..setBool('lite', settings.lite)
      ..setInt('maxLocalOutlets', settings.maxLocalOutlets)
      ..setString('homeCountry', settings.homeCountry);
    notifyListeners();
  }

  void setAutoUpdate(bool v) {
    autoUpdate = v;
    _prefs.setBool('autoUpdate', v);
    notifyListeners();
  }

  void resetLearning() {
    classifier.loadJsonString('{"c":{},"d":{}}');
    profile.reset();
    _prefs
      ..remove('nbModel')
      ..setString('profile', profile.toJsonString());
    notifyListeners();
  }
}
