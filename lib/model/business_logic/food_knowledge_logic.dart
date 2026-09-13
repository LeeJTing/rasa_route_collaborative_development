import 'package:meta/meta.dart' show protected, visibleForTesting;

import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/pronunciation_playback_result.dart';
import '../repositories/food_repository_facade.dart';

/// The food catalogue: browse, search, detail, pairings and similarity.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
/// It exposes clean methods that Views/ViewModels call.
class FoodKnowledgeLogic {
  FoodKnowledgeLogic();

  @protected
  FoodRepositoryFacade createRepository() => FoodRepositoryFacade();

  late final FoodRepositoryFacade repository = createRepository();

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
  Future<bool> toggleFavouriteFood(int localFoodId) =>
      repository.toggleFavourite(localFoodId);

  /// The signed-in tourist's favourited food ids (empty when signed out),
  /// used to prioritise similar foods.
  Future<Set<int>> favouriteFoodIds() => repository.favouriteFoodIds();

  /// Removes a saved dish without the add-on-missing behaviour of toggle.
  Future<void> removeFavouriteFood(int localFoodId) async {
    final Set<int> savedIds = await repository.favouriteFoodIds();
    if (savedIds.contains(localFoodId)) {
      await repository.toggleFavourite(localFoodId);
    }
  }

  Future<LocalFood> getFoodDetails(int foodId) async {
    final LocalFood? food = await repository.getFoodById(foodId);
    if (food == null) throw Exception('Local food not found.');
    return food;
  }

  Future<bool> isFoodInFavourites(int foodId) async =>
      (await getFoodDetails(foodId)).isFavourite;

  Future<PronunciationPlaybackResult> playPronunciation(LocalFood food) =>
      repository.playPronunciation(food);

  /// Finds another catalogue entry that claims the selected food's canonical
  /// name as an exact synonym. Synonyms are directional: an alias on the
  /// selected food does not make the selected food ambiguous when ordered by
  /// its own canonical name. No dish name or database id is embedded here.
  Future<LocalFood?> detectNameCollision(int foodId) async {
    final List<LocalFood> catalogue = await repository.getFoods();
    return findNameCollision(catalogue: catalogue, foodId: foodId);
  }

  @visibleForTesting
  LocalFood? findNameCollision({
    required List<LocalFood> catalogue,
    required int foodId,
  }) {
    final LocalFood selected = catalogue.firstWhere(
      (LocalFood food) => food.id == foodId,
      orElse: () => throw Exception('Local food not found.'),
    );
    final String selectedName = _normaliseName(selected.name);
    if (selectedName.isEmpty) return null;
    for (final LocalFood candidate in catalogue) {
      if (candidate.id == selected.id) continue;
      if (_normaliseName(candidate.name) == selectedName ||
          candidate.synonyms.any(
            (String synonym) => _normaliseName(synonym) == selectedName,
          )) {
        return candidate;
      }
    }
    return null;
  }

  String _normaliseName(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  Future<String?> dietaryWarning(int foodId) async {
    final List<DietaryRestriction> restrictions = await repository
        .foodDietaryRestrictions(foodId);
    final Map<String, String> labels = <String, String>{};
    for (final DietaryRestriction restriction in restrictions) {
      final String label = restriction.name
          .trim()
          .replaceFirst(RegExp(r'^No\s+', caseSensitive: false), '')
          .trim();
      if (label.isEmpty) continue;
      labels.putIfAbsent(label.toLowerCase(), () => label);
    }
    if (labels.isEmpty) return null;
    return 'Contains or may include: ${labels.values.join(', ')}.';
  }

  Future<List<int>> touristDietaryRestrictionIds() async {
    try {
      final List<DietaryRestriction> restrictions = await repository
          .touristDietaryRestrictions();
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
