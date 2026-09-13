import 'package:meta/meta.dart' show visibleForTesting;

import '../app/routing/app_navigator.dart';
import '../app/routing/app_routes.dart';
import '../core/base_view_model.dart';
import '../domain_model/dietary_restriction.dart';
import '../domain_model/food_preference.dart';
import '../domain_model/tourist.dart';
import '../model/business_logic/tourist_information_logic_facade.dart';

/// ViewModel for `ProfileView`.
///
/// The tourist's saved preferences, dietary restrictions and profile links.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class ProfileViewModel extends BaseViewModel {
  ProfileViewModel({
    @visibleForTesting TouristInformationLogicFacade? touristLogic,
  }) : touristLogic = touristLogic ?? TouristInformationLogicFacade();

  final TouristInformationLogicFacade touristLogic;

  List<FoodPreference> _foodPreferences = const <FoodPreference>[];
  List<DietaryRestriction> _dietaryRestrictions = const <DietaryRestriction>[];
  String _email = '';
  bool _discoverySettingsChanged = false;

  /// The signed-in tourist's email (from the auth session).
  String get email => _email;

  /// The taste preferences the tourist selected (e.g. "Sweet", "Sour").
  List<String> get preferredTastes => _foodPreferences
      .where((FoodPreference p) => p.kind == FoodPreferenceKind.taste)
      .map((FoodPreference p) => p.name)
      .toList(growable: false);

  /// The culture/category preferences the tourist selected (e.g. "Malay").
  List<String> get preferredCategories => _foodPreferences
      .where((FoodPreference p) => p.kind == FoodPreferenceKind.category)
      .map((FoodPreference p) => p.name)
      .toList(growable: false);

  List<DietaryRestriction> get dietaryRestrictions =>
      List<DietaryRestriction>.unmodifiable(_dietaryRestrictions);

  /// Whether this Profile visit successfully saved a preference or dietary
  /// change that can affect the Dashboard's Swipe queue.
  bool get discoverySettingsChanged => _discoverySettingsChanged;

  @override
  Future<void> onInit() => load();

  /// Loads the signed-in tourist's preferences and restrictions.
  Future<void> load() => runGuarded(() async {
    final Tourist? tourist = await touristLogic.getTourist();
    if (tourist == null) {
      // Not signed in (or the tourist row can't be resolved) - show nothing.
      _foodPreferences = const <FoodPreference>[];
      _dietaryRestrictions = const <DietaryRestriction>[];
      _email = '';
      return;
    }
    _foodPreferences = tourist.foodPreferences;
    _dietaryRestrictions = tourist.dietaryRestrictions;
    _email = tourist.email;
  });

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  /// Opens the food-preference editor, then refreshes the profile when the
  /// tourist returns. The profile screen is NOT rebuilt when a pushed route
  /// pops (its `State` stays alive), so without this reload the chips would
  /// keep showing the pre-edit selection.
  Future<void> openFoodPreference() async {
    final bool changed =
        await AppNavigator.push<bool>(AppRoutes.editFoodPreference) ?? false;
    if (!changed) return;
    _discoverySettingsChanged = true;
    await load();
  }

  /// Same reload-on-return behaviour for the dietary-restriction editor.
  Future<void> openDietaryRestriction() async {
    final bool changed =
        await AppNavigator.push<bool>(AppRoutes.editDietaryRestriction) ??
        false;
    if (!changed) return;
    _discoverySettingsChanged = true;
    await load();
  }

  void openFavouriteCollection() {
    AppNavigator.push(AppRoutes.favouriteCollection);
  }

  /// "My Landmarks" - open the tourist's contribution history (implemented by
  /// the landmark module, not duplicated here).
  void openSubmittedLandmarks() {
    AppNavigator.push(AppRoutes.landmarkHistory);
  }

  /// "Incomplete Submissions" - the saved (incomplete) Add-New-Landmark
  /// forms the tourist can continue (implemented by the landmark module).
  void openIncompleteLandmarks() {
    AppNavigator.push(AppRoutes.incompleteLandmarks);
  }

  /// Signs the tourist out and returns to the entry screen, clearing the
  /// whole navigation stack.
  Future<void> signOut() => runGuarded(() async {
    await touristLogic.signOut();
    // Await the navigation: `resetTo` is async, so an unawaited failure here
    // would surface as an unhandled error instead of a guarded one.
    await AppNavigator.resetTo(AppRoutes.loginRegister);
  });
}
