import '../../domain_model/food_comparison.dart';
import '../../domain_model/food_pairing.dart';
import '../../domain_model/food_similarity.dart';
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

  Future<LocalFood> getFoodDetails(int foodId) async {
    final LocalFood? food = await knowledge.getLocalFoodById(foodId);
    if (food == null) throw Exception('Local food not found.');
    return food;
  }

  Future<bool> isFoodInFavourites(int foodId) async =>
      (await getFoodDetails(foodId)).isFavourite;

  Future<LocalFood?> detectNameCollision(int foodId) async {
    final LocalFood selected = await getFoodDetails(foodId);
    if (selected.name != 'Prawn Noodle') return null;
    return knowledge.getLocalFoodById(5);
  }

  Future<List<String>> detectAllergies(LocalFood food) async {
    final String ingredients = food.ingredients.toLowerCase();
    final List<String> warnings = <String>[];
    if (ingredients.contains('prawn') ||
        ingredients.contains('seafood') ||
        ingredients.contains('shellfish')) {
      warnings.add('People with seafood allergy should avoid this dish.');
    }
    if (ingredients.contains('peanut') || ingredients.contains('nut')) {
      warnings.add('People with nut allergies should avoid this dish.');
    }
    return warnings;
  }

  Future<List<LocalFood>> getSimilarFoods(int foodId) async {
    final List<LocalFood> catalogue = await knowledge.getLocalFoods();
    final LocalFood selected = catalogue.firstWhere(
      (LocalFood food) => food.id == foodId,
      orElse: () => throw Exception('Local food not found.'),
    );
    final List<FoodSimilarity> similarities = await recommendation.similarTo(
      selected,
      catalogue,
    );

    // Prioritise for the signed-in tourist: favourites, and the tastes they
    // prefer (derived from their favourite dishes), rank higher. There is no
    // per-user food-preference table yet, so preferences are inferred from the
    // favourite collection.
    final Set<int> favouriteIds = await knowledge.favouriteFoodIds();
    final Set<String> preferredTastes = <String>{};
    for (final LocalFood food in catalogue) {
      if (favouriteIds.contains(food.id)) {
        preferredTastes.addAll(food.tastes);
      }
    }

    final List<LocalFood> ranked = recommendation.prioritizeSimilar(
      similarities: similarities,
      catalogue: catalogue,
      favouriteIds: favouriteIds,
      preferredTastes: preferredTastes,
    );
    if (ranked.length >= 3) return ranked;

    const List<int> fallbackIds = <int>[9, 10, 4];
    return catalogue
        .where((LocalFood food) => fallbackIds.contains(food.id))
        .take(3)
        .toList(growable: false);
  }

  Future<List<FoodPairing>> getFoodPairingRecommendations(int foodId) async {
    final List<LocalFood> catalogue = await knowledge.getLocalFoods();
    final LocalFood selected = catalogue.firstWhere(
      (LocalFood food) => food.id == foodId,
      orElse: () => throw Exception('Local food not found.'),
    );
    // Dietary-safety ids from the DB relations (`user_dietary_restriction` and
    // `food_dietary_restriction`); conflicting foods are excluded before the
    // prompt, so only the food data reaches Gemini.
    final List<int> touristRestrictionIds =
        await knowledge.touristDietaryRestrictionIds();
    final Map<int, List<int>> foodRestrictionIds =
        await knowledge.foodDietaryRestrictionIds();
    return recommendation.pairingsFor(
      selected,
      catalogue,
      touristDietaryRestrictionIds: touristRestrictionIds,
      foodDietaryRestrictionIds: foodRestrictionIds,
    );
  }

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
