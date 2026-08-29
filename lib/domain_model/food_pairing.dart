/// Dietary-safety verdict for one pairing, returned by Gemini (UC406).
enum FoodPairingDietaryStatus {
  /// Supplied data shows no known conflict and contains enough information to
  /// evaluate the tourist's applicable restrictions.
  compatible,

  /// Allergen, ingredient or preparation information is incomplete/uncertain,
  /// or cross-contamination is unverified - the tourist must check with the
  /// seller before ordering.
  warning,
}

/// "Goes well with" - one dish paired with another for a specific tourist.
///
/// The shape mirrors the Gemini food-pairing JSON (UC406): [matchPercentage]
/// is the recommendation strength (0-100), [rank] is the display order, and
/// [dietaryStatus]/[warning] carry the dietary-safety verdict.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class FoodPairing {
  const FoodPairing({
    required this.localFoodId,
    required this.pairedLocalFoodId,
    required this.pairedFoodName,
    required this.rank,
    required this.matchPercentage,
    required this.reason,
    required this.dietaryStatus,
    this.warning,
  });

  /// The food currently being viewed (the selected food).
  final int localFoodId;

  /// The recommended paired dish (must exist in candidateFoods).
  final int pairedLocalFoodId;

  final String pairedFoodName;

  /// Display order - 1-based, consecutive, matches list position.
  final int rank;

  /// Recommendation strength, a whole integer 0-100 (not a probability,
  /// medical-safety score, or measurement).
  final int matchPercentage;

  /// One concise, tourist-friendly sentence explaining the pairing.
  final String reason;

  /// Dietary-safety verdict for this tourist.
  final FoodPairingDietaryStatus dietaryStatus;

  /// What the tourist must confirm with the seller when [dietaryStatus] is
  /// [FoodPairingDietaryStatus.warning]; null when compatible.
  final String? warning;

  String? get pairedImageUrl => null;
}
