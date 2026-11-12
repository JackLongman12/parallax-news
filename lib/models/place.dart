enum PlaceLevel { world, continent, country, region, district, city, locality }

class Place {
  const Place({
    required this.id,
    required this.name,
    required this.level,
    this.countryCode,
    this.continentCode,
    this.parents = const [],
    this.wikidataId,
  });

  /// Stable id: 'world', 'cont:EU', 'cc:US', or 'wd:Q1234' / 'osm:...'.
  final String id;
  final String name;
  final PlaceLevel level;
  final String? countryCode; // ISO-3166 alpha-2, upper case
  final String? continentCode;

  /// Parent place names, nearest first (e.g. ['Illinois', 'United States']).
  final List<String> parents;
  final String? wikidataId;

  static const world = Place(id: 'world', name: 'World', level: PlaceLevel.world);

  String get subtitle => parents.isEmpty ? levelLabel : '$levelLabel · ${parents.join(', ')}';

  String get levelLabel {
    switch (level) {
      case PlaceLevel.world:
        return 'Global';
      case PlaceLevel.continent:
        return 'Continent';
      case PlaceLevel.country:
        return 'Country';
      case PlaceLevel.region:
        return 'State / Province';
      case PlaceLevel.district:
        return 'District / County';
      case PlaceLevel.city:
        return 'City';
      case PlaceLevel.locality:
        return 'Community';
    }
  }

  bool get isLocalLevel =>
      level == PlaceLevel.city || level == PlaceLevel.locality || level == PlaceLevel.district;

  PlaceLevel get childLevel {
    switch (level) {
      case PlaceLevel.world:
        return PlaceLevel.continent;
      case PlaceLevel.continent:
        return PlaceLevel.country;
      case PlaceLevel.country:
        return PlaceLevel.region;
      case PlaceLevel.region:
        return PlaceLevel.district;
      case PlaceLevel.district:
        return PlaceLevel.city;
      case PlaceLevel.city:
      case PlaceLevel.locality:
        return PlaceLevel.locality;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'level': level.name,
        'cc': countryCode,
        'cont': continentCode,
        'parents': parents,
        'wd': wikidataId,
      };

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        id: j['id'] as String,
        name: j['name'] as String,
        level: PlaceLevel.values
            .firstWhere((l) => l.name == j['level'], orElse: () => PlaceLevel.locality),
        countryCode: j['cc'] as String?,
        continentCode: j['cont'] as String?,
        parents: (j['parents'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        wikidataId: j['wd'] as String?,
      );

  @override
  bool operator ==(Object other) => other is Place && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
