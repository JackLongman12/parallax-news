import 'dart:async';
import 'dart:math' as math;

import 'net.dart';

class ProviderUnavailable implements Exception {
  ProviderUnavailable(this.provider, this.until);
  final String provider;
  final DateTime until;
  @override
  String toString() => '$provider cooling down';
}

/// Live health of one news source.
class ProviderStats {
  ProviderStats(this.name, {this.minInterval = Duration.zero});
  final String name;

  /// Minimum gap between requests (GDELT asks for ~1 request / 5s).
  final Duration minInterval;

  double avgLatencyMs = 0;
  double errorRate = 0; // exponentially weighted, 0..1
  int requests = 0;
  int consecutiveFailures = 0;
  DateTime? cooldownUntil;
  String? lastError;
  DateTime _lastStart = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _gate = Future.value();

  bool get coolingDown => cooldownUntil != null && DateTime.now().isBefore(cooldownUntil!);

  String get status {
    if (coolingDown) {
      final s = cooldownUntil!.difference(DateTime.now()).inSeconds;
      return 'Paused ${s >= 60 ? '${(s / 60).ceil()}m' : '${s}s'} (${lastError ?? 'errors'})';
    }
    if (requests == 0) return 'Ready';
    return 'OK · ${avgLatencyMs.round()} ms · ${(errorRate * 100).round()}% errors';
  }
}

/// Tracks every provider and decides who to use. Used by Auto mode:
///  * rate-limit / server errors -> exponential cool-down (30s .. 15 min)
///  * 3 failures in a row        -> cool-down
///  * enforces per-provider spacing (GDELT)
class ProviderHealth {
  ProviderHealth._();
  static final ProviderHealth instance = ProviderHealth._();

  final Map<String, ProviderStats> stats = {
    'google': ProviderStats('Google News'),
    'bing': ProviderStats('Bing News'),
    'gdelt': ProviderStats('GDELT', minInterval: const Duration(milliseconds: 5500)),
    'wikidata': ProviderStats('Wikidata'),
  };

  bool available(String p) => !(stats[p]?.coolingDown ?? false);

  /// Runs [task] for provider [p], recording latency and outcome.
  Future<T> run<T>(String p, Future<T> Function() task) async {
    final s = stats[p]!;
    if (s.coolingDown) throw ProviderUnavailable(p, s.cooldownUntil!);

    if (s.minInterval > Duration.zero) {
      // Serialise requests so they are spaced at least minInterval apart.
      final prev = s._gate;
      final done = Completer<void>();
      s._gate = done.future;
      try {
        await prev;
        final wait = s.minInterval - DateTime.now().difference(s._lastStart);
        if (!wait.isNegative) await Future<void>.delayed(wait);
        s._lastStart = DateTime.now();
      } finally {
        done.complete();
      }
    }

    final sw = Stopwatch()..start();
    try {
      final r = await task();
      _record(s, sw.elapsedMilliseconds, null);
      return r;
    } catch (e) {
      _record(s, sw.elapsedMilliseconds, e);
      rethrow;
    }
  }

  void _record(ProviderStats s, int ms, Object? error) {
    s.requests++;
    s.avgLatencyMs = s.requests == 1 ? ms.toDouble() : s.avgLatencyMs * 0.8 + ms * 0.2;
    s.errorRate = s.errorRate * 0.8 + (error == null ? 0 : 0.2);
    if (error == null) {
      s.consecutiveFailures = 0;
      return;
    }
    s.consecutiveFailures++;
    final status = error is NetException ? error.status : null;
    final rateLimited = status == 429 || status == 503 || status == 403;
    s.lastError = rateLimited ? 'rate limited' : (status != null ? 'HTTP $status' : 'failing');
    if (rateLimited || s.consecutiveFailures >= 3) {
      final step = math.min(5, s.consecutiveFailures); // 30s,60s,2m,4m,8m(,15m cap)
      final secs = math.min(900, 30 * math.pow(2, step - 1).toInt());
      s.cooldownUntil = DateTime.now().add(Duration(seconds: secs));
    }
  }

  /// Test hook.
  void reset() {
    for (final s in stats.values) {
      s
        ..avgLatencyMs = 0
        ..errorRate = 0
        ..requests = 0
        ..consecutiveFailures = 0
        ..cooldownUntil = null
        ..lastError = null;
    }
  }
}
