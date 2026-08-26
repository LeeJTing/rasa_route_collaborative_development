import '../core/base_view_model.dart';
import '../model/business_logic/food_logic_facade.dart';
import '../model/business_logic/tourist_information_logic_facade.dart';

/// ViewModel for `FavouriteCollectionView`.
///
/// The dishes the tourist saved.
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

  final FoodLogicFacade foodLogic = FoodLogicFacade();
  final TouristInformationLogicFacade touristLogic =
      TouristInformationLogicFacade();
}
