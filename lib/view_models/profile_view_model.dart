import '../app/routing/app_navigator.dart';
import '../app/routing/app_routes.dart';
import '../core/base_view_model.dart';
import '../model/business_logic/tourist_information_logic_facade.dart';

/// ViewModel for `ProfileView`.
///
/// The tourist and their saved preferences.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class ProfileViewModel extends BaseViewModel {
  ProfileViewModel();

  final TouristInformationLogicFacade touristLogic =
      TouristInformationLogicFacade();

  /// "Submitted Landmarks" - open the tourist's contribution history.
  void openSubmittedLandmarks() {
    AppNavigator.push(AppRoutes.landmarkHistory);
  }
}
