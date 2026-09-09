import '../../core/name_normalization.dart';
import '../../domain_model/local_food.dart';

/// Pure catalogue name-matching policy for dish names that come from Gemini.
///
/// `local_food` is the curated, human-verified list of Malaysian local foods -
/// the authoritative source of a dish's details. Gemini often returns a MORE
/// SPECIFIC variant of a curated name ("nasi lemak ayam" vs the curated
/// "nasi lemak"), so this matcher finds the best curated row for a free-text
/// dish name - or null when none is good enough and Gemini's own details
/// should be used instead.
///
/// Matching tiers, best first:
///   1. **exact** - the curated name or one of its synonyms equals the dish
///      name (after normalisation);
///   2. **prefix** - the curated name/synonym is a WHOLE WORD prefix of the
///      dish name ("nasi lemak" in "nasi lemak ayam"). Malay compound dish
///      names start with the base dish, so a prefix hit is a strong signal;
///   3. **contained** - the curated name/synonym appears as a whole phrase
///      anywhere in the dish name ("mee goreng" in "special mee goreng").
///
/// Within a tier the LONGEST match wins (most specific: "nasi lemak" beats
/// "nasi" for "nasi lemak ayam"). Matching is deliberately one-directional:
/// a short Gemini name is never expanded to a LONGER curated variant
/// ("nasi lemak" -> "nasi lemak ayam") because that is ambiguous - the photo
/// may show the plain dish, not the variant.
///
/// Curated rows shorter than [_minFuzzyLength] are ignored by the fuzzy tiers,
/// so a generic ingredient word ("ayam", "nasi", "mee") never matches a
/// compound dish name by accident; exact matches are unaffected.
class FoodNameMatcher {
  const FoodNameMatcher._();

  /// Curated aliases shorter than this are ignored by the prefix/contained
  /// tiers. Exact matches can still be any length.
  static const int _minFuzzyLength = 4;

  /// The best curated [LocalFood] for a free-text dish [name], or null when
  /// nothing matches well enough.
  static LocalFood? bestMatch(String name, List<LocalFood> catalogue) {
    final String needle = normalize(name);
    if (needle.isEmpty) return null;

    LocalFood? prefixBest;
    int prefixBestLength = 0;
    LocalFood? containedBest;
    int containedBestLength = 0;

    for (final LocalFood food in catalogue) {
      for (final String alias in _aliases(food)) {
        final String a = normalize(alias);
        if (a.isEmpty) continue;

        // Tier 1 - exact. Nothing can beat a perfect match, so take it.
        if (a == needle) return food;

        if (a.length < _minFuzzyLength) continue;

        // Tier 2 - whole-word prefix ("nasi lemak" in "nasi lemak ayam").
        // A prefix hit is stronger than a mid-name hit, so an alias that
        // matches here is not also considered for tier 3.
        if (needle.startsWith('$a ')) {
          if (prefixBest == null || a.length > prefixBestLength) {
            prefixBest = food;
            prefixBestLength = a.length;
          }
          continue;
        }

        // Tier 3 - whole phrase anywhere ("mee goreng" in "special mee goreng").
        if (needle.contains(' $a ') || needle.endsWith(' $a')) {
          if (containedBest == null || a.length > containedBestLength) {
            containedBest = food;
            containedBestLength = a.length;
          }
        }
      }
    }

    return prefixBest ?? containedBest;
  }

  /// Every alias a curated row can be matched by - its name first, then its
  /// synonyms.
  static Iterable<String> _aliases(LocalFood food) sync* {
    yield food.name;
    yield* food.synonyms;
  }

  /// Normalises a dish name for matching: Traditional → Simplified Chinese
  /// folding, lowercase, everything that is not a letter or digit becomes a
  /// space, and runs of whitespace collapse. "Nasi Lemak (Ayam)!" ->
  /// "nasi lemak ayam"; "福建麵" -> "福建面".
  static String normalize(String name) => toSimplifiedChinese(name)
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}
