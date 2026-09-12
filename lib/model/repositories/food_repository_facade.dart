import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_pairing.dart';
import '../../domain_model/food_preference.dart';
import '../../domain_model/food_similarity.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/pronunciation_playback_result.dart';
import 'auth_repository.dart';
import 'dietary_restriction_repository.dart';
import 'food_knowledge_repository.dart';
import 'food_preference_repository.dart';
import 'recommendation_repository.dart';
import 'restaurant_repository.dart';
import 'swipe_repository.dart';
import 'tourist_profile_repository.dart';

/// Everything about dishes: the catalogue, favourites, recommendation
/// candidates, the swipe deck, and the food-domain reference data
/// (`food_preference`, `dietary_restriction`).
///
/// REPOSITORY FACADE - a business-logic class holds ONE of these, not four
/// separate repositories. It groups the repositories for one subject area and
/// re-exposes them as a single flat API. No business rules live here.
class FoodRepositoryFacade {
  FoodRepositoryFacade();

  final FoodKnowledgeRepository knowledge = FoodKnowledgeRepository();
  final RecommendationRepository recommendation = RecommendationRepository();
  final SwipeRepository swipe = SwipeRepository();

  /// Canonical taste/category options (`food_preference`) and reference
  /// dietary restrictions (`dietary_restriction`) - food-domain reference
  /// data read by recognition/recommendation features.
  final FoodPreferenceRepository foodPreference = FoodPreferenceRepository();
  final DietaryRestrictionRepository dietaryRestriction =
      DietaryRestrictionRepository();
  final AuthRepository auth = AuthRepository();
  final TouristProfileRepository touristProfile = TouristProfileRepository();

  /// Restaurant menu rows - used to compute a dish's listed price range.
  final RestaurantRepository restaurant = RestaurantRepository();

  // =========================================================================
  // Flat API - a logic class calls these, never `facade.knowledge.xxx`.
  // =========================================================================

  Future<List<LocalFood>> getFoods() => knowledge.getFoods();

  Future<List<LocalFood>> searchFoods(String query) =>
      knowledge.searchFoods(query);

  Future<LocalFood?> getFoodById(int foodId) => knowledge.getFoodById(foodId);

  Future<PronunciationPlaybackResult> playPronunciation(LocalFood food) =>
      knowledge.playPronunciation(food);

  /// Adds a genuinely-new, tourist-confirmed Malaysian local food to the
  /// catalogue (Option C - catalogue growth from submissions). Returns the
  /// saved row (with its assigned id) or null when a duplicate exists.
  Future<LocalFood?> insertFood(LocalFood food) => knowledge.insertFood(food);

  /// Attaches a photo to a catalogue dish (`local_food_image`) - used when a
  /// new dish is added from a landmark submission, so the dish carries the
  /// tourist's own photo. [imageName] is either a food-images object name or
  /// a full public URL (the already-uploaded `landmark-images` URL).
  Future<void> addFoodImage({
    required int localFoodId,
    required String imageName,
  }) => knowledge.addFoodImage(localFoodId: localFoodId, imageName: imageName);

  /// Taste/category name -> id lookups (lowercased) for normalising a
  /// recognized food's tags against `food_preference` before writing links.
  Future<({Map<String, int> tastes, Map<String, int> categories})>
  preferenceIdLookup() => foodPreference.preferenceIdLookup();

  /// Writes the `local_food_preference` links for a freshly-inserted dish
  /// (tastes with the main taste marked, plus its category).
  Future<void> linkFoodPreferences(
    int localFoodId, {
    required List<int> tasteIds,
    int mainTasteId = 0,
    int? categoryId,
  }) => knowledge.linkFoodPreferences(
    localFoodId,
    tasteIds: tasteIds,
    mainTasteId: mainTasteId,
    categoryId: categoryId,
  );

  /// Writes the `food_dietary_restriction` links for a freshly-inserted dish.
  Future<void> linkFoodDietaryRestrictions(
    int localFoodId,
    List<int> restrictionIds,
  ) => knowledge.linkFoodDietaryRestrictions(localFoodId, restrictionIds);

  Future<bool> toggleFavourite(int localFoodId) =>
      knowledge.toggleFavourite(localFoodId);

  /// The signed-in tourist's favourited food ids (`favourite_food`), or an
  /// empty set when nobody is signed in. Used to prioritise similar foods.
  Future<Set<int>> favouriteFoodIds() => knowledge.favouriteFoodIds();

  /// Canonical taste values from `food_preference`, used to normalise a
  /// food's taste tags against the reference set.
  Future<List<String>> tasteOptions() => foodPreference.tasteOptions();

  /// Reference dietary restrictions (`dietary_restriction`).
  Future<List<DietaryRestriction>> dietaryRestrictions() =>
      dietaryRestriction.restrictions();

  /// The signed-in tourist's dietary restrictions (`user_dietary_restriction`),
  /// resolving the auth user id to the domain `tourist_id` first.
  Future<List<DietaryRestriction>> touristDietaryRestrictions() =>
      dietaryRestriction.restrictionsForCurrentTourist();

  Future<List<FoodPreference>> touristFoodPreferences() async {
    final String? touristId = await auth.currentTouristId();
    if (touristId == null || touristId.isEmpty) {
      return const <FoodPreference>[];
    }
    return touristProfile.getFoodPreferences(touristId);
  }

  /// The restrictions attached to one dish (`food_dietary_restriction`).
  Future<List<DietaryRestriction>> foodDietaryRestrictions(int foodId) =>
      dietaryRestriction.restrictionsForFood(foodId);

  /// Every dish's dietary-restriction ids (`local_food_id -> [restriction ids]`)
  /// in one query, used by pairing to exclude confirmed conflicts before Gemini.
  Future<Map<int, List<int>>> foodDietaryRestrictionIds() =>
      dietaryRestriction.restrictionIdsByFood();

  Future<List<FoodPairing>> getPairings(
    LocalFood food,
    List<LocalFood> catalogue, {
    List<int> touristDietaryRestrictionIds = const <int>[],
    Map<int, List<int>> foodDietaryRestrictionIds = const <int, List<int>>{},
    List<FoodPreference> touristPreferences = const <FoodPreference>[],
    int maximumResults = 5,
    void Function(String model)? onFallbackModel,
  }) => recommendation.getPairings(
    food,
    catalogue,
    touristDietaryRestrictionIds: touristDietaryRestrictionIds,
    foodDietaryRestrictionIds: foodDietaryRestrictionIds,
    touristPreferences: touristPreferences,
    maximumResults: maximumResults,
    onFallbackModel: onFallbackModel,
  );

  /// Lowest and highest listed price per dish, aggregated from every
  /// `restaurant_item` menu row selling those dishes.
  Future<Map<int, ({double min, double max})>> foodPriceRanges(
    Set<int> foodIds,
  ) => restaurant.restaurantPriceRangeByFood(foodIds);

  Future<Map<int, List<({String name, double price})>>> foodMenuItems(
    Set<int> foodIds,
  ) => restaurant.restaurantMenuItemsByFood(foodIds);

  /// "If you liked X, try Y" - computed from shared attributes, no AI call.
  Future<List<FoodSimilarity>> getSimilar(
    LocalFood food,
    List<LocalFood> catalogue,
  ) => recommendation.getSimilar(food, catalogue);
}
