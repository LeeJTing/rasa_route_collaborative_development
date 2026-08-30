import 'package:meta/meta.dart' show visibleForTesting;

import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_pairing.dart';
import '../../domain_model/food_similarity.dart';
import '../../domain_model/local_food.dart';
import '../../shared_client/api_manager/api_manager.dart';
import 'dietary_restriction_repository.dart';
import 'food_knowledge_repository.dart';
import 'food_preference_repository.dart';
import 'recommendation_repository.dart';
import 'swipe_repository.dart';

/// Everything about dishes: the catalogue, favourites, recommendation
/// candidates, the swipe deck, and the food-domain reference data
/// (`food_preference`, `dietary_restriction`).
///
/// REPOSITORY FACADE - a business-logic class holds ONE of these, not four
/// separate repositories. It groups the repositories for one subject area and
/// re-exposes them as a single flat API. No business rules live here.
class FoodRepositoryFacade {
  FoodRepositoryFacade({@visibleForTesting FoodKnowledgeRepository? knowledge})
    : knowledge = knowledge ?? FoodKnowledgeRepository();

  final APIManager api = APIManager();

  final FoodKnowledgeRepository knowledge;
  final RecommendationRepository recommendation = RecommendationRepository();
  final SwipeRepository swipe = SwipeRepository();

  /// Canonical taste/category options (`food_preference`) and reference
  /// dietary restrictions (`dietary_restriction`) - food-domain reference
  /// data read by recognition/recommendation features.
  final FoodPreferenceRepository foodPreference = FoodPreferenceRepository();
  final DietaryRestrictionRepository dietaryRestriction =
      DietaryRestrictionRepository();

  // =========================================================================
  // Flat API - a logic class calls these, never `facade.knowledge.xxx`.
  // =========================================================================

  Future<List<LocalFood>> getFoods() => knowledge.getFoods();

  Future<List<LocalFood>> searchFoods(String query) =>
      knowledge.searchFoods(query);

  Future<LocalFood?> getFoodById(int foodId) => knowledge.getFoodById(foodId);

  /// Adds a genuinely-new, tourist-confirmed Malaysian local food to the
  /// catalogue (Option C - catalogue growth from submissions). Returns the
  /// saved row (with its assigned id) or null when a duplicate exists.
  Future<LocalFood?> insertFood(LocalFood food) => knowledge.insertFood(food);

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

  Future<void> toggleFavourite(int localFoodId) =>
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
    int maximumResults = 5,
  }) => recommendation.getPairings(
    food,
    catalogue,
    touristDietaryRestrictionIds: touristDietaryRestrictionIds,
    foodDietaryRestrictionIds: foodDietaryRestrictionIds,
    maximumResults: maximumResults,
  );

  /// "If you liked X, try Y" - computed from shared attributes, no AI call.
  Future<List<FoodSimilarity>> getSimilar(
    LocalFood food,
    List<LocalFood> catalogue,
  ) => recommendation.getSimilar(food, catalogue);
}
