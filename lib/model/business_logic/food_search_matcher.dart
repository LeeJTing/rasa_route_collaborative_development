import 'package:string_similarity/string_similarity.dart';

import '../../domain_model/local_food.dart';
import 'food_name_matcher.dart';

class FoodSearchMatcher {
  const FoodSearchMatcher._();

  /// Queries shorter than this use the substring tiers only.
  static const int _minFuzzyLength = 4;

  static const int _exactScore = 100;
  static const int _prefixScore = 80;
  static const int _containedScore = 60;
  static const int _similarityBaseScore = 40;
  static const int _similarityScoreRange = 15;
  static const double _similarityThreshold = 0.6;

  static int score(String query, LocalFood food) {
    final String needle = _normalize(query);
    if (needle.isEmpty) return 0;
    int best = 0;
    for (final String alias in _aliases(food)) {
      final int aliasScore = _scoreAlias(needle, alias);
      if (aliasScore > best) best = aliasScore;
    }
    return best;
  }

  static bool matches(String query, LocalFood food) => score(query, food) > 0;

  static Iterable<String> _aliases(LocalFood food) sync* {
    yield _normalize(food.name);
    for (final String synonym in food.synonyms) {
      yield _normalize(synonym);
    }
  }

  static int _scoreAlias(String needle, String alias) {
    if (alias.isEmpty) return 0;
    if (alias == needle) return _exactScore;
    if (alias.startsWith(needle)) return _prefixScore;
    if (alias.contains(needle)) return _containedScore;
    if (needle.length < _minFuzzyLength) return 0;
    return _similarityScore(needle, alias);
  }

  static int _similarityScore(String needle, String alias) {
    final double similarity = StringSimilarity.compareTwoStrings(needle, alias);
    if (similarity < _similarityThreshold) return 0;
    return _similarityBaseScore +
        (similarity * _similarityScoreRange).round();
  }

  static String _normalize(String value) => FoodNameMatcher.normalize(value);
}
