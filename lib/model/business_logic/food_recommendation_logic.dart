import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_pairing.dart';
import '../../domain_model/food_preference.dart';
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
    List<FoodPreference> touristPreferences = const <FoodPreference>[],
    int maximumResults = 5,
    void Function(String model)? onFallbackModel,
  }) => repository.getPairings(
    food,
    catalogue,
    touristDietaryRestrictionIds: touristDietaryRestrictionIds,
    foodDietaryRestrictionIds: foodDietaryRestrictionIds,
    touristPreferences: touristPreferences,
    maximumResults: maximumResults,
    onFallbackModel: onFallbackModel,
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

    final List<FoodSimilarity> sorted = List<FoodSimilarity>.of(
      similarities,
    )..sort((FoodSimilarity a, FoodSimilarity b) => rank(b).compareTo(rank(a)));
    return sorted
        .map((FoodSimilarity s) => byId(s.similarLocalFoodId))
        .whereType<LocalFood>()
        .toList(growable: false);
  }

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
    final Set<int> favouriteIds = await repository.favouriteFoodIds();
    final Set<String> preferredTastes = <String>{};
    for (final LocalFood food in catalogue) {
      if (favouriteIds.contains(food.id)) preferredTastes.addAll(food.tastes);
    }
    final List<LocalFood> ranked = prioritizeSimilar(
      similarities: similarities,
      catalogue: catalogue,
      favouriteIds: favouriteIds,
      preferredTastes: preferredTastes,
    );
    if (ranked.length >= 3) return ranked;
    final Set<int> rankedIds = ranked.map((LocalFood food) => food.id).toSet();
    return <LocalFood>[
      ...ranked,
      ...catalogue.where(
        (LocalFood food) => food.id != foodId && !rankedIds.contains(food.id),
      ),
    ].take(3).toList(growable: false);
  }

  Future<List<FoodPairing>> getPairingRecommendations(
    int foodId, {
    void Function(String model)? onFallbackModel,
  }) async {
    final List<LocalFood> catalogue = await repository.getFoods();
    final LocalFood selected = catalogue.firstWhere(
      (LocalFood food) => food.id == foodId,
      orElse: () => throw Exception('Local food not found.'),
    );
    final List<DietaryRestriction> restrictions = await repository
        .touristDietaryRestrictions();
    final Map<int, List<int>> restrictionIds = await repository
        .foodDietaryRestrictionIds();

    final List<FoodPreference> preferences = await repository
        .touristFoodPreferences();
    return pairingsFor(
      selected,
      catalogue,
      touristDietaryRestrictionIds: restrictions
          .map((DietaryRestriction restriction) => restriction.id)
          .toList(growable: false),
      foodDietaryRestrictionIds: restrictionIds,
      touristPreferences: preferences,
      onFallbackModel: onFallbackModel,
    );
  }
}
