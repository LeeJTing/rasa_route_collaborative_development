import 'package:meta/meta.dart' show visibleForTesting;

import '../core/base_view_model.dart';
import '../domain_model/food_preference.dart';
import '../model/business_logic/tourist_information_logic_facade.dart';

/// ViewModel for `EditFoodPreferenceView`.
///
/// The tourist's taste and culture preferences. Each [FoodPreference] is ONE
/// option (a taste or a category) with an `id`; the tourist picks any number
/// and the chosen ones float to the top ("Selected items appear on top").
/// Loading pulls the options and the current selection from the DB
/// (`food_preference` + `personalised_preference`); Save persists the new
/// selection by id.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class EditFoodPreferenceViewModel extends BaseViewModel {
  EditFoodPreferenceViewModel({
    @visibleForTesting TouristInformationLogicFacade? touristLogic,
  }) : touristLogic = touristLogic ?? TouristInformationLogicFacade();

  final TouristInformationLogicFacade touristLogic;

  /// Every selectable option (tastes + categories mixed).
  List<FoodPreference> _options = const <FoodPreference>[];
  final Set<int> _selectedIds = <int>{};

  /// Every selectable taste, keeping the option list's order.
  List<FoodPreference> get tasteOptions => _options
      .where((FoodPreference p) => p.kind == FoodPreferenceKind.taste)
      .toList(growable: false);

  /// Every selectable culture/category, keeping the option list's order.
  List<FoodPreference> get categoryOptions => _options
      .where((FoodPreference p) => p.kind == FoodPreferenceKind.category)
      .toList(growable: false);

  /// The chosen tastes, keeping the option list's order.
  List<FoodPreference> get selectedTastes =>
      tasteOptions.where(_isSelected).toList(growable: false);

  /// The remaining (unchosen) tastes, keeping the option list's order.
  List<FoodPreference> get unselectedTastes => tasteOptions
      .where((FoodPreference p) => !_isSelected(p))
      .toList(growable: false);

  /// The chosen cultures, keeping the option list's order.
  List<FoodPreference> get selectedCategories =>
      categoryOptions.where(_isSelected).toList(growable: false);

  /// The remaining (unchosen) cultures, keeping the option list's order.
  List<FoodPreference> get unselectedCategories => categoryOptions
      .where((FoodPreference p) => !_isSelected(p))
      .toList(growable: false);

  int get selectedTasteCount => selectedTastes.length;
  int get selectedCategoryCount => selectedCategories.length;

  bool isTasteSelected(FoodPreference preference) => _isSelected(preference);
  bool isCategorySelected(FoodPreference preference) => _isSelected(preference);

  void toggleTaste(FoodPreference preference) => _toggle(preference.id);
  void toggleCategory(FoodPreference preference) => _toggle(preference.id);

  bool _isSelected(FoodPreference preference) =>
      _selectedIds.contains(preference.id);

  void _toggle(int id) {
    if (!_selectedIds.remove(id)) _selectedIds.add(id);
    safeNotifyListeners();
  }

  @override
  Future<void> onInit() => load();

  /// Loads the selectable options and the tourist's current selection.
  Future<void> load() => runGuarded(() async {
    final List<FoodPreference> options = await touristLogic
        .foodPreferenceOptions();
    final List<FoodPreference> current = await touristLogic
        .getFoodPreferences();

    _options = options;
    _selectedIds
      ..clear()
      ..addAll(current.map((FoodPreference p) => p.id));
  });

  /// Persists the chosen preferences (replaces the junction rows).
  Future<void> save() => runGuarded(() async {
    await touristLogic.saveFoodPreferences(
      _selectedIds.toList(growable: false),
    );
  });
}
