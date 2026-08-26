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
  FoodRepositoryFacade();

  final APIManager api = APIManager();

  final FoodKnowledgeRepository knowledge = FoodKnowledgeRepository();
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

  Future<void> toggleFavourite(int localFoodId) =>
      knowledge.toggleFavourite(localFoodId);

  /// Canonical taste values from `food_preference`, used to normalise a
  /// food's taste tags against the reference set.
  Future<List<String>> tasteOptions() => foodPreference.tasteOptions();

  /// Reference dietary restrictions (`dietary_restriction`).
  Future<List<DietaryRestriction>> dietaryRestrictions() =>
      dietaryRestriction.restrictions();

  /// The signed-in tourist's dietary restrictions (`user_dietary_restriction`),
  /// keyed by `tourist_id` = the current auth user.
  Future<List<DietaryRestriction>> touristDietaryRestrictions() =>
      dietaryRestriction.restrictionsForTourist(api.currentUserId);

  /// The restrictions attached to one dish (`food_dietary_restriction`).
  Future<List<DietaryRestriction>> foodDietaryRestrictions(int foodId) =>
      dietaryRestriction.restrictionsForFood(foodId);

  /// AI-generated pairing suggestions for [food], matched against [catalogue].
  Future<List<FoodPairing>> getPairings(
    LocalFood food,
    List<LocalFood> catalogue,
  ) => recommendation.getPairings(food, catalogue);

  /// "If you liked X, try Y" - computed from shared attributes, no AI call.
  Future<List<FoodSimilarity>> getSimilar(
    LocalFood food,
    List<LocalFood> catalogue,
  ) => recommendation.getSimilar(food, catalogue);
}
