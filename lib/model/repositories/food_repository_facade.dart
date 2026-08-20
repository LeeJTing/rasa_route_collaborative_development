import '../../domain_model/food_pairing.dart';
import '../../domain_model/food_similarity.dart';
import '../../domain_model/local_food.dart';
import 'food_knowledge_repository.dart';
import 'recommendation_repository.dart';
import 'swipe_repository.dart';

/// Everything about dishes: the catalogue, favourites, recommendation candidates and the swipe deck.
///
/// REPOSITORY FACADE - a business-logic class holds ONE of these, not four
/// separate repositories. It groups the repositories for one subject area and
/// re-exposes them as a single flat API. No business rules live here.
class FoodRepositoryFacade {
  FoodRepositoryFacade();

  final FoodKnowledgeRepository knowledge = FoodKnowledgeRepository();
  final RecommendationRepository recommendation = RecommendationRepository();
  final SwipeRepository swipe = SwipeRepository();

  // =========================================================================
  // Flat API - a logic class calls these, never `facade.knowledge.xxx`.
  // =========================================================================

  Future<List<LocalFood>> getFoods() => knowledge.getFoods();

  Future<List<LocalFood>> searchFoods(String query) =>
      knowledge.searchFoods(query);

  Future<LocalFood?> getFoodById(int foodId) => knowledge.getFoodById(foodId);

  Future<void> toggleFavourite(int localFoodId) =>
      knowledge.toggleFavourite(localFoodId);

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
