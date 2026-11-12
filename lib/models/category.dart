/// Content categories used for sorting the daily feed.
/// `gnTopic` is the Google News topic id used to pull pre-labelled feeds,
/// which also double as free training data for the on-device classifier.
enum Category {
  general('Top News', null),
  politics('Politics', null),
  world('World', 'WORLD'),
  business('Business', 'BUSINESS'),
  technology('Technology', 'TECHNOLOGY'),
  ai('AI', null),
  science('Science', 'SCIENCE'),
  space('Space', null),
  health('Health', 'HEALTH'),
  sports('Sports', 'SPORTS'),
  entertainment('Entertainment', 'ENTERTAINMENT'),
  gaming('Gaming', null),
  environment('Climate', null),
  crime('Crime & Justice', null),
  education('Education', null),
  finance('Markets & Crypto', null),
  autos('Autos', null),
  travel('Travel & Food', null),
  lifestyle('Lifestyle', null),
  local('Community', null);

  const Category(this.label, this.gnTopic);
  final String label;
  final String? gnTopic;

  /// Search query used to fetch extra items for categories without a topic feed.
  String? get searchQuery {
    switch (this) {
      case Category.ai:
        return '"artificial intelligence" OR OpenAI OR Anthropic OR "machine learning" OR LLM';
      case Category.space:
        return 'NASA OR SpaceX OR ESA OR rocket launch OR astronomy';
      case Category.gaming:
        return 'video game OR PlayStation OR Xbox OR Nintendo OR esports';
      case Category.environment:
        return 'climate change OR environment OR emissions OR wildfire';
      case Category.finance:
        return 'stock market OR bitcoin OR crypto OR interest rates';
      case Category.politics:
        return 'election OR parliament OR congress OR government policy';
      case Category.autos:
        return 'electric vehicle OR automaker OR car launch';
      case Category.education:
        return 'schools OR university OR students OR education policy';
      default:
        return null;
    }
  }

  static Category? byName(String? n) {
    for (final c in Category.values) {
      if (c.name == n) return c;
    }
    return null;
  }
}
