import 'region.dart';

/// Where a local food is actually served: one restaurant menu entry, or one
/// dish on a tourist-submitted landmark.
///
/// These are the raw points the REQ102 heatmap is built from. `MapRepository`
/// produces them; `MapExplorationLogic` assigns each one to a [Region] and
/// applies the C1 availability formula.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these.
class FoodOccurrence {
  const FoodOccurrence({
    required this.sourceId,
    required this.source,
    required this.placeName,
    required this.localFoodId,
    required this.foodName,
    required this.latitude,
    required this.longitude,
    this.placeImageUrl,
    this.placeCategory,
    this.placeRating,
    this.itemPrice,
  });

  /// `restaurant_id` or `landmark_id`, as text - the two id spaces overlap, so
  /// [source] is what disambiguates them.
  final String sourceId;

  final FoodOccurrenceSource source;

  /// Restaurant or landmark name, used as the map pin's label.
  final String placeName;

  /// `local_food.local_food_id`, or `0` for a submitted landmark whose `dish`
  /// text has not been resolved against the catalogue yet.
  final int localFoodId;

  /// The dish as the source spells it. For a submitted landmark this is
  /// `landmark_item.dish`, which is how the catalogue match is made.
  final String foodName;

  final double latitude;
  final double longitude;

  // --- what the "Click Map Pin" sheet needs (UC300 A11) --------------------
  // Carried on the occurrence because the pin query already reads these
  // columns; collecting them here saves a second round trip when a pin is
  // tapped.

  final String? placeImageUrl;
  final String? placeCategory;
  final double? placeRating;

  /// Price of this one dish here, used to build the pin's price range.
  final double? itemPrice;
}

/// Which data source an occurrence came from (C21 keeps the two apart).
enum FoodOccurrenceSource { restaurant, submittedLandmark }

/// One area's raw counts, before the C1 availability formula is applied.
///
/// This is what [MapRepository] produces for a level of the heatmap: an area
/// paired with the numbers Postgres counted for it against the real
/// administrative boundary. `MapExplorationLogic` turns a list of these into
/// [RegionAvailability] by working out the C1 denominator across the set.
///
/// It exists so the counts can cross out of the repository as a domain model
/// rather than as a row - the score is a business rule, and business rules do
/// not belong in the layer that talks to the database.
class RegionTally {
  const RegionTally({
    required this.region,
    required this.placeCount,
    required this.foodCount,
    required this.restaurantCount,
    required this.landmarkCount,
  });

  final Region region;

  /// Distinct places in this area serving a food that survives the current
  /// filter - the number the gradient is built from.
  final int placeCount;

  /// Distinct local foods available in this area under the same filter.
  final int foodCount;

  /// Every `available` restaurant inside the boundary, unfiltered.
  final int restaurantCount;

  /// Every `available` submitted landmark inside the boundary, unfiltered.
  final int landmarkCount;
}

/// One state's slice of the heatmap.
///
/// [score] is C1: `restaurantCount / maximumRestaurantCount`, clamped to 0..1.
/// REQ102_15 renders the state with a colour gradient from this value;
/// REQ102_16 makes 1.0 green and 0.0 grey.
class RegionAvailability {
  const RegionAvailability({
    required this.region,
    required this.placeCount,
    required this.maximumPlaceCount,
    required this.score,
    required this.foodCount,
    this.restaurantCount = 0,
    this.landmarkCount = 0,
  });

  final Region region;

  /// **What the gradient is built from.** Distinct places inside this state -
  /// restaurants and submitted landmarks - serving at least one local food
  /// that survives the active filters (REQ102_28).
  ///
  /// Counted per *place*, not per menu entry: a restaurant serving six
  /// matching dishes is still one restaurant, and counting entries would let a
  /// single large menu outweigh a whole town.
  final int placeCount;

  /// The denominator of C1 - the highest [placeCount] any state reached
  /// for this same filter set.
  final int maximumPlaceCount;

  /// `restaurantCount / maximumRestaurantCount`, 0..1.
  final double score;

  /// Distinct local foods available in this state. Shown on the state card as
  /// context; the gradient no longer uses it.
  final int foodCount;

  /// Every `available` restaurant whose real coordinates fall inside this
  /// area's boundary, whether or not it serves a food matching the current
  /// filter. Maintained in Postgres by trigger, so it is a read rather than a
  /// count. [placeCount] is the filtered number the gradient uses; this is the
  /// unfiltered total the state card reports.
  final int restaurantCount;

  /// The same for tourist-submitted landmarks.
  final int landmarkCount;
}

/// The whole heatmap for one filter selection (REQ102_29).
class FoodDistribution {
  const FoodDistribution({
    required this.regions,
    required this.maximumPlaceCount,
    required this.matchingFoodCount,
    this.level = Region.stateLevel,
    this.parentCode,
    this.parentName,
  });

  static const FoodDistribution empty = FoodDistribution(
    regions: <RegionAvailability>[],
    maximumPlaceCount: 0,
    matchingFoodCount: 0,
  );

  /// Which level these numbers were counted at: [Region.stateLevel] for the
  /// whole country, [Region.districtLevel] for one state's districts.
  ///
  /// REQ102_12 - drilling in **recounts**. A district's number is its own
  /// tally, never the state's number shown again at a larger size, and
  /// [maximumPlaceCount] is the largest value *within this set*, so the colour
  /// ramp re-spreads across the districts on show instead of leaving them all
  /// one shade of the national maximum.
  final int level;

  /// The state being drilled into, `null` at [Region.stateLevel].
  final String? parentCode;
  final String? parentName;

  bool get isDistrictLevel => level == Region.districtLevel;

  /// Every Malaysian state, always - a state with no matching food is still
  /// drawn, in grey.
  final List<RegionAvailability> regions;

  /// C1's denominator (see [RegionAvailability.maximumPlaceCount]).
  final int maximumPlaceCount;

  /// How many catalogue entries survived the active filters. Zero means the
  /// filter combination matches nothing, not that the map failed to load.
  final int matchingFoodCount;
}
