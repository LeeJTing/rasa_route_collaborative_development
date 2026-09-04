import 'package:meta/meta.dart' show visibleForTesting;

import '../core/base_view_model.dart';
import '../domain_model/dietary_restriction.dart';
import '../model/business_logic/tourist_information_logic_facade.dart';

/// ViewModel for `EditDietaryRestrictionView`.
///
/// Every dietary restriction the tourist can pick (from the
/// `dietary_restriction` table) plus the currently selected ones. Loading
/// pulls the options and current selection from the DB; Save persists the new
/// selection to `user_dietary_restriction`.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class EditDietaryRestrictionViewModel extends BaseViewModel {
  EditDietaryRestrictionViewModel({
    @visibleForTesting TouristInformationLogicFacade? touristLogic,
  }) : touristLogic = touristLogic ?? TouristInformationLogicFacade();

  final TouristInformationLogicFacade touristLogic;

  List<DietaryRestriction> _restrictions = const <DietaryRestriction>[];
  final Set<int> _selectedIds = <int>{};

  /// Every restriction the tourist can choose from.
  List<DietaryRestriction> get restrictions =>
      List<DietaryRestriction>.unmodifiable(_restrictions);

  /// The currently selected restrictions.
  List<DietaryRestriction> get selectedRestrictions => _restrictions
      .where((DietaryRestriction r) => _selectedIds.contains(r.id))
      .toList(growable: false);

  int get selectedCount => _selectedIds.length;

  bool isSelected(DietaryRestriction restriction) =>
      _selectedIds.contains(restriction.id);

  void toggle(DietaryRestriction restriction) {
    if (!_selectedIds.remove(restriction.id)) {
      _selectedIds.add(restriction.id);
    }
    safeNotifyListeners();
  }

  @override
  Future<void> onInit() => load();

  /// Loads the selectable restrictions and the tourist's current selection.
  Future<void> load() => runGuarded(() async {
    final List<DietaryRestriction> options = await touristLogic
        .dietaryRestrictionOptions();
    final List<DietaryRestriction> current = await touristLogic
        .getDietaryRestrictions();

    _restrictions = options;
    _selectedIds
      ..clear()
      ..addAll(current.map((DietaryRestriction r) => r.id));
  });

  /// Persists the chosen restrictions (replaces the junction rows).
  Future<void> save() => runGuarded(() async {
    await touristLogic.saveDietaryRestrictions(
      _selectedIds.toList(growable: false),
    );
  });
}
