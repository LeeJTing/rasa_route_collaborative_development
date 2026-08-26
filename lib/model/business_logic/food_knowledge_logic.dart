import '../repositories/food_repository_facade.dart';
import '../../domain_model/local_food.dart';

/// The food catalogue: browse, search, detail, pairings and similarity.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
/// It exposes clean methods that Views/ViewModels call.
class FoodKnowledgeLogic {
  FoodKnowledgeLogic();

  final FoodRepositoryFacade repository = FoodRepositoryFacade();

  // =========================================================================
  // Public API for ViewModels
  // =========================================================================

  /// Fetch all local foods catalogue.
  Future<List<LocalFood>> getLocalFoods() => repository.getFoods();

  /// Search foods by query string.
  Future<List<LocalFood>> searchLocalFoods(String query) =>
      repository.searchFoods(query);

  /// Get single food by ID.
  Future<LocalFood?> getLocalFoodById(int foodId) =>
      repository.getFoodById(foodId);

  /// Toggle favourite status (add if missing, remove if present).
  Future<void> toggleFavouriteFood(int localFoodId) =>
      repository.toggleFavourite(localFoodId);
}
