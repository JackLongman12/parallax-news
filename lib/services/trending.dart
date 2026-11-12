import 'package:xml/xml.dart';

import 'feed_parser.dart';
import 'net.dart';

class Trend {
  Trend(this.title, this.traffic);
  final String title;
  final String? traffic; // e.g. "200K+" searches
}

/// What people are searching for right now, from Google Trends' public
/// "trending now" feed for the reader's country (no key, updated hourly).
class Trending {
  static List<Trend>? _cache;
  static String? _geo;
  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<List<Trend>> load(String countryCode) async {
    final geo = RegExp(r'^[A-Z]{2}$').hasMatch(countryCode) ? countryCode : 'US';
    if (_cache != null && _geo == geo && DateTime.now().difference(_at) < const Duration(minutes: 20)) return _cache!;
    try {
      final body = await Net.getText('https://trends.google.com/trending/rss?geo=$geo', useCache: false);
      final doc = XmlDocument.parse(body);
      final out = <Trend>[];
      for (final item in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'item')) {
        String? child(String local) {
          for (final c in item.childElements) {
            if (c.name.local == local) return c.innerText.trim();
          }
          return null;
        }

        final title = FeedParser.cleanText(child('title') ?? '');
        if (title.isEmpty || title.length > 80) continue;
        out.add(Trend(title, child('approx_traffic')));
        if (out.length >= 20) break;
      }
      if (out.isNotEmpty) {
        _cache = out;
        _geo = geo;
        _at = DateTime.now();
      }
      return out;
    } catch (_) {
      return _cache ?? const [];
    }
  }
}
