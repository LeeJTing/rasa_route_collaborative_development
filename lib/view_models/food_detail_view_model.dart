import '../core/base_view_model.dart';
import '../model/business_logic/discovery_logic_facade.dart';
import '../model/business_logic/food_logic_facade.dart';

/// ViewModel for `FoodDetailView`.
///
/// One dish, its pairings, similar dishes and where to eat it.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class FoodDetailViewModel extends BaseViewModel {
  FoodDetailViewModel();

  final FoodLogicFacade foodLogic = FoodLogicFacade();
  final DiscoveryLogicFacade discoveryLogic = DiscoveryLogicFacade();
}
