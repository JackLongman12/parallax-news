import 'package:xml/xml.dart';

import '../models/article.dart';
import '../models/category.dart';
import 'net.dart';

/// Parses RSS 2.0 and Atom feeds, including Google News and Bing News quirks.
class FeedParser {
  static List<Article> parse(
    String body, {
    required String provider,
    String? sourceName,
    String? sourceDomain,
    Category? hint,
    bool isLocal = false,
    int maxItems = 60,
  }) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(body);
    } catch (_) {
      return const [];
    }
    final out = <Article>[];
    final elements = doc.descendants.whereType<XmlElement>();
    final items = elements.where((e) => e.name.local == 'item' || e.name.local == 'entry');
    for (final item in items) {
      if (out.length >= maxItems) break;
      final a = _parseItem(item, provider, sourceName, sourceDomain, hint, isLocal);
      if (a != null) out.add(a);
    }
    return out;
  }

  static Article? _parseItem(XmlElement item, String provider, String? sourceName,
      String? sourceDomain, Category? hint, bool isLocal) {
    var title = cleanText(_childText(item, 'title') ?? '');
    if (title.isEmpty) return null;

    // Link: RSS <link>text</link> or Atom <link href=".." rel="alternate"/>.
    String? link;
    for (final l in item.childElements.where((e) => e.name.local == 'link')) {
      final href = l.getAttribute('href');
      final rel = l.getAttribute('rel');
      if (href != null && (rel == null || rel == 'alternate')) {
        link = href;
        break;
      }
      final t = l.innerText.trim();
      if (t.isNotEmpty) {
        link = t;
        break;
      }
    }
    link ??= _childText(item, 'guid');
    if (link == null) return null;
    link = link.trim();

    // Bing wraps the real URL in an apiclick redirect.
    if (provider == 'bing') {
      final u = Uri.tryParse(link);
      final real = u?.queryParameters['url'];
      if (real != null && real.isNotEmpty) link = real;
    }
    if (!isSafeWebUrl(link)) return null;

    // Publisher: Google <source url="...">Name</source>, Bing <News:Source>.
    var name = sourceName;
    var domain = sourceDomain;
    final srcEl = _child(item, 'source');
    if (srcEl != null) {
      final srcUrl = srcEl.getAttribute('url');
      final srcName = srcEl.innerText.trim();
      if (srcName.isNotEmpty) name = srcName;
      if (srcUrl != null && srcUrl.isNotEmpty) domain = domainOf(srcUrl);
    }
    domain ??= domainOf(link);
    name ??= domain;

    // Google News appends " - Publisher" to titles.
    if (provider == 'google' && name.isNotEmpty && title.endsWith(' - $name')) {
      title = title.substring(0, title.length - name.length - 3).trim();
    }

    final dateText = _childText(item, 'pubDate') ??
        _childText(item, 'published') ??
        _childText(item, 'updated') ??
        _childText(item, 'date');
    final published = dateText == null ? null : parseFeedDate(dateText);

    var snippet = _childText(item, 'description') ?? _childText(item, 'summary') ?? '';
    snippet = cleanText(snippet);
    if (snippet.length > 280) snippet = '${snippet.substring(0, 277)}...';
    // Google's description is just the headline + publisher again.
    if (provider == 'google') snippet = '';

    // Pick the LARGEST image offered (feeds often list a tiny thumbnail first).
    String? image;
    var bestWidth = -1;
    void consider(String? u, int width) {
      // Images load outside our Net guard, so only allow public HTTPS hosts.
      final iu = u == null ? null : Uri.tryParse(u.trim());
      if (iu == null || iu.scheme != 'https' || !isPublicHost(iu.host)) return;
      if (width > bestWidth) {
        bestWidth = width;
        image = iu.toString();
      }
    }

    final mediaEls = [
      ...item.childElements,
      for (final g in item.childElements.where((e) => e.name.local == 'group')) ...g.childElements,
    ];
    for (final e in mediaEls) {
      final n = e.name.local;
      // Bing: <News:Image>https://www.bing.com/th?id=...</News:Image>
      if (n == 'Image' && e.getAttribute('url') == null) {
        consider(upscaleImage(e.innerText.trim()), 1000);
      } else if (n == 'thumbnail' || n == 'content' || n == 'enclosure') {
        final type = e.getAttribute('type') ?? e.getAttribute('medium') ?? 'image';
        if (!type.startsWith('image')) continue;
        // Unknown size: assume medium. Known tiny thumbnails rank lowest.
        final w = int.tryParse(e.getAttribute('width') ?? '') ?? (n == 'thumbnail' ? 300 : 700);
        consider(e.getAttribute('url'), w);
      }
    }
    if (bestWidth > 0 && bestWidth < 250) image = null; // too small to look good

    return Article(
      title: title,
      url: link,
      sourceName: name,
      domain: domain,
      published: published,
      snippet: snippet,
      imageUrl: image,
      provider: provider,
      isLocal: isLocal,
      hintCategory: hint,
    );
  }

  /// Bing serves thumbnails from /th; ask for a large rendition instead.
  static String upscaleImage(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !u.host.endsWith('bing.com') || !u.path.startsWith('/th')) return url;
    final q = Map<String, String>.from(u.queryParameters)
      ..['w'] = '1200'
      ..['h'] = '675'
      ..['c'] = '7'
      ..['rs'] = '1'
      ..['qlt'] = '90'
      ..remove('pid');
    return u.replace(queryParameters: q).toString();
  }

  static XmlElement? _child(XmlElement e, String local) {
    for (final c in e.childElements) {
      if (c.name.local == local) return c;
    }
    return null;
  }

  static String? _childText(XmlElement e, String local) {
    final c = _child(e, local);
    if (c == null) return null;
    final t = c.innerText.trim();
    return t.isEmpty ? null : t;
  }

  static final _tag = RegExp(r'<[^>]*>');
  static final _ws = RegExp(r'\s+');
  static final _spoof = RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F​-‏‪-‮⁦-⁩﻿]');

  /// Strips HTML tags and decodes common entities. Output is plain text only.
  static String cleanText(String s) {
    var t = s.replaceAll(_tag, ' ');
    t = decodeEntities(t);
    // Entity-decoding can reveal escaped tags (&lt;b&gt;) — strip again.
    t = t.replaceAll(_tag, ' ');
    // Remove bidi overrides / invisible controls used to spoof headlines & names.
    t = t.replaceAll(_spoof, '');
    return t.replaceAll(_ws, ' ').trim();
  }

  static final _numEntity = RegExp(r'&#(x?)([0-9a-fA-F]+);');
  static const _named = {
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&apos;': "'",
    '&#39;': "'",
    '&nbsp;': ' ',
    '&ndash;': '–',
    '&mdash;': '—',
    '&hellip;': '…',
    '&rsquo;': '’',
    '&lsquo;': '‘',
    '&rdquo;': '”',
    '&ldquo;': '“',
  };

  static String decodeEntities(String s) {
    var t = s.replaceAllMapped(_numEntity, (m) {
      final code = int.tryParse(m[2]!, radix: m[1]!.isEmpty ? 10 : 16);
      if (code == null || code <= 0 || code > 0x10FFFF) return '';
      return String.fromCharCode(code);
    });
    _named.forEach((k, v) => t = t.replaceAll(k, v));
    return t;
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  static final _rfc822 = RegExp(
      r'(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Za-z]+)?');

  /// Parses RFC-822 (RSS) and ISO-8601 (Atom) dates into UTC.
  static DateTime? parseFeedDate(String s) {
    final iso = DateTime.tryParse(s.trim());
    if (iso != null) return iso.toUtc();
    final m = _rfc822.firstMatch(s);
    if (m == null) return null;
    final month = _months[m[2]!.toLowerCase()];
    if (month == null) return null;
    var year = int.parse(m[3]!);
    if (year < 100) year += 2000;
    var dt = DateTime.utc(year, month, int.parse(m[1]!), int.parse(m[4]!), int.parse(m[5]!),
        int.tryParse(m[6] ?? '0') ?? 0);
    final tz = m[7];
    if (tz != null && (tz.startsWith('+') || tz.startsWith('-'))) {
      final sign = tz.startsWith('-') ? -1 : 1;
      final h = int.parse(tz.substring(1, 3));
      final min = int.parse(tz.substring(3, 5));
      dt = dt.subtract(Duration(minutes: sign * (h * 60 + min)));
    } else if (tz != null) {
      const zones = {'EST': -5, 'EDT': -4, 'CST': -6, 'CDT': -5, 'MST': -7, 'MDT': -6, 'PST': -8, 'PDT': -7};
      final off = zones[tz.toUpperCase()];
      if (off != null) dt = dt.subtract(Duration(hours: off));
    }
    // Ignore obviously bogus future dates.
    if (dt.isAfter(DateTime.now().toUtc().add(const Duration(days: 1)))) return null;
    return dt;
  }
}
