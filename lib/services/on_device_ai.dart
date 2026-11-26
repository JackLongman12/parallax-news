import 'package:flutter/services.dart';

/// Whether this phone can write summaries on-device (Gemini Nano via AICore).
enum AiStatus { available, downloadable, downloading, unavailable }

/// Talks to the native side (android/.../GenAiBridge.kt). Every call fails
/// soft: on iOS, desktop, tests, or a phone without Gemini Nano the feature
/// reports [AiStatus.unavailable] and the UI hides itself.
class OnDeviceAi {
  static const _channel = MethodChannel('parallax/genai');
  static Future<AiStatus>? _status;

  static Future<AiStatus> status() => _status ??= _probe();

  static Future<AiStatus> _probe() async {
    try {
      final s = await _channel.invokeMethod<String>('status');
      return switch (s) {
        'available' => AiStatus.available,
        'downloadable' => AiStatus.downloadable,
        'downloading' => AiStatus.downloading,
        _ => AiStatus.unavailable,
      };
    } catch (_) {
      return AiStatus.unavailable;
    }
  }

  /// Returns up to [bullets] short bullet lines, or null if it could not run.
  static Future<List<String>?> summarize(String text, {int bullets = 3}) async {
    try {
      final out = await _channel.invokeMethod<String>('summarize', {'text': text, 'bullets': bullets});
      if (out == null) return null;
      final lines = out
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^\s*[-•*]\s*'), '').trim())
          .where((l) => l.isNotEmpty)
          .toList();
      return lines.isEmpty ? null : lines;
    } catch (_) {
      return null;
    }
  }
}
