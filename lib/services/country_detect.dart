import 'dart:io' show Platform;

import '../data/geo.dart';
import 'net.dart';

/// Works out which country the phone is in, without location permission:
///  1. the country of the current network connection (Wi-Fi or mobile data),
///     from Cloudflare's public trace endpoint (returns only `loc=XX`);
///  2. otherwise the phone's region setting (e.g. en_GB -> GB).
/// Note: a VPN makes (1) report the VPN's country.
class CountryDetector {
  static final _loc = RegExp(r'^loc=([A-Z]{2})\s*$', multiLine: true);

  /// Parses a cdn-cgi/trace response. Exposed for tests.
  static String? parseTrace(String body) {
    final cc = _loc.firstMatch(body)?.group(1);
    if (cc == null || cc == 'XX' || cc == 'T1') return null; // unknown / Tor
    return countryByCode(cc)?.code;
  }

  /// Country from a locale string like "en_US", "pt-BR" or "fr_CA.UTF-8".
  static String? fromLocale(String locale) {
    final m = RegExp(r'[_-]([A-Za-z]{2})(?:[._@]|$)').firstMatch(locale);
    return countryByCode(m?.group(1)?.toUpperCase())?.code;
  }

  static String? fromDevice() {
    try {
      return fromLocale(Platform.localeName);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> fromNetwork() async {
    try {
      final body = await Net.getText('https://www.cloudflare.com/cdn-cgi/trace',
          useCache: false, timeout: const Duration(seconds: 5));
      return parseTrace(body);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> detect() async => await fromNetwork() ?? fromDevice();
}
