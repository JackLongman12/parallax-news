/// Tokenisation shared by clustering and the classifier. Deliberately cheap:
/// no regex backtracking, no allocations beyond the token list.
class TextTokens {
  static const _stop = {
    'the', 'and', 'for', 'with', 'that', 'this', 'from', 'are', 'was', 'were', 'has', 'have',
    'had', 'will', 'would', 'could', 'should', 'into', 'over', 'after', 'before', 'about',
    'says', 'said', 'say', 'new', 'its', 'his', 'her', 'their', 'they', 'you', 'not', 'but',
    'than', 'then', 'what', 'when', 'where', 'who', 'why', 'how', 'all', 'can', 'out', 'more',
    'most', 'some', 'just', 'also', 'amid', 'via', 'per', 'off', 'one', 'two', 'now',
    'year', 'years', 'day', 'days', 'week', 'live', 'update', 'updates', 'news', 'report',
    'reports', 'video', 'watch', 'photos', 'here', 'top', 'get', 'gets', 'make', 'makes',
    'les', 'des', 'une', 'pour', 'dans', 'sur', 'por', 'para', 'con', 'las', 'los', 'del',
    'una', 'und', 'der', 'die', 'das', 'mit', 'von', 'den', 'ist', 'dei', 'della', 'che',
  };

  static bool isStopWord(String w) => _stop.contains(w);

  static final _split = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final _cjk = RegExp(r'[぀-ヿ㐀-鿿가-힯฀-๿]');

  static List<String> tokens(String text) {
    final lower = text.toLowerCase();
    final words = lower.split(_split).where((w) => w.length > 2 && !_stop.contains(w)).toList();
    // Scripts without spaces (CJK, Thai): fall back to character bigrams.
    if (_cjk.hasMatch(lower)) {
      final chars = lower.replaceAll(_split, '');
      for (var i = 0; i + 1 < chars.length; i++) {
        words.add(chars.substring(i, i + 2));
      }
    }
    return words;
  }

  /// Very light stemming so "election"/"elections" match.
  static String stem(String w) {
    if (w.length > 5 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
    if (w.length > 4 && w.endsWith('es')) return w.substring(0, w.length - 2);
    if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
    return w;
  }

  static Set<String> stemSet(String text) => tokens(text).map(stem).toSet();
}
