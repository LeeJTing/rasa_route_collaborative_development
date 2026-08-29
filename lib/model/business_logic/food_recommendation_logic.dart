import '../../domain_model/food_pairing.dart';
import '../../domain_model/food_similarity.dart';
import '../../domain_model/local_food.dart';
import '../repositories/food_repository_facade.dart';

class FoodRecommendationLogic {
  FoodRecommendationLogic();

  final FoodRepositoryFacade repository = FoodRepositoryFacade();
  Future<List<FoodPairing>> pairingsFor(
    LocalFood food,
    List<LocalFood> catalogue, {
    List<int> touristDietaryRestrictionIds = const <int>[],
    Map<int, List<int>> foodDietaryRestrictionIds = const <int, List<int>>{},
    int maximumResults = 5,
  }) => repository.getPairings(
    food,
    catalogue,
    touristDietaryRestrictionIds: touristDietaryRestrictionIds,
    foodDietaryRestrictionIds: foodDietaryRestrictionIds,
    maximumResults: maximumResults,
  );

  /// "You might also like" - dishes similar to [food] by shared attributes.
  Future<List<FoodSimilarity>> similarTo(
    LocalFood food,
    List<LocalFood> catalogue,
  ) => repository.getSimilar(food, catalogue);

  /// Re-ranks [similarities] for the signed-in tourist: dishes that are
  /// favourites or match [preferredTastes] float to the top, with the base
  /// similarity score breaking ties. Returns the dishes in priority order.
  List<LocalFood> prioritizeSimilar({
    required List<FoodSimilarity> similarities,
    required List<LocalFood> catalogue,
    required Set<int> favouriteIds,
    required Set<String> preferredTastes,
  }) {
    LocalFood? byId(int id) {
      for (final LocalFood food in catalogue) {
        if (food.id == id) return food;
      }
      return null;
    }

    double rank(FoodSimilarity similarity) {
      double score = similarity.score;
      if (favouriteIds.contains(similarity.similarLocalFoodId)) score += 0.2;
      final LocalFood? food = byId(similarity.similarLocalFoodId);
      if (food != null) {
        final int overlap = food.tastes.where(preferredTastes.contains).length;
        if (overlap > 0) score += 0.1 * overlap;
      }
      return score;
    }

    final List<FoodSimilarity> sorted = List<FoodSimilarity>.of(similarities)
      ..sort(
        (FoodSimilarity a, FoodSimilarity b) => rank(b).compareTo(rank(a)),
      );
    return sorted
        .map((FoodSimilarity s) => byId(s.similarLocalFoodId))
        .whereType<LocalFood>()
        .toList(growable: false);
  }
}
