import '../models/place.dart';

class Continent {
  const Continent(this.code, this.name);
  final String code;
  final String name;

  Place get place =>
      Place(id: 'cont:$code', name: name, level: PlaceLevel.continent, continentCode: code);
}

const continents = [
  Continent('AF', 'Africa'),
  Continent('AS', 'Asia'),
  Continent('EU', 'Europe'),
  Continent('NA', 'North America'),
  Continent('SA', 'South America'),
  Continent('OC', 'Oceania'),
  Continent('AN', 'Antarctica'),
];

class Country {
  const Country(this.code, this.name, this.continent);
  final String code;
  final String name;
  final String continent;

  Place get place => Place(
        id: 'cc:$code',
        name: name,
        level: PlaceLevel.country,
        countryCode: code,
        continentCode: continent,
        parents: [continentName(continent)],
      );
}

String continentName(String code) =>
    continents.firstWhere((c) => c.code == code, orElse: () => const Continent('', '')).name;

Country? countryByCode(String? code) {
  if (code == null) return null;
  final up = code.toUpperCase();
  for (final c in countries) {
    if (c.code == up) return c;
  }
  return null;
}

/// ISO-3166 alpha-2 code | name | continent code.
const _countryTable = '''
DZ|Algeria|AF
AO|Angola|AF
BJ|Benin|AF
BW|Botswana|AF
BF|Burkina Faso|AF
BI|Burundi|AF
CV|Cabo Verde|AF
CM|Cameroon|AF
CF|Central African Republic|AF
TD|Chad|AF
KM|Comoros|AF
CD|DR Congo|AF
CG|Republic of the Congo|AF
CI|Côte d'Ivoire|AF
DJ|Djibouti|AF
EG|Egypt|AF
GQ|Equatorial Guinea|AF
ER|Eritrea|AF
SZ|Eswatini|AF
ET|Ethiopia|AF
GA|Gabon|AF
GM|Gambia|AF
GH|Ghana|AF
GN|Guinea|AF
GW|Guinea-Bissau|AF
KE|Kenya|AF
LS|Lesotho|AF
LR|Liberia|AF
LY|Libya|AF
MG|Madagascar|AF
MW|Malawi|AF
ML|Mali|AF
MR|Mauritania|AF
MU|Mauritius|AF
MA|Morocco|AF
MZ|Mozambique|AF
NA|Namibia|AF
NE|Niger|AF
NG|Nigeria|AF
RW|Rwanda|AF
ST|São Tomé and Príncipe|AF
SN|Senegal|AF
SC|Seychelles|AF
SL|Sierra Leone|AF
SO|Somalia|AF
ZA|South Africa|AF
SS|South Sudan|AF
SD|Sudan|AF
TZ|Tanzania|AF
TG|Togo|AF
TN|Tunisia|AF
UG|Uganda|AF
EH|Western Sahara|AF
ZM|Zambia|AF
ZW|Zimbabwe|AF
AF|Afghanistan|AS
AM|Armenia|AS
AZ|Azerbaijan|AS
BH|Bahrain|AS
BD|Bangladesh|AS
BT|Bhutan|AS
BN|Brunei|AS
KH|Cambodia|AS
CN|China|AS
CY|Cyprus|AS
GE|Georgia|AS
HK|Hong Kong|AS
IN|India|AS
ID|Indonesia|AS
IR|Iran|AS
IQ|Iraq|AS
IL|Israel|AS
JP|Japan|AS
JO|Jordan|AS
KZ|Kazakhstan|AS
KW|Kuwait|AS
KG|Kyrgyzstan|AS
LA|Laos|AS
LB|Lebanon|AS
MO|Macau|AS
MY|Malaysia|AS
MV|Maldives|AS
MN|Mongolia|AS
MM|Myanmar|AS
NP|Nepal|AS
KP|North Korea|AS
OM|Oman|AS
PK|Pakistan|AS
PS|Palestine|AS
PH|Philippines|AS
QA|Qatar|AS
SA|Saudi Arabia|AS
SG|Singapore|AS
KR|South Korea|AS
LK|Sri Lanka|AS
SY|Syria|AS
TW|Taiwan|AS
TJ|Tajikistan|AS
TH|Thailand|AS
TL|Timor-Leste|AS
TR|Türkiye|AS
TM|Turkmenistan|AS
AE|United Arab Emirates|AS
UZ|Uzbekistan|AS
VN|Vietnam|AS
YE|Yemen|AS
AL|Albania|EU
AD|Andorra|EU
AT|Austria|EU
BY|Belarus|EU
BE|Belgium|EU
BA|Bosnia and Herzegovina|EU
BG|Bulgaria|EU
HR|Croatia|EU
CZ|Czechia|EU
DK|Denmark|EU
EE|Estonia|EU
FO|Faroe Islands|EU
FI|Finland|EU
FR|France|EU
DE|Germany|EU
GI|Gibraltar|EU
GR|Greece|EU
GG|Guernsey|EU
HU|Hungary|EU
IS|Iceland|EU
IE|Ireland|EU
IM|Isle of Man|EU
IT|Italy|EU
JE|Jersey|EU
XK|Kosovo|EU
LV|Latvia|EU
LI|Liechtenstein|EU
LT|Lithuania|EU
LU|Luxembourg|EU
MT|Malta|EU
MD|Moldova|EU
MC|Monaco|EU
ME|Montenegro|EU
NL|Netherlands|EU
MK|North Macedonia|EU
NO|Norway|EU
PL|Poland|EU
PT|Portugal|EU
RO|Romania|EU
RU|Russia|EU
SM|San Marino|EU
RS|Serbia|EU
SK|Slovakia|EU
SI|Slovenia|EU
ES|Spain|EU
SE|Sweden|EU
CH|Switzerland|EU
UA|Ukraine|EU
GB|United Kingdom|EU
VA|Vatican City|EU
AI|Anguilla|NA
AG|Antigua and Barbuda|NA
AW|Aruba|NA
BS|Bahamas|NA
BB|Barbados|NA
BZ|Belize|NA
BM|Bermuda|NA
CA|Canada|NA
KY|Cayman Islands|NA
CR|Costa Rica|NA
CU|Cuba|NA
CW|Curaçao|NA
DM|Dominica|NA
DO|Dominican Republic|NA
SV|El Salvador|NA
GL|Greenland|NA
GD|Grenada|NA
GP|Guadeloupe|NA
GT|Guatemala|NA
HT|Haiti|NA
HN|Honduras|NA
JM|Jamaica|NA
MQ|Martinique|NA
MX|Mexico|NA
NI|Nicaragua|NA
PA|Panama|NA
PR|Puerto Rico|NA
KN|Saint Kitts and Nevis|NA
LC|Saint Lucia|NA
VC|Saint Vincent and the Grenadines|NA
TT|Trinidad and Tobago|NA
TC|Turks and Caicos Islands|NA
US|United States|NA
VI|U.S. Virgin Islands|NA
AR|Argentina|SA
BO|Bolivia|SA
BR|Brazil|SA
CL|Chile|SA
CO|Colombia|SA
EC|Ecuador|SA
FK|Falkland Islands|SA
GF|French Guiana|SA
GY|Guyana|SA
PY|Paraguay|SA
PE|Peru|SA
SR|Suriname|SA
UY|Uruguay|SA
VE|Venezuela|SA
AS|American Samoa|OC
AU|Australia|OC
CK|Cook Islands|OC
FJ|Fiji|OC
PF|French Polynesia|OC
GU|Guam|OC
KI|Kiribati|OC
MH|Marshall Islands|OC
FM|Micronesia|OC
NR|Nauru|OC
NC|New Caledonia|OC
NZ|New Zealand|OC
MP|Northern Mariana Islands|OC
PW|Palau|OC
PG|Papua New Guinea|OC
WS|Samoa|OC
SB|Solomon Islands|OC
TO|Tonga|OC
TV|Tuvalu|OC
VU|Vanuatu|OC
AQ|Antarctica|AN
''';

final List<Country> countries = _countryTable
    .split('\n')
    .where((l) => l.trim().isNotEmpty)
    .map((l) {
      final p = l.split('|');
      return Country(p[0], p[1], p[2]);
    })
    .toList(growable: false);

/// Google News edition parameters for a country.
class Edition {
  const Edition(this.hl, this.gl, this.lang);
  final String hl;
  final String gl;
  final String lang;

  String get query => 'hl=$hl&gl=$gl&ceid=$gl:$lang';
  bool get isEnglish => lang == 'en';

  static const us = Edition('en-US', 'US', 'en');
}

const Map<String, Edition> _editions = {
  'US': Edition('en-US', 'US', 'en'),
  'GB': Edition('en-GB', 'GB', 'en'),
  'CA': Edition('en-CA', 'CA', 'en'),
  'AU': Edition('en-AU', 'AU', 'en'),
  'NZ': Edition('en-NZ', 'NZ', 'en'),
  'IE': Edition('en-IE', 'IE', 'en'),
  'IN': Edition('en-IN', 'IN', 'en'),
  'PK': Edition('en-PK', 'PK', 'en'),
  'BD': Edition('bn', 'BD', 'bn'),
  'SG': Edition('en-SG', 'SG', 'en'),
  'MY': Edition('en-MY', 'MY', 'en'),
  'PH': Edition('en-PH', 'PH', 'en'),
  'ZA': Edition('en-ZA', 'ZA', 'en'),
  'NG': Edition('en-NG', 'NG', 'en'),
  'KE': Edition('en-KE', 'KE', 'en'),
  'GH': Edition('en-GH', 'GH', 'en'),
  'UG': Edition('en-UG', 'UG', 'en'),
  'TZ': Edition('en-TZ', 'TZ', 'en'),
  'ZW': Edition('en-ZW', 'ZW', 'en'),
  'NA': Edition('en-NA', 'NA', 'en'),
  'BW': Edition('en-BW', 'BW', 'en'),
  'ET': Edition('en-ET', 'ET', 'en'),
  'ZM': Edition('en-ZW', 'ZW', 'en'),
  'MX': Edition('es-419', 'MX', 'es-419'),
  'AR': Edition('es-419', 'AR', 'es-419'),
  'CO': Edition('es-419', 'CO', 'es-419'),
  'CL': Edition('es-419', 'CL', 'es-419'),
  'PE': Edition('es-419', 'PE', 'es-419'),
  'VE': Edition('es-419', 'VE', 'es-419'),
  'CU': Edition('es-419', 'CU', 'es-419'),
  'ES': Edition('es', 'ES', 'es'),
  'BR': Edition('pt-BR', 'BR', 'pt-419'),
  'PT': Edition('pt-PT', 'PT', 'pt-150'),
  'FR': Edition('fr', 'FR', 'fr'),
  'BE': Edition('fr', 'BE', 'fr'),
  'CH': Edition('de', 'CH', 'de'),
  'MA': Edition('fr', 'MA', 'fr'),
  'SN': Edition('fr', 'SN', 'fr'),
  'DE': Edition('de', 'DE', 'de'),
  'AT': Edition('de', 'AT', 'de'),
  'IT': Edition('it', 'IT', 'it'),
  'NL': Edition('nl', 'NL', 'nl'),
  'PL': Edition('pl', 'PL', 'pl'),
  'CZ': Edition('cs', 'CZ', 'cs'),
  'SK': Edition('sk', 'SK', 'sk'),
  'HU': Edition('hu', 'HU', 'hu'),
  'RO': Edition('ro', 'RO', 'ro'),
  'BG': Edition('bg', 'BG', 'bg'),
  'GR': Edition('el', 'GR', 'el'),
  'RS': Edition('sr', 'RS', 'sr'),
  'SI': Edition('sl', 'SI', 'sl'),
  'LV': Edition('lv', 'LV', 'lv'),
  'LT': Edition('lt', 'LT', 'lt'),
  'SE': Edition('sv', 'SE', 'sv'),
  'NO': Edition('no', 'NO', 'no'),
  'UA': Edition('uk', 'UA', 'uk'),
  'RU': Edition('ru', 'RU', 'ru'),
  'TR': Edition('tr', 'TR', 'tr'),
  'IL': Edition('he', 'IL', 'he'),
  'EG': Edition('ar', 'EG', 'ar'),
  'SA': Edition('ar', 'SA', 'ar'),
  'AE': Edition('ar', 'AE', 'ar'),
  'LB': Edition('ar', 'LB', 'ar'),
  'JP': Edition('ja', 'JP', 'ja'),
  'KR': Edition('ko', 'KR', 'ko'),
  'CN': Edition('zh-CN', 'CN', 'zh-Hans'),
  'TW': Edition('zh-TW', 'TW', 'zh-Hant'),
  'HK': Edition('zh-HK', 'HK', 'zh-Hant'),
  'ID': Edition('id', 'ID', 'id'),
  'TH': Edition('th', 'TH', 'th'),
  'VN': Edition('vi', 'VN', 'vi'),
};

/// Returns the native edition for a country, or null if Google has none.
Edition? editionFor(String? countryCode) =>
    countryCode == null ? null : _editions[countryCode.toUpperCase()];
