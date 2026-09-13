import '../../core/name_normalization.dart';
import '../../domain_model/local_food.dart';

/// How a free-text dish name matched a curated `local_food` row.
///
/// [exact] and [sameWords] mean the name IS the dish: its curated name, one
/// of its synonyms, or the same words in another order ("cendol nyonya" for
/// "Nyonya Cendol"). [prefix] and [contained] mean the name EXTENDS the dish
/// without being one of its names - an unlisted variant ("cendol jagung"
/// over "cendol"). The distinction matters UPSTREAM: a landmark item
/// records a `variant` only for an extension, never for the dish itself (see
/// `FoodRecognitionLogic._variantFor`).
enum FoodMatchTier { exact, sameWords, prefix, contained }

/// A curated match plus the tier it was found at - see [FoodMatchTier].
typedef FoodNameMatch = ({LocalFood food, FoodMatchTier tier});

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
///   2. **same words** - the curated name/synonym holds exactly the dish
///      name's words in another order ("cendol nyonya" vs "Nyonya Cendol");
///      a name typed back-to-front is still the SAME dish, never a variant of
///      it;
///   3. **prefix** - the curated name/synonym is a WHOLE WORD prefix of the
///      dish name ("nasi lemak" in "nasi lemak ayam"). Malay compound dish
///      names start with the base dish, so a prefix hit is a strong signal;
///   4. **contained** - the curated name/synonym appears as a whole phrase
///      anywhere in the dish name ("mee goreng" in "special mee goreng").
///
/// Within a tier the LONGEST match wins (most specific: "nasi lemak" beats
/// "nasi" for "nasi lemak ayam"). EXACT / same-words ties - several rows
/// sharing one spelling, e.g. 'chendol' and 煎蕊 on all three cendol rows -
/// resolve to the MOST GENERIC row (fewest words in its curated name: plain
/// "Cendol" over "Nyonya Cendol"), so a base spelling never lands on a
/// specific dessert. Matching is deliberately one-directional: a short
/// Gemini name is never expanded to a LONGER curated variant ("nasi lemak"
/// -> "nasi lemak ayam") because that is ambiguous - the photo may show the
/// plain dish, not the variant.
///
/// Curated rows shorter than [_minFuzzyLength] are ignored by the same-words
/// / prefix / contained tiers, so a generic ingredient word ("ayam", "nasi",
/// "mee") never matches a compound dish name by accident; exact matches are
/// unaffected.
class FoodNameMatcher {
  const FoodNameMatcher._();

  /// Curated aliases shorter than this are ignored by the same-words /
  /// prefix / contained tiers. Exact matches can still be any length.
  static const int _minFuzzyLength = 4;

  /// The best curated [LocalFood] for a free-text dish [name], or null when
  /// nothing matches well enough - see [bestMatchDetailed] for the tier the
  /// match came from.
  static LocalFood? bestMatch(String name, List<LocalFood> catalogue) =>
      bestMatchDetailed(name, catalogue)?.food;

  /// The best curated row for [name] WITH the tier it matched at - the tier
  /// tells "the same dish" ([FoodMatchTier.exact]/[FoodMatchTier.sameWords])
  /// apart from an unlisted variant that merely EXTENDS a dish
  /// ([FoodMatchTier.prefix]/[FoodMatchTier.contained]).
  static FoodNameMatch? bestMatchDetailed(
    String name,
    List<LocalFood> catalogue,
  ) {
    final String needle = normalize(name);
    if (needle.isEmpty) return null;
    final List<String> needleWords = _sortedWords(needle);

    final List<LocalFood> exact = <LocalFood>[];
    final List<LocalFood> sameWords = <LocalFood>[];
    LocalFood? prefixBest;
    int prefixBestLength = 0;
    LocalFood? containedBest;
    int containedBestLength = 0;

    for (final LocalFood food in catalogue) {
      bool exactHere = false;
      bool sameWordsHere = false;
      for (final String alias in _aliases(food)) {
        final String a = normalize(alias);
        if (a.isEmpty) continue;

        // Tier 1 - exact. Nothing can beat a perfect match, so this row
        // needs no lower tier - but several rows may claim the same spelling,
        // so collect them all and pick the most generic afterwards.
        if (a == needle) {
          exactHere = true;
          break;
        }

        if (a.length < _minFuzzyLength) continue;

        // Tier 2 - same words, any order ("cendol nyonya" / "Nyonya Cendol").
        if (_isSameWords(a, needleWords)) {
          sameWordsHere = true;
          continue;
        }

        // Tier 3 - whole-word prefix ("nasi lemak" in "nasi lemak ayam").
        // A prefix hit is stronger than a mid-name hit, so an alias that
        // matches here is not also considered for tier 4.
        if (needle.startsWith('$a ')) {
          if (prefixBest == null || a.length > prefixBestLength) {
            prefixBest = food;
            prefixBestLength = a.length;
          }
          continue;
        }

        // Tier 4 - whole phrase anywhere ("mee goreng" in "special mee goreng").
        if (needle.contains(' $a ') || needle.endsWith(' $a')) {
          if (containedBest == null || a.length > containedBestLength) {
            containedBest = food;
            containedBestLength = a.length;
          }
        }
      }
      if (exactHere) {
        exact.add(food);
      } else if (sameWordsHere) {
        sameWords.add(food);
      }
    }

    if (exact.isNotEmpty) {
      return (food: _mostGenericOf(exact), tier: FoodMatchTier.exact);
    }
    if (sameWords.isNotEmpty) {
      return (food: _mostGenericOf(sameWords), tier: FoodMatchTier.sameWords);
    }
    if (prefixBest != null) {
      return (food: prefixBest, tier: FoodMatchTier.prefix);
    }
    if (containedBest != null) {
      return (food: containedBest, tier: FoodMatchTier.contained);
    }
    return null;
  }

  /// Whether [alias] holds exactly the words of [needleWords] in another
  /// order - the SAME dish written differently ("cendol nyonya" vs
  /// "Nyonya Cendol"), never a subset or superset of it.
  static bool _isSameWords(String alias, List<String> needleWords) {
    final List<String> aliasWords = _sortedWords(alias);
    if (aliasWords.length != needleWords.length) return false;
    for (int index = 0; index < aliasWords.length; index++) {
      if (aliasWords[index] != needleWords[index]) return false;
    }
    return true;
  }

  /// Normalised words, sorted - the comparable shape behind [_isSameWords].
  static List<String> _sortedWords(String normalized) =>
      normalized.split(' ')..sort();

  /// The most GENERIC row of a tie: the one with the fewest words in its
  /// curated NAME, then the shortest name ('Cendol' over 'Nyonya Cendol' /
  /// 'Durian Cendol'), so a spelling several rows claim ('chendol', 煎蕊)
  /// resolves to the base dish. Remaining ties keep catalogue order.
  static LocalFood _mostGenericOf(List<LocalFood> rows) {
    LocalFood best = rows.first;
    String bestName = normalize(best.name);
    int bestWords = _wordCount(bestName);
    for (final LocalFood food in rows.skip(1)) {
      final String name = normalize(food.name);
      final int words = _wordCount(name);
      if (words < bestWords ||
          (words == bestWords && name.length < bestName.length)) {
        best = food;
        bestName = name;
        bestWords = words;
      }
    }
    return best;
  }

  static int _wordCount(String normalized) =>
      normalized.isEmpty ? 0 : normalized.split(' ').length;

  /// Every alias a curated row can be matched by - its name first, then its
  /// synonyms.
  static Iterable<String> _aliases(LocalFood food) sync* {
    yield food.name;
    yield* food.synonyms;
  }

  /// The words [variant] adds BEYOND the dish's own names - its [synonyms]
  /// included, since a synonym IS the dish. Empty means there is no variant
  /// at all: "Ais Kacang (ABC)" reduces to nothing when "ABC" is a curated
  /// synonym of "Ais Kacang" (the catalogue row lists it), so a capture or
  /// an entry spelled that way is simply the plain dish. A genuine variant
  /// keeps its distinguishing words: "Cendol Jagung" over "Cendol" leaves
  /// 'jagung'.
  ///
  /// Word-level and script-folded, exactly like every other name comparison
  /// here - case, punctuation and Traditional/Simplified spelling never
  /// split a word.
  static String variantDistinction(
    String dish,
    String variant,
    Iterable<String> synonyms,
  ) {
    final Set<String> known = <String>{
      ...normalize(dish).split(' '),
      for (final String synonym in synonyms) ...normalize(synonym).split(' '),
    }..remove('');
    final List<String> extra = normalize(variant)
        .split(' ')
        .where((String word) => word.isNotEmpty && !known.contains(word))
        .toList(growable: false);
    return extra.join(' ');
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
