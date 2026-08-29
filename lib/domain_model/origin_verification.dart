/// The 3-step origin verification (Option C gate) - port of
/// tools/validate_dish_origin.py.
///
/// A model grading its own single-shot answer is exactly the failure mode
/// that lets a dish like Soto Ayam through - if Gemini's training data
/// already associates a dish with Malay cuisine it will self-report high
/// confidence on that same association. So a brand-new food submitted via a
/// landmark is checked with three SEPARATE, DIFFERENTLY-FRAMED questions,
/// each a fresh call with no shared context:
///
///   1. [OriginDirectCheck] - origin question with NO mention of Malaysia;
///   2. [OriginAdjudicateCheck] - surfaces the Malaysia-vs-elsewhere dispute
///      and asks the model to adjudicate it;
///   3. [OriginKnownPatternCheck] - audits against the specific failure mode
///      already caught (see `GeminiLandmarkService.knownMisattributions`).
///
/// A dish counts as Malaysian local food when it is (a) Malaysian in origin,
/// (b) adopted/naturalized (roti canai, chee cheong fun) or (d) shared
/// regional (rendang, laksa) - NOT only when it originated in Malaysia. Each
/// check classifies the dish into those cases. With no human-review queue, a
/// split is resolved by rule: at least 2 of 3 checks agreeing on (a)/(b)/(d)
/// accepts the dish; otherwise it is rejected.
library;

/// The single most important taste of a dish.
/// The a/b/c/d case a dish falls into - the classification every check is
/// asked to make (port of the app's own `_localFoodRules` scheme):
///   (a) [malaysian]       - originated in Malaysia;
///   (b) [adopted]         - foreign origin but adopted/naturalized as
///                           everyday Malaysian food (roti canai, chee cheong
///                           fun);
///   (c) [foreign]         - popular in Malaysia but no distinct Malaysian
///                           identity (sushi, pizza, Western fast food);
///   (d) [sharedRegional]  - shared across Malaysia/Indonesia/etc. and
///                           genuinely part of Malaysian food culture
///                           (rendang, laksa).
///   [unclear]             - the check could not classify it.
enum OriginDishCase {
  malaysian,
  adopted,
  foreign,
  sharedRegional,
  unclear;

  /// Parses the "case" field Gemini returns ("a"|"b"|"c"|"d").
  static OriginDishCase fromLabel(Object? label) => switch (label) {
    'a' => OriginDishCase.malaysian,
    'b' => OriginDishCase.adopted,
    'c' => OriginDishCase.foreign,
    'd' => OriginDishCase.sharedRegional,
    _ => OriginDishCase.unclear,
  };

  /// Whether this classification counts as Malaysian local food: (a) origin,
  /// (b) adopted/naturalized, (d) shared regional. (c) foreign and unclear
  /// do not.
  bool get isMalaysianLocalFood =>
      this == OriginDishCase.malaysian ||
      this == OriginDishCase.adopted ||
      this == OriginDishCase.sharedRegional;
}

/// Check 1 - where the dish historically originated and which case it falls
/// into (no mention of Malaysia in the question, so there is nothing to
/// anchor to or agree with).
typedef OriginDirectCheck = ({
  /// The a/b/c/d classification.
  OriginDishCase dishCase,

  /// Country the dish historically originated in.
  String originCountry,

  /// Ethnic/regional cuisine (e.g. Malay, Javanese, Peranakan, Thai).
  String originEthnicity,

  /// 0..1 confidence in the classification.
  double confidence,
});

/// Adjudication of the Malaysia-vs-elsewhere dispute - case-aware, so a dish
/// can be Malaysian local food even when it did not originate in Malaysia.
typedef OriginAdjudicateCheck = ({
  /// The a/b/c/d classification.
  OriginDishCase dishCase,

  /// Where the dish actually originated.
  String actualOriginCountry,

  /// Max-2-sentence note on regional variants / adoption.
  String distinguishingNotes,
});

/// Audit against the known misattribution pattern.
typedef OriginKnownPatternCheck = ({
  /// Whether this dish is the same kind of mistake already caught.
  bool isCommonlyMisattributed,

  /// The correct origin when it is misattributed, else null.
  String? correctOriginIfMisattributed,

  /// Max-2-sentence reasoning.
  String reasoning,
});

/// Consensus of the three checks.
///
/// There is NO human-review queue in the app, so a split cannot be deferred:
/// it is resolved by rule - a check counts as "Malaysian" when it classifies
/// the dish as (a), (b) or (d), and a dish is [accept]ed when AT LEAST TWO of
/// the three independent checks say so. That is what lets adopted dishes
/// (roti canai) and shared-regional dishes (rendang, laksa) through even
/// though their origin is not Malaysia, while a single weak vote (1/3) is not
/// enough to create a curated catalogue row.
enum OriginVerdict {
  /// At least 2 of the 3 checks classified the dish as Malaysian local food.
  accept,

  /// Fewer than 2 checks did - the dish is not admitted to the catalogue.
  reject,
}

/// Outcome of the 3-step origin verification for one dish.
class OriginVerification {
  const OriginVerification({
    required this.dishName,
    required this.verdict,
    required this.votesMalaysian,
    required this.directOrigin,
    required this.adjudicate,
    required this.knownPattern,
  });

  final String dishName;
  final OriginVerdict verdict;

  /// How many of the three checks voted "Malaysian" (0..3).
  final int votesMalaysian;

  final OriginDirectCheck directOrigin;
  final OriginAdjudicateCheck adjudicate;
  final OriginKnownPatternCheck knownPattern;
}
