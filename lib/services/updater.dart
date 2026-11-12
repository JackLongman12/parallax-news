import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  };

  static bool _allowed(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https') return false;
    return _allowedHosts.contains(u.host);
  }

  static Future<int> currentBuild() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
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
      final info = await _check();
      lastResult = info == null ? 'Up to date (checked ${_stamp()})' : 'Update ${info.version} found (${_stamp()})';
      return info;
    } catch (e) {
      lastResult = 'Check failed at ${_stamp()}: $e';
      rethrow;
    }
  }

  static Future<UpdateInfo?> _check() async {
    if (!Platform.isAndroid) return null;
    if (manifestUrl.isEmpty || !_allowed(manifestUrl)) {
      throw StateError('update source not allowed');
    }
    // Cache-buster so no proxy/CDN can serve a stale manifest.
    final manifest = '$manifestUrl?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}';
    final json = await Net.getJson(manifest, useCache: false);
    if (json is! Map) return null;
    final build = (json['build'] as num?)?.toInt() ?? 0;
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

  static Stream<UpdateProgress> install(UpdateInfo info) {
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
