import 'package:meta/meta.dart' show visibleForTesting;

import '../core/base_view_model.dart';
import '../domain_model/dietary_restriction.dart';
import '../domain_model/food_preference.dart';
import '../model/business_logic/tourist_information_logic_facade.dart';

/// ViewModel for `ProfileSetUpView`.
///
/// C3 - first-run capture of the tourist's food preferences (tastes +
/// cultures) and dietary restrictions BEFORE they reach the dashboard. The
/// selectable options come from Supabase (`food_preference` /
/// `dietary_restriction` reference tables); the tourist's picks are persisted
/// through the profile logic just like the edit screens.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class ProfileSetUpViewModel extends BaseViewModel {
  ProfileSetUpViewModel({
    @visibleForTesting TouristInformationLogicFacade? touristLogic,
  }) : touristLogic = touristLogic ?? TouristInformationLogicFacade();

  final TouristInformationLogicFacade touristLogic;

  List<FoodPreference> _foodPreferences = const <FoodPreference>[];
  List<DietaryRestriction> _dietaryRestrictions = const <DietaryRestriction>[];
  final Set<int> _selectedPreferenceIds = <int>{};
  final Set<int> _selectedRestrictionIds = <int>{};
  bool _saved = false;

  /// True once [save] persisted both selections - the View navigates on this.
  bool get saved => _saved;

  /// Every selectable taste, keeping the option list's order.
  List<FoodPreference> get tasteOptions => _foodPreferences
      .where((FoodPreference p) => p.kind == FoodPreferenceKind.taste)
      .toList(growable: false);

  /// Every selectable culture/category, keeping the option list's order.
  List<FoodPreference> get categoryOptions => _foodPreferences
      .where((FoodPreference p) => p.kind == FoodPreferenceKind.category)
      .toList(growable: false);

  /// Every selectable dietary restriction, keeping the option list's order.
  List<DietaryRestriction> get dietaryOptions =>
      List<DietaryRestriction>.unmodifiable(_dietaryRestrictions);

  int get selectedPreferenceCount => _selectedPreferenceIds.length;
  int get selectedRestrictionCount => _selectedRestrictionIds.length;

  /// Total picks across both sections - the gate for "Continue".
  int get selectedCount => selectedPreferenceCount + selectedRestrictionCount;

  /// The Continue button is enabled once the tourist picked at least one
  /// option (either a preference or a restriction) - this also prevents a
  /// completed-but-empty profile from being re-flagged as "not set up" on the
  /// next sign-in.
  bool get canContinue => selectedCount > 0 && !isBusy;

  bool isPreferenceSelected(FoodPreference preference) =>
      _selectedPreferenceIds.contains(preference.id);

  bool isDietarySelected(DietaryRestriction restriction) =>
      _selectedRestrictionIds.contains(restriction.id);

  void togglePreference(FoodPreference preference) {
    _toggle(_selectedPreferenceIds, preference.id);
  }

  void toggleDietary(DietaryRestriction restriction) {
    _toggle(_selectedRestrictionIds, restriction.id);
  }

  void _toggle(Set<int> ids, int id) {
    if (!ids.remove(id)) ids.add(id);
    safeNotifyListeners();
  }

  @override
  Future<void> onInit() => load();

  /// Loads the selectable options from Supabase plus the tourist's current
  /// selection (so an abandoned first run resumes where they left off).
  Future<void> load() => runGuarded(() async {
    final List<FoodPreference> preferences = await touristLogic
        .foodPreferenceOptions();
    final List<DietaryRestriction> restrictions = await touristLogic
        .dietaryRestrictionOptions();
    final List<FoodPreference> currentPreferences = await touristLogic
        .getFoodPreferences();
    final List<DietaryRestriction> currentRestrictions = await touristLogic
        .getDietaryRestrictions();

    _foodPreferences = preferences;
    _dietaryRestrictions = restrictions;
    _selectedPreferenceIds
      ..clear()
      ..addAll(currentPreferences.map((FoodPreference p) => p.id));
    _selectedRestrictionIds
      ..clear()
      ..addAll(currentRestrictions.map((DietaryRestriction r) => r.id));
  });

  /// Persists both selections, then marks the set-up complete.
  Future<void> save() => runGuarded(() async {
    await touristLogic.saveFoodPreferences(
      _selectedPreferenceIds.toList(growable: false),
    );
    await touristLogic.saveDietaryRestrictions(
      _selectedRestrictionIds.toList(growable: false),
    );
    _saved = true;
  });
}
