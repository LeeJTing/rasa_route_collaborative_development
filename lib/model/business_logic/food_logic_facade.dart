import '../../domain_model/food_comparison.dart';
import '../../domain_model/food_pairing.dart';
import '../../domain_model/local_food.dart';
import '../../shared_client/device_capability_manager/device_capability_manager.dart';
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
  final DeviceCapabilityManager deviceCapabilities = DeviceCapabilityManager();

  // =========================================================================
  // Forwarded Logic
  // =========================================================================

  /// Get all foods from the catalogue.
  Future<List<LocalFood>> getLocalFoods() => knowledge.getLocalFoods();

  /// Toggle favourite status for a dish.
  Future<void> toggleFavouriteFood(int foodId) =>
      knowledge.toggleFavouriteFood(foodId);

  Future<LocalFood> getFoodDetails(int foodId) =>
      knowledge.getFoodDetails(foodId);

  Future<bool> isFoodInFavourites(int foodId) =>
      knowledge.isFoodInFavourites(foodId);

  Future<LocalFood?> detectNameCollision(int foodId) =>
      knowledge.detectNameCollision(foodId);

  List<String> detectAllergies(LocalFood food) =>
      knowledge.detectAllergies(food);

  Future<List<LocalFood>> getSimilarFoods(int foodId) =>
      recommendation.getSimilarFoods(foodId);

  Future<List<FoodPairing>> getFoodPairingRecommendations(int foodId) =>
      recommendation.getPairingRecommendations(foodId);

  Future<PronunciationPlaybackResult> playPronunciation(LocalFood food) async {
    final DevicePronunciationPlaybackResult result = await deviceCapabilities
        .playPronunciation(foodName: food.name, audioUrl: food.audioGuideUrl);
    return switch (result) {
      DevicePronunciationPlaybackResult.curatedAudio =>
        PronunciationPlaybackResult.curatedAudio,
      DevicePronunciationPlaybackResult.deviceVoice =>
        PronunciationPlaybackResult.deviceVoice,
      DevicePronunciationPlaybackResult.unavailable =>
        PronunciationPlaybackResult.unavailable,
    };
  }

  // --- Food comparison ------------------------------------------------------

  Future<FoodComparison> buildComparison(List<int> foodIds) =>
      comparison.buildComparison(foodIds);

  LocalFood? bestDietaryMatch(FoodComparison result) =>
      comparison.bestDietaryMatch(result);

  LocalFood? bestValueFood(FoodComparison result) =>
      comparison.bestValueFood(result);
}

/// Stable business-layer result exposed to presentation code.
enum PronunciationPlaybackResult { curatedAudio, deviceVoice, unavailable }
