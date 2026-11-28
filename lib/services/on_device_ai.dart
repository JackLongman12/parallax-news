import 'dart:io';

import 'package:flutter/services.dart';

/// Whether this phone can write summaries on-device (Gemini Nano via AICore).
enum AiStatus { available, downloadable, downloading, unavailable }

/// Talks to the native side (android/.../GenAiBridge.kt). Every call fails
/// soft: on iOS, desktop, tests, or a phone without Gemini Nano the feature
/// reports [AiStatus.unavailable], with the reason in [detail].
class OnDeviceAi {
  static const _channel = MethodChannel('parallax/genai');
  static bool _ready = false;

  /// Summaries already written this session, by story (and its size, so a
  /// story that gained outlets gets a fresh summary).
  static final Map<String, List<String>> _cache = {};
  static List<String>? cached(String key) => _cache[key];

  /// Why the last check did not return "available" (shown to the user).
  static String? detail;

  static bool get supportedPlatform => Platform.isAndroid;

  /// What the user can do about [detail], based on AICore's documented error codes.
  static String get advice {
    final d = (detail ?? '').toLowerCase();
    if (d.contains('606') || d.contains('feature_not_found')) {
      return 'AICore has not finished downloading its setup yet. Leave the phone on Wi-Fi and charging '
          'for a few hours, then check again.';
    }
    if (d.contains('601') || d.contains('binding')) {
      return 'Parallax could not connect to AICore. Update AICore in the Play Store, then uninstall '
          'and reinstall Parallax.';
    }
    if (d.contains('bootloader')) return 'Gemini Nano does not run on phones with an unlocked bootloader.';
    if (d.contains('host') || d.contains('download_error')) {
      return 'AICore could not reach Google to download the model. Check your connection and try again.';
    }
    if (d.contains('background')) return 'Keep Parallax open on screen while it summarises.';
    return 'Update AICore in the Play Store, keep the phone on Wi-Fi for a while, then check again.';
  }

  /// Asks the phone each time until it says "available", so a finished
  /// download or an AICore update shows up without restarting the app.
  static Future<AiStatus> status() async {
    if (_ready) return AiStatus.available;
    try {
      final s = await _channel.invokeMethod<String>('status') ?? '';
      final parts = s.split(':');
      detail = parts.length > 1 ? parts.sublist(1).join(':').trim() : null;
      final st = switch (parts.first) {
        'available' => AiStatus.available,
        'downloadable' => AiStatus.downloadable,
        'downloading' => AiStatus.downloading,
        _ => AiStatus.unavailable,
      };
      _ready = st == AiStatus.available;
      return st;
    } on MissingPluginException {
      detail = 'This build has no on-device AI bridge.';
      return AiStatus.unavailable;
    } catch (e) {
      detail = '$e';
      return AiStatus.unavailable;
    }
  }

  /// Returns up to [bullets] short bullet lines, or null if it could not run
  /// (the reason is then in [detail]).
  static Future<List<String>?> summarize(String text, {int bullets = 3, String? key}) async {
    if (key != null && _cache[key] != null) return _cache[key];
    try {
      final out = await _channel.invokeMethod<String>('summarize', {'text': text, 'bullets': bullets});
      if (out == null) return null;
      final lines = out
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^\s*[-•*]\s*'), '').trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        _ready = true;
        if (key != null) {
          if (_cache.length > 100) _cache.clear();
          _cache[key] = lines;
        }
      }
      return lines.isEmpty ? null : lines;
    } on PlatformException catch (e) {
      detail = e.code == 'downloading' ? 'The model is still downloading. Try again in a few minutes.' : (e.message ?? e.code);
      return null;
    } catch (e) {
      detail = '$e';
      return null;
    }
  }
}
