import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crawler_feed.dart';
import 'net.dart';

/// Sends anonymous crash reports to our Cloudflare worker (POST /crash).
///
/// A report holds only the error, its stack trace, the app version and the
/// Android version: no reading history, places or identifiers. Reports
/// that can't be sent (offline) wait in a small file and go out on the next
/// start. At most 5 per session, each distinct error once.
class CrashReporter {
  static const _prefKey = 'crashReports';
  static bool enabled = true;
  static final _sent = <String>{};
  static String _version = '?';

  static Future<void> init() async {
    try {
      enabled = (await SharedPreferences.getInstance()).getBool(_prefKey) ?? true;
      final info = await PackageInfo.fromPlatform();
      _version = '${info.version}+${info.buildNumber}';
    } catch (_) {}

    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      prevFlutter?.call(details);
      report(details.exception, details.stack, fatal: false, context: details.context?.toDescription());
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, fatal: true);
      return true; // handled: don't kill the app over an async error
    };
    unawaited(_flushQueue());
  }

  static Future<void> setEnabled(bool v) async {
    enabled = v;
    try {
      (await SharedPreferences.getInstance()).setBool(_prefKey, v);
    } catch (_) {}
  }

  static bool get _configured => CrawlerFeed.workerUrl.startsWith('https://') && !kDebugMode;

  static void report(Object error, StackTrace? stack, {bool fatal = false, String? context}) {
    if (!enabled || !_configured) return;
    // Lost connections etc. are expected on phones, not bugs.
    if (error is SocketException || error is TimeoutException || error is HttpException || error is http.ClientException) {
      return;
    }
    final text = '${error.runtimeType}: $error'.trim();
    final key = text.length > 200 ? text.substring(0, 200) : text;
    if (_sent.length >= 5 || !_sent.add(key)) return;
    final body = {
      'error': context == null ? text : '$text\n(while $context)',
      'stack': (stack ?? StackTrace.current).toString(),
      'version': _version,
      'os': 'Android ${Platform.operatingSystemVersion}',
      'fatal': fatal,
    };
    unawaited(_send(body).then((ok) => ok ? null : _queue(body)));
  }

  static Future<bool> _send(Map<String, Object?> body) async {
    try {
      final payload = jsonEncode(body);
      final r = await http
          .post(Uri.parse('${CrawlerFeed.workerUrl}/crash'),
              headers: {'Content-Type': 'application/json', 'User-Agent': Net.userAgent},
              body: payload.length > 15000 ? payload.substring(0, 15000) : payload)
          .timeout(const Duration(seconds: 10));
      return r.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  static Future<File?> _file() async {
    try {
      return File('${(await getApplicationSupportDirectory()).path}/crash_queue.json');
    } catch (_) {
      return null;
    }
  }

  static Future<void> _queue(Map<String, Object?> body) async {
    final f = await _file();
    if (f == null) return;
    try {
      final list = await f.exists() ? (jsonDecode(await f.readAsString()) as List) : <dynamic>[];
      list.add(body);
      await f.writeAsString(jsonEncode(list.length > 5 ? list.sublist(list.length - 5) : list));
    } catch (_) {}
  }

  static Future<void> _flushQueue() async {
    if (!enabled || !_configured) return;
    final f = await _file();
    if (f == null || !await f.exists()) return;
    try {
      final list = jsonDecode(await f.readAsString());
      await f.delete();
      if (list is! List) return;
      for (final b in list.whereType<Map>()) {
        if (!await _send(Map<String, Object?>.from(b))) await _queue(Map<String, Object?>.from(b));
      }
    } catch (_) {}
  }
}
