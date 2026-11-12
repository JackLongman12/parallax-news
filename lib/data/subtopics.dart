import '../models/category.dart';
import '../services/text.dart';

/// A subtopic or niche: a focused news search under a topic.
class Sub {
  const Sub(this.label, this.query, [this.niches = const []]);
  final String label;
  final String query;
  final List<Sub> niches;

  Set<String> get keywords => TextTokens.stemSet('$label $query'.replaceAll(' OR ', ' '));
}

/// General -> subtopic -> niche. Queries use Google News syntax.
const Map<Category, List<Sub>> subtopics = {
  Category.politics: [
    Sub('Elections', 'election polls OR campaign OR voters', [
      Sub('Polling', 'election poll survey voters'),
      Sub('Campaign finance', 'campaign donations super PAC fundraising'),
      Sub('Voting rights', 'voting rights ballot access'),
    ]),
    Sub('Legislation', 'bill passes OR legislation OR lawmakers vote', [
      Sub('Budget & spending', 'budget bill spending government shutdown'),
      Sub('Tax policy', 'tax bill tax cuts tax reform'),
    ]),
    Sub('Courts', 'supreme court ruling OR constitutional court', [
      Sub('Supreme Court', 'supreme court ruling justices'),
    ]),
    Sub('Diplomacy', 'summit OR foreign minister OR sanctions', [
      Sub('Sanctions', 'sanctions imposed OR lifted'),
      Sub('Trade talks', 'trade talks trade deal negotiations'),
    ]),
  ],
  Category.world: [
    Sub('Conflicts', 'war OR ceasefire OR offensive', [
      Sub('Ukraine war', 'Ukraine Russia war front'),
      Sub('Middle East', 'Gaza OR Israel OR Lebanon OR Iran conflict'),
      Sub('Sudan', 'Sudan war RSF'),
    ]),
    Sub('United Nations', 'United Nations OR UN Security Council'),
    Sub('Migration', 'migrants OR refugees OR asylum', [
      Sub('Border policy', 'border crossings asylum policy'),
    ]),
    Sub('Humanitarian', 'humanitarian aid OR famine OR relief'),
  ],
  Category.business: [
    Sub('Earnings', 'quarterly earnings results profit', [
      Sub('Big Tech earnings', 'Apple OR Microsoft OR Alphabet OR Amazon OR Meta earnings'),
      Sub('Bank earnings', 'JPMorgan OR Goldman OR bank earnings'),
    ]),
    Sub('Deals & M&A', 'acquisition OR merger OR takeover bid', [
      Sub('Antitrust', 'antitrust regulator blocks merger'),
    ]),
    Sub('Trade & tariffs', 'tariffs OR trade war OR exports', [
      Sub('Supply chains', 'supply chain shortage shipping'),
    ]),
    Sub('Retail & consumers', 'retail sales OR consumer spending'),
    Sub('Startups', 'startup funding round OR unicorn OR venture capital'),
  ],
  Category.finance: [
    Sub('Stocks', 'stock market OR Wall Street OR shares', [
      Sub('S&P 500', 'S&P 500 index'),
      Sub('Nasdaq & tech stocks', 'Nasdaq tech stocks rally OR selloff'),
      Sub('IPOs', 'IPO listing debut shares'),
    ]),
    Sub('Central banks', 'Federal Reserve OR ECB OR interest rates', [
      Sub('Fed & rates', 'Federal Reserve interest rate decision Powell'),
      Sub('Inflation', 'inflation CPI report prices'),
    ]),
    Sub('Crypto', 'bitcoin OR crypto OR ethereum', [
      Sub('Bitcoin', 'bitcoin price'),
      Sub('Crypto ETFs', 'bitcoin ETF OR ether ETF flows'),
      Sub('Crypto regulation', 'crypto regulation SEC stablecoin'),
    ]),
    Sub('Commodities', 'gold price OR oil price OR commodities'),
    Sub('Currencies', 'dollar OR euro OR yen currency forex'),
    Sub('Personal finance', 'mortgage rates OR savings OR retirement OR credit cards'),
  ],
  Category.technology: [
    Sub('Semiconductors', 'chips OR semiconductor OR Nvidia OR TSMC', [
      Sub('AI chips', 'AI chips Nvidia AMD accelerators'),
      Sub('Chip export controls', 'chip export controls China'),
    ]),
    Sub('Cybersecurity', 'cyberattack OR data breach OR ransomware OR hackers', [
      Sub('Ransomware', 'ransomware attack'),
      Sub('Data breaches', 'data breach leaked records'),
    ]),
    Sub('Smartphones', 'iPhone OR Android OR Samsung Galaxy OR Pixel'),
    Sub('Social media', 'TikTok OR Instagram OR X Twitter OR Meta platform', [
      Sub('Content moderation', 'content moderation platform policy'),
    ]),
    Sub('Big Tech regulation', 'antitrust Google OR Apple OR Meta OR Amazon regulators'),
    Sub('Software & cloud', 'cloud computing OR Microsoft Azure OR AWS OR software'),
  ],
  Category.ai: [
    Sub('AI models', 'new AI model OR LLM release OR GPT OR Claude OR Gemini', [
      Sub('Open-source AI', 'open source AI model weights'),
      Sub('AI agents', 'AI agents autonomous'),
    ]),
    Sub('AI policy', 'AI regulation OR AI Act OR AI safety', [
      Sub('AI safety', 'AI safety research alignment'),
      Sub('Copyright & AI', 'AI copyright lawsuit training data'),
    ]),
    Sub('AI business', 'AI startup funding OR AI investment', [
      Sub('AI data centers', 'AI data center power gigawatt'),
    ]),
    Sub('AI in science', 'AI drug discovery OR AI research breakthrough'),
  ],
  Category.science: [
    Sub('Physics', 'physics discovery OR quantum', [Sub('Quantum computing', 'quantum computer qubits')]),
    Sub('Biology', 'biology study OR genetics OR evolution', [Sub('Gene editing', 'CRISPR gene editing')]),
    Sub('Archaeology', 'archaeologists discover OR ancient'),
    Sub('Climate science', 'climate study research warming'),
  ],
  Category.space: [
    Sub('Launches', 'rocket launch OR SpaceX launch', [Sub('Starship', 'SpaceX Starship flight')]),
    Sub('Moon & Mars', 'Artemis OR lunar OR Mars mission'),
    Sub('Astronomy', 'telescope OR exoplanet OR galaxy', [Sub('James Webb', 'James Webb telescope')]),
    Sub('Satellites', 'satellites OR Starlink OR orbit debris'),
  ],
  Category.health: [
    Sub('Medical research', 'clinical trial OR study finds treatment', [
      Sub('Cancer', 'cancer treatment study'),
      Sub('Weight-loss drugs', 'Ozempic OR Wegovy OR GLP-1'),
    ]),
    Sub('Public health', 'outbreak OR vaccination OR public health', [Sub('Outbreaks', 'outbreak cases virus')]),
    Sub('Mental health', 'mental health OR depression OR anxiety'),
    Sub('Healthcare policy', 'health insurance OR drug prices OR hospitals funding'),
  ],
  Category.sports: [
    Sub('Football / soccer', 'Premier League OR Champions League OR La Liga OR World Cup', [
      Sub('Premier League', 'Premier League'),
      Sub('Transfers', 'transfer signing football club'),
    ]),
    Sub('American football', 'NFL'),
    Sub('Basketball', 'NBA OR basketball'),
    Sub('Tennis', 'tennis ATP OR WTA'),
    Sub('Motorsport', 'Formula 1 OR F1 Grand Prix'),
    Sub('Cricket', 'cricket test OR T20'),
  ],
  Category.entertainment: [
    Sub('Film', 'box office OR film OR movie premiere', [Sub('Awards', 'Oscars OR Golden Globes nominations')]),
    Sub('TV & streaming', 'Netflix OR streaming series OR HBO'),
    Sub('Music', 'album OR tour OR Grammy'),
    Sub('Celebrity', 'celebrity OR actor OR singer'),
  ],
  Category.gaming: [
    Sub('Consoles', 'PlayStation OR Xbox OR Nintendo Switch'),
    Sub('PC gaming', 'PC gaming OR Steam'),
    Sub('Esports', 'esports tournament'),
    Sub('Game industry', 'game studio layoffs OR game publisher'),
  ],
  Category.environment: [
    Sub('Extreme weather', 'wildfire OR flood OR drought OR heatwave'),
    Sub('Climate policy', 'climate policy OR COP summit OR emissions target', [
      Sub('Carbon markets', 'carbon price emissions trading'),
    ]),
    Sub('Renewables', 'solar OR wind power OR renewable energy'),
    Sub('Biodiversity', 'biodiversity OR species extinction OR conservation'),
  ],
  Category.crime: [
    Sub('Courts & trials', 'trial verdict OR sentenced OR jury'),
    Sub('Investigations', 'investigation police OR FBI OR charges'),
    Sub('Cybercrime', 'cybercrime OR scam OR fraud ring'),
  ],
  Category.education: [
    Sub('Universities', 'university OR college tuition OR campus'),
    Sub('Schools', 'schools OR teachers OR school board'),
    Sub('Student loans', 'student loans debt'),
  ],
  Category.autos: [
    Sub('Electric vehicles', 'electric vehicle OR EV sales OR Tesla OR BYD', [Sub('EV batteries', 'EV battery technology')]),
    Sub('Self-driving', 'self-driving OR robotaxi OR autonomous vehicle'),
    Sub('Automakers', 'Toyota OR Volkswagen OR GM OR Ford OR Stellantis'),
  ],
  Category.travel: [
    Sub('Airlines', 'airline OR flights OR airport'),
    Sub('Tourism', 'tourism OR tourists OR destination'),
    Sub('Food & dining', 'restaurant OR chef OR food trends'),
  ],
  Category.lifestyle: [
    Sub('Fitness', 'fitness OR workout OR exercise'),
    Sub('Fashion', 'fashion week OR designer OR fashion brand'),
    Sub('Parenting', 'parenting OR children family'),
  ],
  Category.energy: [
    Sub('Oil & gas', 'oil prices OR OPEC OR natural gas', [
      Sub('OPEC+', 'OPEC+ output cuts'),
      Sub('LNG', 'LNG exports liquefied natural gas'),
    ]),
    Sub('Power & grid', 'electricity grid OR power prices OR blackout'),
    Sub('Nuclear', 'nuclear power OR reactor OR SMR'),
    Sub('Solar & wind', 'solar farm OR wind farm OR offshore wind'),
  ],
  Category.realEstate: [
    Sub('Housing market', 'home prices OR housing market OR home sales', [Sub('Mortgage rates', 'mortgage rates')]),
    Sub('Rent', 'rent prices OR renters OR housing affordability'),
    Sub('Commercial property', 'commercial real estate OR office vacancies'),
  ],
  Category.defense: [
    Sub('Military aid', 'military aid OR weapons package'),
    Sub('Defense industry', 'defense contractor OR Lockheed OR arms deal'),
    Sub('Drones & missiles', 'drone attack OR missile strike OR air defense'),
    Sub('NATO', 'NATO'),
  ],
  Category.labor: [
    Sub('Jobs data', 'jobs report OR payrolls OR unemployment rate'),
    Sub('Strikes & unions', 'strike OR union OR walkout'),
    Sub('Layoffs', 'layoffs OR job cuts'),
    Sub('Wages', 'minimum wage OR wages rise'),
  ],
  Category.weather: [
    Sub('Storms', 'hurricane OR typhoon OR storm'),
    Sub('Heat & drought', 'heatwave OR drought'),
    Sub('Winter weather', 'snowstorm OR blizzard OR cold snap'),
  ],
};

/// A subtopic/niche with its path, e.g. "Technology > Semiconductors > AI chips".
class SubPath {
  SubPath(this.category, this.chain);
  final Category category;
  final List<Sub> chain;
  Sub get leaf => chain.last;
  String get path => [category.label, ...chain.map((s) => s.label)].join(' > ');
}

Iterable<SubPath> allSubPaths() sync* {
  for (final e in subtopics.entries) {
    for (final s in e.value) {
      yield SubPath(e.key, [s]);
      for (final n in s.niches) {
        yield SubPath(e.key, [s, n]);
      }
    }
  }
}

/// Subtopics/niches whose words overlap [tokens] (e.g. a story headline),
/// most specific (niche) first.
List<SubPath> matchingSubPaths(Set<String> tokens, {int limit = 4}) {
  final scored = <(SubPath, double)>[];
  for (final sp in allSubPaths()) {
    final kw = sp.leaf.keywords;
    final hits = kw.where(tokens.contains).length;
    if (hits == 0) continue;
    scored.add((sp, hits + sp.chain.length * 0.5));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  final seen = <String>{};
  return [for (final s in scored) if (seen.add(s.$1.leaf.label)) s.$1].take(limit).toList();
}
