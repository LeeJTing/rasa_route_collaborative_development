import '../../domain_model/food_comparison.dart';
import '../../domain_model/food_pairing.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/pronunciation_playback_result.dart';
import 'food_comparison_logic.dart';
import 'food_knowledge_logic.dart';
import 'food_recommendation_logic.dart';

/// Dishes: catalogue, favourites, comparison and recommendation. Used by the
/// LocalFoodList, FoodDetail, FoodComparison, FoodRecommendation and
/// FavouriteCollection ViewModels.
///
/// LOGIC FACADE - a ViewModel holds ONE of these and talks to it. Behind it the
/// facade fans out to as many business-logic classes as the feature needs. No
/// business rules live here, and it never imports Flutter.
class FoodLogicFacade {
  FoodLogicFacade();

  final FoodKnowledgeLogic knowledge = FoodKnowledgeLogic();
  final FoodComparisonLogic comparison = FoodComparisonLogic();
  final FoodRecommendationLogic recommendation = FoodRecommendationLogic();

  // =========================================================================
  // Forwarded Logic
  // =========================================================================

  /// Get all foods from the catalogue.
  Future<List<LocalFood>> getLocalFoods() => knowledge.getLocalFoods();

  /// Toggle favourite status for a dish.
  Future<bool> toggleFavouriteFood(int foodId) =>
      knowledge.toggleFavouriteFood(foodId);

  Future<Set<int>> favouriteFoodIds() => knowledge.favouriteFoodIds();

  Future<void> removeFavouriteFood(int foodId) =>
      knowledge.removeFavouriteFood(foodId);

  Future<LocalFood> getFoodDetails(int foodId) =>
      knowledge.getFoodDetails(foodId);

  Future<bool> isFoodInFavourites(int foodId) =>
      knowledge.isFoodInFavourites(foodId);

  Future<LocalFood?> detectNameCollision(int foodId) =>
      knowledge.detectNameCollision(foodId);

  Future<String?> dietaryWarning(int foodId) =>
      knowledge.dietaryWarning(foodId);

  Future<List<LocalFood>> getSimilarFoods(int foodId) =>
      recommendation.getSimilarFoods(foodId);

  Future<List<FoodPairing>> getFoodPairingRecommendations(
    int foodId, {
    void Function(String model)? onFallbackModel,
  }) => recommendation.getPairingRecommendations(
    foodId,
    onFallbackModel: onFallbackModel,
  );

  Future<PronunciationPlaybackResult> playPronunciation(LocalFood food) =>
      knowledge.playPronunciation(food);

  // --- Food comparison ------------------------------------------------------

  Future<FoodComparison> buildComparison(List<int> foodIds) =>
      comparison.buildComparison(foodIds);

  LocalFood? bestDietaryMatch(FoodComparison result) =>
      comparison.bestDietaryMatch(result);
}
