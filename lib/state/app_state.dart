import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bias.dart';
import '../models/category.dart';
import '../models/place.dart';
import '../models/story.dart';
import '../services/bias_service.dart';
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
    final classifier = TopicClassifier();
    final settings = FetchSettings();
    final repo = NewsRepository(bias: bias, classifier: classifier, settings: settings);
    final s = AppState._(prefs, bias, classifier, repo, settings);
    s._load();
    repo.onModelUpdated = s._scheduleModelSave;
    unawaited(bias.refreshRemote());
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
      ..discoverLocal = p.getBool('discoverLocal') ?? true
      ..lite = p.getBool('lite') ?? false
      ..maxLocalOutlets = p.getInt('maxLocalOutlets') ?? 10
      ..homeCountry = p.getString('homeCountry') ?? 'US';
    autoUpdate = p.getBool('autoUpdate') ?? true;
    final model = p.getString('nbModel');
    if (model != null) classifier.loadJsonString(model);
    // Age the model once a day so it follows the current news cycle.
    final last = DateTime.tryParse(p.getString('nbDecayed') ?? '');
    if (last == null || DateTime.now().difference(last).inHours >= 24) {
      classifier.decay();
      p.setString('nbDecayed', DateTime.now().toIso8601String());
    }
    final prof = p.getString('profile');
    if (prof != null) profile.loadJsonString(prof);
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

  void recordOpen(Story s) {
    profile.recordOpen(s);
    _prefs.setString('profile', profile.toJsonString());
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
    profile.weights.clear();
    _prefs
      ..remove('nbModel')
      ..setString('profile', profile.toJsonString());
    notifyListeners();
  }
}
