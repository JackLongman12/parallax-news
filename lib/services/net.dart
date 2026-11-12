import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class NetException implements Exception {
  NetException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Small HTTP helper: one shared client, timeouts, size cap, and a short
/// in-memory cache so revisiting a screen doesn't re-download everything
/// (important on slow connections / weak phones).
class Net {
  Net._();

  static final http.Client _client = http.Client();
  static const userAgent = 'ParallaxNews/0.1 (open-source news reader; Android)';

  /// Feeds bigger than this are rejected to protect low-memory devices.
  static const maxBytes = 4 * 1024 * 1024;

  static final Map<String, _CacheEntry> _cache = {};
  static const _ttl = Duration(minutes: 10);

  static Future<String> getText(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 15),
    bool useCache = true,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      throw NetException('Refusing non-http URL');
    }
    if (useCache) {
      final hit = _cache[url];
      if (hit != null && DateTime.now().difference(hit.at) < _ttl) return hit.body;
    }
    final req = http.Request('GET', uri)
      ..headers['User-Agent'] = userAgent
      ..headers['Accept'] = 'application/rss+xml, application/atom+xml, application/json, text/xml, */*'
      ..followRedirects = true
      ..maxRedirects = 5;
    if (headers != null) req.headers.addAll(headers);

    final res = await _client.send(req).timeout(timeout);
    if (res.statusCode != 200) {
      // Drain so the connection can be reused.
      unawaited(res.stream.drain<void>().catchError((_) {}));
      throw NetException('HTTP ${res.statusCode} from ${uri.host}');
    }
    final declared = res.contentLength;
    if (declared != null && declared > maxBytes) {
      unawaited(res.stream.drain<void>().catchError((_) {}));
      throw NetException('Response too large from ${uri.host}');
    }
    final bytes = <int>[];
    await for (final chunk in res.stream.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) throw NetException('Response too large from ${uri.host}');
    }
    final body = utf8.decode(bytes, allowMalformed: true);
    if (useCache) {
      if (_cache.length > 200) _cache.clear();
      _cache[url] = _CacheEntry(body, DateTime.now());
    }
    return body;
  }

  static Future<dynamic> getJson(String url, {Map<String, String>? headers, bool useCache = true}) async {
    final text = await getText(url, headers: headers, useCache: useCache);
    return jsonDecode(text);
  }

  static void clearCache() => _cache.clear();
}

class _CacheEntry {
  _CacheEntry(this.body, this.at);
  final String body;
  final DateTime at;
}

/// Runs [tasks] with at most [concurrency] in flight. Failed tasks yield null.
Future<List<T?>> runPooled<T>(List<Future<T> Function()> tasks, {int concurrency = 4}) async {
  final results = List<T?>.filled(tasks.length, null);
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= tasks.length) return;
      try {
        results[i] = await tasks[i]();
      } catch (_) {
        results[i] = null;
      }
    }
  }

  await Future.wait(List.generate(
      concurrency < tasks.length ? concurrency : tasks.length, (_) => worker()));
  return results;
}

/// Lower-cased host without a leading "www." / "m." / "amp.".
String domainOf(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  for (final p in const ['www.', 'm.', 'amp.', 'mobile.']) {
    if (host.startsWith(p)) return host.substring(p.length);
  }
  return host;
}

/// Only http(s) links may be opened from feed content.
bool isSafeWebUrl(String url) {
  final u = Uri.tryParse(url);
  return u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.isNotEmpty;
}
