import '../../domain_model/food_pairing.dart';
import '../../domain_model/food_similarity.dart';
import '../../domain_model/local_food.dart';
import '../repositories/food_repository_facade.dart';

/// Ranks dishes for a tourist and drives the swipe deck.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
class FoodRecommendationLogic {
  FoodRecommendationLogic();

  final FoodRepositoryFacade repository = FoodRepositoryFacade();

  /// AI food-pairing suggestions for [food] (UC406). [catalogue] should be
  /// the already-loaded food list so this makes no extra fetch.
  Future<List<FoodPairing>> pairingsFor(
    LocalFood food,
    List<LocalFood> catalogue,
  ) => repository.getPairings(food, catalogue);

  /// "You might also like" - dishes similar to [food] by shared attributes.
  Future<List<FoodSimilarity>> similarTo(
    LocalFood food,
    List<LocalFood> catalogue,
  ) => repository.getSimilar(food, catalogue);

  Future<List<LocalFood>> getSimilarFoods(int foodId) async {
    final List<LocalFood> catalogue = await repository.getFoods();
    final LocalFood selected = catalogue.firstWhere(
      (LocalFood food) => food.id == foodId,
      orElse: () => throw Exception('Local food not found.'),
    );
    final List<FoodSimilarity> similarities = await similarTo(
      selected,
      catalogue,
    );
    final Map<int, LocalFood> foodsById = <int, LocalFood>{
      for (final LocalFood food in catalogue) food.id: food,
    };
    return similarities
        .map(
          (FoodSimilarity similarity) =>
              foodsById[similarity.similarLocalFoodId],
        )
        .whereType<LocalFood>()
        .take(3)
        .toList(growable: false);
  }

  Future<List<FoodPairing>> getPairingRecommendations(int foodId) async {
    final List<LocalFood> catalogue = await repository.getFoods();
    final LocalFood selected = catalogue.firstWhere(
      (LocalFood food) => food.id == foodId,
      orElse: () => throw Exception('Local food not found.'),
    );
    return pairingsFor(selected, catalogue);
  }
}
