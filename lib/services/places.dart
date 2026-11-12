import '../data/geo.dart';
import '../models/bias.dart';
import '../models/place.dart';
import '../models/source.dart';
import 'feed_parser.dart';
import 'net.dart';

/// Live geography + local-outlet discovery from open data:
///  * OpenStreetMap Nominatim for place search (any town, suburb, village)
///  * Wikidata (CC0) for "places within" drill-down and local news outlets.
class PlaceService {
  static const _sparql = 'https://query.wikidata.org/sparql';

  /// Validates a Wikidata id so it can be safely embedded in SPARQL.
  static bool isQid(String? s) => s != null && RegExp(r'^Q\d{1,12}$').hasMatch(s);
  static bool _isIso2(String? s) => s != null && RegExp(r'^[A-Z]{2}$').hasMatch(s);

  static DateTime _lastNominatim = DateTime.fromMillisecondsSinceEpoch(0);

  /// Search any place on earth (respects Nominatim's 1 req/sec policy).
  static Future<List<Place>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final wait = const Duration(milliseconds: 1100) - DateTime.now().difference(_lastNominatim);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _lastNominatim = DateTime.now();
    final url = 'https://nominatim.openstreetmap.org/search?format=jsonv2&addressdetails=1'
        '&extratags=1&limit=15&accept-language=en&q=${Uri.encodeQueryComponent(q)}';
    final json = await Net.getJson(url);
    if (json is! List) return const [];
    final out = <Place>[];
    final seen = <String>{};
    for (final r in json) {
      if (r is! Map) continue;
      final p = _fromNominatim(r);
      if (p != null && seen.add(p.id)) out.add(p);
    }
    return out;
  }

  static Place? _fromNominatim(Map r) {
    final addr = (r['address'] as Map?) ?? const {};
    final type = (r['addresstype'] ?? r['type'] ?? '').toString();
    final level = _levelFor(type);
    if (level == null) return null;
    final cc = addr['country_code']?.toString().toUpperCase();
    final name = FeedParser.cleanText((r['name']?.toString().isNotEmpty ?? false)
        ? r['name'].toString()
        : (r['display_name']?.toString().split(',').first ?? ''));
    if (name.isEmpty) return null;

    if (level == PlaceLevel.country && cc != null) {
      final c = countryByCode(cc);
      if (c != null) return c.place;
    }

    final parents = <String>[];
    for (final k in const ['city', 'town', 'municipality', 'county', 'state_district', 'state', 'province', 'region', 'country']) {
      final raw = addr[k]?.toString();
      final v = raw == null ? null : FeedParser.cleanText(raw);
      if (v != null && v != name && !parents.contains(v)) parents.add(v);
    }
    final qid = (r['extratags'] as Map?)?['wikidata']?.toString();
    final country = countryByCode(cc);
    return Place(
      id: isQid(qid) ? 'wd:$qid' : 'osm:${r['osm_type']}${r['osm_id']}',
      name: name,
      level: level,
      countryCode: cc,
      continentCode: country?.continent,
      parents: parents,
      wikidataId: isQid(qid) ? qid : null,
    );
  }

  static PlaceLevel? _levelFor(String t) {
    switch (t) {
      case 'country':
        return PlaceLevel.country;
      case 'state':
      case 'province':
      case 'region':
      case 'territory':
        return PlaceLevel.region;
      case 'county':
      case 'state_district':
      case 'district':
        return PlaceLevel.district;
      case 'city':
      case 'town':
      case 'municipality':
        return PlaceLevel.city;
      case 'village':
      case 'suburb':
      case 'neighbourhood':
      case 'quarter':
      case 'hamlet':
      case 'borough':
      case 'city_district':
      case 'island':
        return PlaceLevel.locality;
      default:
        return null;
    }
  }

  static Future<List<Map<String, dynamic>>> _query(String sparql) async {
    final url = '$_sparql?format=json&query=${Uri.encodeQueryComponent(sparql)}';
    final json = await Net.getJson(url, headers: {'Accept': 'application/sparql-results+json'});
    if (json is! Map) return const [];
    final results = json['results'];
    final rows = (results is Map ? results['bindings'] : null) as List? ?? const [];
    return rows.whereType<Map<String, dynamic>>().toList();
  }

  static String? _v(Map<String, dynamic> row, String key) => (row[key] as Map?)?['value']?.toString();
  static String? _qidFromUri(String? uri) => uri?.split('/').last;

  /// Administrative subdivisions of [parent] (states, counties, municipalities…).
  static Future<List<Place>> childrenOf(Place parent) async {
    final String subject;
    if (parent.level == PlaceLevel.country && _isIso2(parent.countryCode)) {
      subject = '?parent wdt:P297 "${parent.countryCode}" .';
    } else if (isQid(parent.wikidataId)) {
      subject = 'BIND(wd:${parent.wikidataId} AS ?parent)';
    } else {
      return const [];
    }
    final q = '''
SELECT DISTINCT ?item ?itemLabel ?pop WHERE {
  $subject
  ?parent wdt:P150 ?item .
  FILTER NOT EXISTS { ?item wdt:P576 ?dissolved }
  OPTIONAL { ?item wdt:P1082 ?pop }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en,mul". }
} LIMIT 400''';
    final rows = await _query(q);
    final byId = <String, (Place, double)>{};
    final parents = [parent.name, ...parent.parents];
    for (final r in rows) {
      final qid = _qidFromUri(_v(r, 'item'));
      final rawLabel = _v(r, 'itemLabel');
      final label = rawLabel == null ? null : FeedParser.cleanText(rawLabel);
      if (!isQid(qid) || label == null || label == qid) continue;
      final pop = double.tryParse(_v(r, 'pop') ?? '') ?? 0;
      byId[qid!] = (
        Place(
          id: 'wd:$qid',
          name: label,
          level: parent.childLevel,
          countryCode: parent.countryCode,
          continentCode: parent.continentCode,
          parents: parents,
          wikidataId: qid,
        ),
        pop
      );
    }
    final list = byId.values.toList()..sort((a, b) => a.$1.name.compareTo(b.$1.name));
    return list.map((e) => e.$1).toList();
  }

  static const _outletTypes =
      'wd:Q11032 wd:Q1110794 wd:Q1153191 wd:Q192283 wd:Q1193236 wd:Q14350 wd:Q1616075 '
      'wd:Q2001305 wd:Q41298 wd:Q2305295 wd:Q15265344 wd:Q1002697';

  /// News outlets published in / headquartered in [place] or anywhere within it.
  /// This is how genuinely local papers, radio and TV stations are found.
  static Future<List<SourceInfo>> outletsIn(Place place, {int limit = 150}) async {
    final String where;
    if (place.level == PlaceLevel.country && _isIso2(place.countryCode)) {
      where = '?c wdt:P297 "${place.countryCode}" . { ?o wdt:P17 ?c } UNION { ?o wdt:P495 ?c }';
    } else if (isQid(place.wikidataId)) {
      where = '{ ?o wdt:P291 ?loc } UNION { ?o wdt:P159 ?loc } UNION { ?o wdt:P131 ?loc } '
          '?loc wdt:P131* wd:${place.wikidataId} .';
    } else {
      return const [];
    }
    final q = '''
SELECT ?o ?oLabel ?site ?feed ?alignLabel ?ideoLabel ?ownerLabel WHERE {
  VALUES ?type { $_outletTypes }
  ?o wdt:P31 ?type .
  $where
  ?o wdt:P856 ?site .
  FILTER NOT EXISTS { ?o wdt:P576 ?end }
  OPTIONAL { ?o wdt:P1019 ?feed }
  OPTIONAL { ?o wdt:P1387 ?align }
  OPTIONAL { ?o wdt:P1142 ?ideo }
  OPTIONAL { ?o wdt:P127 ?owner }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en,mul". }
} LIMIT ${limit * 2}''';
    final rows = await _query(q);
    final byQid = <String, SourceInfo>{};
    for (final r in rows) {
      final qid = _qidFromUri(_v(r, 'o'));
      final site = _v(r, 'site');
      final rawName = _v(r, 'oLabel');
      final name = rawName == null ? null : FeedParser.cleanText(rawName);
      if (qid == null || site == null || name == null || !isSafeWebUrl(site)) continue;
      if (byQid.containsKey(qid) && byQid[qid]!.feedUrl != null) continue;
      final feed = _v(r, 'feed');
      final align = _v(r, 'alignLabel') ?? _v(r, 'ideoLabel');
      final bias = align == null ? Bias.unrated : biasFromWikidataLabel(align);
      byQid[qid] = SourceInfo(
        domain: domainOf(site),
        name: name,
        bias: bias,
        country: place.countryCode,
        owner: _v(r, 'ownerLabel'),
        origin: bias == Bias.unrated ? RatingOrigin.none : RatingOrigin.wikidata,
        alignmentLabel: align,
        feedUrl: feed != null && isSafeWebUrl(feed) ? feed : null,
        wikidataId: qid,
        isLocal: place.level != PlaceLevel.country,
      );
      if (byQid.length >= limit) break;
    }
    return byQid.values.where((s) => s.domain.isNotEmpty).toList();
  }
}
