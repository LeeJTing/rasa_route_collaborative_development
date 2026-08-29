import '../../domain_model/dietary_restriction.dart';
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

  /// The signed-in tourist's favourited food ids (empty when signed out),
  /// used to prioritise similar foods.
  Future<Set<int>> favouriteFoodIds() => repository.favouriteFoodIds();

  Future<LocalFood> getFoodDetails(int foodId) async {
    final LocalFood? food = await repository.getFoodById(foodId);
    if (food == null) throw Exception('Local food not found.');
    return food;
  }

  Future<bool> isFoodInFavourites(int foodId) async =>
      (await getFoodDetails(foodId)).isFavourite;

  /// Finds another catalogue entry whose canonical name or synonym overlaps
  /// with the selected food. Collision detection is data-driven; no dish name
  /// or database id is embedded in the app.
  Future<LocalFood?> detectNameCollision(int foodId) async {
    final List<LocalFood> catalogue = await repository.getFoods();
    final LocalFood selected = catalogue.firstWhere(
      (LocalFood food) => food.id == foodId,
      orElse: () => throw Exception('Local food not found.'),
    );
    final Set<String> selectedNames = <String>{
      selected.name.toLowerCase(),
      ...selected.synonyms.map((String value) => value.toLowerCase()),
    };
    for (final LocalFood candidate in catalogue) {
      if (candidate.id == selected.id) continue;
      final Set<String> candidateNames = <String>{
        candidate.name.toLowerCase(),
        ...candidate.synonyms.map((String value) => value.toLowerCase()),
      };
      if (selectedNames.intersection(candidateNames).isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }

  List<String> detectAllergies(LocalFood food) {
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

  Future<List<int>> touristDietaryRestrictionIds() async {
    try {
      final List<DietaryRestriction> restrictions =
      await repository.touristDietaryRestrictions();
      return restrictions
          .map((DietaryRestriction r) => r.id)
          .toList(growable: false);
    } catch (_) {
      return const <int>[];
    }
  }

  /// Every dish's dietary-restriction ids (`food_dietary_restriction`) in one
  /// query, used by pairing to exclude confirmed conflicts before Gemini.
  ///
  /// Fails soft: an unavailable relation degrades to "no labels" so pairing
  /// still runs.
  Future<Map<int, List<int>>> foodDietaryRestrictionIds() async {
    try {
      return await repository.foodDietaryRestrictionIds();
    } catch (_) {
      return const <int, List<int>>{};
    }
  }
}
