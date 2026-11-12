import 'bias.dart';
import 'category.dart';

enum RatingOrigin { curated, wikidata, userOverride, none }

class SourceInfo {
  const SourceInfo({
    required this.domain,
    required this.name,
    this.bias = Bias.unrated,
    this.factuality = Factuality.unknown,
    this.country,
    this.owner,
    this.stateAffiliated = false,
    this.origin = RatingOrigin.none,
    this.alignmentLabel,
    this.feedUrl,
    this.wikidataId,
    this.isLocal = false,
    this.topics = const [],
  });

  final String domain;
  final String name;
  final Bias bias;
  final Factuality factuality;
  final String? country;
  final String? owner;
  final bool stateAffiliated;
  final RatingOrigin origin;
  final String? alignmentLabel;
  final String? feedUrl;
  final String? wikidataId;
  final bool isLocal;

  /// Topic specialisms (e.g. a tech site). Empty means general news.
  final List<Category> topics;

  SourceInfo copyWith({Bias? bias, RatingOrigin? origin, bool? isLocal, String? name}) =>
      SourceInfo(
        domain: domain,
        name: name ?? this.name,
        bias: bias ?? this.bias,
        factuality: factuality,
        country: country,
        owner: owner,
        stateAffiliated: stateAffiliated,
        origin: origin ?? this.origin,
        alignmentLabel: alignmentLabel,
        feedUrl: feedUrl,
        wikidataId: wikidataId,
        isLocal: isLocal ?? this.isLocal,
        topics: topics,
      );

  /// Compact format used by assets/sources.json.
  factory SourceInfo.fromCatalog(Map<String, dynamic> j) => SourceInfo(
        domain: (j['d'] as String).toLowerCase(),
        name: j['n'] as String,
        bias: Bias.fromCode(j['b'] as String?),
        factuality: Factuality.fromCode(j['f'] as String?),
        country: j['c'] as String?,
        owner: j['o'] as String?,
        stateAffiliated: j['s'] == true,
        feedUrl: j['rss'] as String?,
        origin: j['b'] != null ? RatingOrigin.curated : RatingOrigin.none,
        topics: ((j['t'] as List?) ?? const [])
            .map((e) => Category.byName(e.toString()))
            .whereType<Category>()
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'd': domain,
        'n': name,
        'b': bias.code,
        'f': factuality.code,
        'c': country,
        'o': owner,
        's': stateAffiliated,
        'rss': feedUrl,
        'wd': wikidataId,
        'al': alignmentLabel,
        'loc': isLocal,
        'origin': origin.name,
      };

  factory SourceInfo.fromJson(Map<String, dynamic> j) => SourceInfo(
        domain: j['d'] as String,
        name: j['n'] as String,
        bias: Bias.fromCode(j['b'] as String?),
        factuality: Factuality.fromCode(j['f'] as String?),
        country: j['c'] as String?,
        owner: j['o'] as String?,
        stateAffiliated: j['s'] == true,
        feedUrl: j['rss'] as String?,
        wikidataId: j['wd'] as String?,
        alignmentLabel: j['al'] as String?,
        isLocal: j['loc'] == true,
        origin: RatingOrigin.values
            .firstWhere((o) => o.name == j['origin'], orElse: () => RatingOrigin.none),
      );
}
