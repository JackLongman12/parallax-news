import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'net.dart';

class UpdateInfo {
  UpdateInfo({required this.version, required this.build, required this.url, this.sha256, this.notes = ''});
  final String version;
  final int build;
  final String url;
  final String? sha256;
  final String notes;
}

class UpdateProgress {
  UpdateProgress(this.stage, {this.percent, this.error});
  final String stage; // downloading | installing | error
  final int? percent;
  final String? error;
}

/// Checks a small JSON manifest at startup and, if a newer build exists,
/// downloads the APK and hands it to the Android package installer.
///
/// Safety: manifest + APK must be HTTPS on an allow-listed host, the APK's
/// SHA-256 is verified, and Android itself refuses any APK not signed with the
/// same key as the installed app.
class Updater {
  static const manifestUrl = String.fromEnvironment(
    'UPDATE_MANIFEST_URL',
    defaultValue: 'https://github.com/JackLongman12/parallax-news/releases/latest/download/latest.json',
  );

  static const _allowedHosts = {
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
    'raw.githubusercontent.com',
    'api.github.com',
  };

  static bool _allowed(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https') return false;
    return _allowedHosts.contains(u.host);
  }

  /// This install's build: the N in version name 0.1.N. (Android's version
  /// code is 2000+N or 1000+N for per-CPU APKs, so it can't be compared.)
  static Future<int> currentBuild() async {
    final info = await PackageInfo.fromPlatform();
    final m = RegExp(r'(\d+)$').firstMatch(info.version);
    if (m != null) return int.parse(m[1]!);
    return (int.tryParse(info.buildNumber) ?? 0) % 1000;
  }

  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  /// Result of the most recent check, shown in Settings for troubleshooting.
  static String lastResult = 'Not checked yet';

  static String _stamp() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  static Future<UpdateInfo?> check() async {
    try {
      final info = await _check().timeout(const Duration(seconds: 25));
      lastResult = info == null ? 'Up to date (checked ${_stamp()})' : 'Update ${info.version} found (${_stamp()})';
      return info;
    } catch (e) {
      lastResult = 'Check failed at ${_stamp()}: $e';
      rethrow;
    }
  }

  /// Build number of a manifest, comparable with [currentBuild].
  static int _build(Map j) {
    final run = j['run'];
    if (run is num) return run.toInt();
    return ((j['build'] as num?)?.toInt() ?? 0) % 1000;
  }

  static Future<Map?> _manifest(String url) async {
    try {
      final j = await Net.getJson(url, useCache: false);
      return j is Map ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// latest.json of the newest non-prerelease, read via the GitHub API.
  static Future<Map?> _manifestFromApi() async {
    final m = RegExp(r'^https://github\.com/([\w.-]+)/([\w.-]+)/releases/').firstMatch(manifestUrl);
    if (m == null) return null;
    try {
      final list = await Net.getJson('https://api.github.com/repos/${m[1]}/${m[2]}/releases?per_page=5',
          headers: {'Accept': 'application/vnd.github+json'}, useCache: false);
      if (list is! List) return null;
      for (final r in list.whereType<Map>()) {
        if (r['prerelease'] == true || r['draft'] == true) continue;
        for (final a in (r['assets'] as List? ?? const []).whereType<Map>()) {
          final u = a['browser_download_url'];
          if (a['name'] == 'latest.json' && u is String && _allowed(u)) return _manifest(u);
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<UpdateInfo?> _check() async {
    if (!Platform.isAndroid) return null;
    if (manifestUrl.isEmpty || !_allowed(manifestUrl)) {
      throw StateError('update source not allowed');
    }
    // Two independent sources, newest wins: GitHub's "latest" redirect can lag
    // for a while after a release, so the newest release is also read from
    // the API. Either one failing alone is fine.
    final results = await Future.wait([
      _manifest('$manifestUrl?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}'),
      _manifestFromApi(),
    ]);
    Map? json;
    for (final j in results) {
      if (j == null) continue;
      if (json == null || _build(j) > _build(json)) json = j;
    }
    if (json == null) throw StateError('could not reach GitHub');
    final build = _build(json);
    final android = json['android'];
    if (android is! Map) return null;
    // Pick the APK built for this phone's CPU (64-bit vs 32-bit ARM).
    var url = android['url']?.toString() ?? '';
    var shaRaw = android['sha256'];
    final abis = android['abis'];
    if (abis is Map) {
      final mine = Platform.version.contains('arm64') ? 'arm64' : (Platform.version.contains('_arm') ? 'arm' : 'arm64');
      final pick = abis[mine];
      if (pick is Map && pick['url'] is String) {
        url = pick['url'] as String;
        shaRaw = pick['sha256'];
      }
    }
    if (!_allowed(url)) throw StateError('APK host not allowed');
    // Checksum is mandatory: never install an unverified download.
    final sha = shaRaw?.toString();
    if (sha == null || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha)) return null;
    final mine = await currentBuild();
    if (build <= mine) return null;
    return UpdateInfo(
      version: json['version']?.toString() ?? '$build',
      build: build,
      url: url,
      sha256: sha,
      notes: (json['notes']?.toString() ?? '').trim(),
    );
  }

  /// Deletes update APKs left behind by earlier updates (each is ~20-60 MB).
  /// Only touches files this app created (parallax_news_*.apk) inside its own
  /// private folders; never follows links.
  static Future<int> cleanOldApks({String? keep}) async {
    if (!Platform.isAndroid) return 0;
    final dirs = <Directory>[];
    Future<void> add(Future<Directory?> Function() f) async {
      try {
        final d = await f();
        if (d != null) dirs.add(d);
      } catch (_) {}
    }

    await add(getApplicationSupportDirectory);
    await add(() async => (await getApplicationDocumentsDirectory()).parent);
    await add(getExternalStorageDirectory);
    await add(getTemporaryDirectory);
    var freed = 0;
    final seen = <String>{};
    for (final d in dirs) {
      try {
        await for (final e in d.list(recursive: true, followLinks: false)) {
          if (e is! File || !seen.add(e.path)) continue;
          final name = e.uri.pathSegments.isEmpty ? '' : e.uri.pathSegments.last;
          if (!name.startsWith('parallax_news_') || !name.endsWith('.apk') || name == keep) continue;
          try {
            freed += await e.length();
            await e.delete();
          } catch (_) {}
        }
      } catch (_) {}
    }
    return freed;
  }

  static Stream<UpdateProgress> install(UpdateInfo info) {
    unawaited(cleanOldApks(keep: 'parallax_news_${info.build}.apk'));
    final controller = StreamController<UpdateProgress>();
    try {
      final stream = OtaUpdate().execute(
        info.url,
        destinationFilename: 'parallax_news_${info.build}.apk',
        sha256checksum: info.sha256,
      );
      stream.listen(
        (OtaEvent e) {
          if (e.status == OtaStatus.DOWNLOADING) {
            controller.add(UpdateProgress('downloading', percent: int.tryParse(e.value ?? '')));
          } else if (e.status == OtaStatus.INSTALLING) {
            controller.add(UpdateProgress('installing'));
          } else {
            controller.add(UpdateProgress('error', error: '${e.status.name} ${e.value ?? ''}'.trim()));
          }
        },
        onError: (Object err) {
          controller.add(UpdateProgress('error', error: err.toString()));
          controller.close();
        },
        onDone: controller.close,
      );
    } catch (err) {
      if (kDebugMode) debugPrint('update failed: $err');
      controller.add(UpdateProgress('error', error: err.toString()));
      controller.close();
    }
    return controller.stream;
  }
}
