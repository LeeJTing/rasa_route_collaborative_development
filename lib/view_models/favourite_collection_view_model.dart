import 'package:meta/meta.dart' show visibleForTesting;

import '../core/base_view_model.dart';
import '../domain_model/local_food.dart';
import '../model/business_logic/food_logic_facade.dart';

/// ViewModel for `FavouriteCollectionView`.
///
/// The dishes the tourist saved, with swipe-to-remove.
///
/// The `favourite_food` junction is keyed by `tourist.tourist_id`, so the
/// "which dishes did THIS tourist save" question belongs to the profile module
/// (`touristLogic.favouriteFoodIds` / `removeFavourite`). The catalogue
/// itself (a `LocalFood` list) belongs to the food module
/// (`foodLogic.getLocalFoods`) - this ViewModel joins the two.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class FavouriteCollectionViewModel extends BaseViewModel {
  FavouriteCollectionViewModel({
    @visibleForTesting FoodLogicFacade? foodLogic,
    @visibleForTesting TouristInformationLogicFacade? touristLogic,
  }) : foodLogic = foodLogic ?? FoodLogicFacade(),
       touristLogic = touristLogic ?? TouristInformationLogicFacade();

  final FoodLogicFacade foodLogic;
  final TouristInformationLogicFacade touristLogic;

  List<LocalFood> _favourites = const <LocalFood>[];

  /// The tourist's favourited dishes.
  List<LocalFood> get favourites => List<LocalFood>.unmodifiable(_favourites);

  @override
  Future<void> onInit() => load();

  /// Loads the favourite dishes by joining the saved `local_food_id`s
  /// (`favourite_food`, profile module) against the catalogue (food module).
  Future<void> load() => runGuarded(() async {
    final List<LocalFood> all = await foodLogic.getLocalFoods();
    final Set<int> savedIds = await touristLogic.favouriteFoodIds();
    _favourites = all
        .where((LocalFood food) => savedIds.contains(food.id))
        .toList(growable: false);
  });

  final FoodLogicFacade foodLogic = FoodLogicFacade();
}
