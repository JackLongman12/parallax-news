import 'dart:async';
import 'dart:convert';
import 'dart:io' show InternetAddress;

import 'package:http/http.dart' as http;

class NetException implements Exception {
  NetException(this.message, {this.status});
  final String message;

  /// HTTP status when the failure was an HTTP error (e.g. 429 rate limit).
  final int? status;
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
    Duration timeout = const Duration(seconds: 10),
    bool useCache = true,
    /// If set, read at most this many bytes and return the (partial) prefix
    /// instead of failing — used to grab <head> metadata from article pages.
    int? headBytes,
  }) async {
    final parsed = Uri.tryParse(url);
    if (parsed == null || !(parsed.scheme == 'https' || parsed.scheme == 'http')) {
      throw NetException('Refusing non-http URL');
    }
    // Cleartext is disabled app-wide; upgrade instead of failing.
    final uri = parsed.scheme == 'http' ? parsed.replace(scheme: 'https') : parsed;
    if (!isPublicHost(uri.host) || !await _resolvesPublic(uri.host)) {
      throw NetException('Refusing private/local address');
    }
    if (useCache) {
      final hit = _cache[url];
      if (hit != null && DateTime.now().difference(hit.at) < _ttl) return hit.body;
    }
    // Follow redirects by hand so every hop is checked against [isPublicHost].
    var current = uri;
    late http.StreamedResponse res;
    for (var hop = 0;; hop++) {
      final req = http.Request('GET', current)
        ..headers['User-Agent'] = userAgent
        ..headers['Accept'] = 'application/rss+xml, application/atom+xml, application/json, text/xml, */*'
        ..followRedirects = false;
      if (headers != null) req.headers.addAll(headers);
      res = await _client.send(req).timeout(timeout);
      final loc = res.headers['location'];
      if (res.statusCode >= 300 && res.statusCode < 400 && loc != null) {
        unawaited(res.stream.drain<void>().catchError((_) {}));
        if (hop >= 5) throw NetException('Too many redirects from ${uri.host}');
        var next = current.resolve(loc);
        if (next.scheme == 'http') next = next.replace(scheme: 'https');
        if (next.scheme != 'https' || !isPublicHost(next.host) || !await _resolvesPublic(next.host)) {
          throw NetException('Blocked redirect from ${uri.host}');
        }
        current = next;
        continue;
      }
      break;
    }
    if (res.statusCode != 200) {
      // Drain so the connection can be reused.
      unawaited(res.stream.drain<void>().catchError((_) {}));
      throw NetException('HTTP ${res.statusCode} from ${uri.host}', status: res.statusCode);
    }
    final declared = res.contentLength;
    if (headBytes == null && declared != null && declared > maxBytes) {
      unawaited(res.stream.drain<void>().catchError((_) {}));
      throw NetException('Response too large from ${uri.host}');
    }
    final bytes = <int>[];
    // Breaking out of await-for cancels the download.
    await for (final chunk in res.stream.timeout(timeout)) {
      bytes.addAll(chunk);
      if (headBytes != null && bytes.length >= headBytes) break;
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

  static final Map<String, bool> _dnsOk = {};

  /// Blocks DNS tricks where a public-looking name resolves to a LAN/loopback IP.
  static Future<bool> _resolvesPublic(String host) async {
    final cached = _dnsOk[host];
    if (cached != null) return cached;
    bool ok;
    try {
      final addrs = await InternetAddress.lookup(host).timeout(const Duration(seconds: 5));
      ok = addrs.isNotEmpty && addrs.every((a) => isPublicHost(a.address));
    } catch (_) {
      // Lookup failed: the request itself will fail too; don't cache.
      return true;
    }
    if (_dnsOk.length > 500) _dnsOk.clear();
    _dnsOk[host] = ok;
    return ok;
  }
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

/// Feed URLs come from editable sources (Wikidata, feeds). Don't let them make
/// the phone talk to its own LAN / loopback (SSRF-style probing).
bool isPublicHost(String host) {
  final h = host.toLowerCase();
  if (h.isEmpty || h == 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') ||
      h.endsWith('.internal') || h.endsWith('.lan')) {
    return false;
  }
  if (h.contains(':')) {
    // IPv6 literal: block loopback, link-local, unique-local.
    final v6 = h.replaceAll('[', '').replaceAll(']', '');
    if (v6.startsWith('::ffff:')) return isPublicHost(v6.substring(7)); // IPv4-mapped
    return !(v6 == '::1' || v6 == '::' || v6.startsWith('fe80') || v6.startsWith('fc') || v6.startsWith('fd'));
  }
  final parts = h.split('.');
  if (parts.length == 4 && parts.every((p) => int.tryParse(p) != null)) {
    final o = parts.map(int.parse).toList();
    if (o[0] == 10 || o[0] == 127 || o[0] == 0) return false;
    if (o[0] == 169 && o[1] == 254) return false;
    if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return false;
    if (o[0] == 192 && o[1] == 168) return false;
    if (o[0] == 100 && o[1] >= 64 && o[1] <= 127) return false;
  }
  return true;
}

/// Only http(s) links may be opened from feed content.
bool isSafeWebUrl(String url) {
  final u = Uri.tryParse(url);
  return u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.isNotEmpty;
}
