import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/article.dart';
import '../models/bias.dart';
import '../models/source.dart';
import 'net.dart';

/// Resolves a publisher domain to its rating. Priority:
/// user override > curated catalog > Wikidata (discovered live) > unrated.
class BiasService {
  final Map<String, SourceInfo> _curated = {};
  final Map<String, SourceInfo> _discovered = {};
  Map<String, Bias> overrides = {};

  /// Domains already queried on Wikidata (so we don't ask again).
  final Set<String> lookedUp = {};

  /// Optional URL of an updated catalog (same format as assets/sources.json),
  /// so ratings can be fixed without shipping a new app build.
  static const remoteCatalogUrl = String.fromEnvironment('CATALOG_URL', defaultValue: '');

  Future<void> load() async {
    final raw = await rootBundle.loadString('assets/sources.json');
    _ingest(raw);
  }

  Future<void> refreshRemote() async {
    if (remoteCatalogUrl.isEmpty || !remoteCatalogUrl.startsWith('https://')) return;
    try {
      _ingest(await Net.getText(remoteCatalogUrl, useCache: false));
    } catch (_) {
      // Offline or unavailable: keep bundled catalog.
    }
  }

  void _ingest(String raw) {
    final json = jsonDecode(raw);
    final list = (json is Map ? json['sources'] : null) as List? ?? const [];
    for (final e in list) {
      if (e is Map<String, dynamic> && isValidCatalogEntry(e)) {
        final s = SourceInfo.fromCatalog(e);
        _curated[s.domain] = s;
      }
    }
  }

  static final _domainRe = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$');

  /// Rejects malformed or hostile entries (the catalog can be updated remotely).
  static bool isValidCatalogEntry(Map<String, dynamic> e) {
    final d = e['d'], n = e['n'], rss = e['rss'];
    if (d is! String || n is! String) return false;
    if (d.length > 100 || n.isEmpty || n.length > 120) return false;
    if (!_domainRe.hasMatch(d.toLowerCase()) || !isPublicHost(d)) return false;
    if (rss != null) {
      if (rss is! String) return false;
      final u = Uri.tryParse(rss);
      if (u == null || u.scheme != 'https' || !isPublicHost(u.host)) return false;
    }
    return true;
  }

  Iterable<SourceInfo> get curated => _curated.values;
  Iterable<SourceInfo> get discovered => _discovered.values;

  void addDiscovered(Iterable<SourceInfo> sources) {
    for (final s in sources) {
      final existing = _discovered[s.domain];
      if (existing == null || (existing.bias == Bias.unrated && s.bias != Bias.unrated)) {
        _discovered[s.domain] = s;
      } else if (s.isLocal && !existing.isLocal) {
        _discovered[s.domain] = existing.copyWith(isLocal: true);
      }
    }
  }

  /// Looks up the domain and each parent domain (edition.cnn.com -> cnn.com).
  SourceInfo lookup(String domain, {String? name}) {
    final d = domain.toLowerCase();
    SourceInfo? found;
    var probe = d;
    while (true) {
      found = _curated[probe] ?? _discovered[probe];
      if (found != null) break;
      final dot = probe.indexOf('.');
      if (dot < 0 || probe.indexOf('.', dot + 1) < 0) break;
      probe = probe.substring(dot + 1);
    }
    // A discovered (Wikidata) entry may still be local while curated has the rating.
    final disc = _discovered[d];
    var info = found ?? SourceInfo(domain: d, name: name ?? d);
    if (disc != null && disc.isLocal && !info.isLocal) info = info.copyWith(isLocal: true);

    final ov = overrides[info.domain] ?? overrides[d];
    if (ov != null) info = info.copyWith(bias: ov, origin: RatingOrigin.userOverride);
    return info;
  }

  void annotate(List<Article> articles) {
    for (final a in articles) {
      final s = lookup(a.domain, name: a.sourceName);
      a.source = s;
      if (s.isLocal) a.isLocal = true;
      if (a.hintCategory == null && s.topics.isNotEmpty) a.hintCategory = s.topics.first;
    }
  }
}
