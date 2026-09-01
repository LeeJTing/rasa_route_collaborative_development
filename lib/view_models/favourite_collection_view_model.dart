import 'package:meta/meta.dart' show protected;

import '../core/base_view_model.dart';
import '../domain_model/local_food.dart';
import '../model/business_logic/food_logic_facade.dart';

/// ViewModel for `FavouriteCollectionView`.
///
/// The dishes the tourist saved, with swipe-to-remove.
///
/// The food facade provides both the catalogue and the signed-in tourist's
/// saved food ids, keeping this ViewModel on one architecture path.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class FavouriteCollectionViewModel extends BaseViewModel {
  FavouriteCollectionViewModel();

  @protected
  FoodLogicFacade createFoodLogic() => FoodLogicFacade();

  late final FoodLogicFacade foodLogic = createFoodLogic();

  List<LocalFood> _favourites = const <LocalFood>[];

  /// The tourist's favourited dishes.
  List<LocalFood> get favourites => List<LocalFood>.unmodifiable(_favourites);

  @override
  Future<void> onInit() => load();

  /// Loads the favourite dishes by joining the saved `local_food_id`s
  /// (`favourite_food`, profile module) against the catalogue (food module).
  Future<void> load() => runGuarded(() async {
    final List<LocalFood> all = await foodLogic.getLocalFoods();
    final Set<int> savedIds = await foodLogic.favouriteFoodIds();
    _favourites = all
        .where((LocalFood food) => savedIds.contains(food.id))
        .toList(growable: false);
  });

  /// Removes [food] optimistically and restores the database truth on failure.
  Future<void> removeFavourite(LocalFood food) async {
    _favourites = _favourites
        .where((LocalFood favourite) => favourite.id != food.id)
        .toList(growable: false);
    safeNotifyListeners();
    await runGuarded(() => foodLogic.removeFavouriteFood(food.id));
    if (hasError) await load();
  }
}
