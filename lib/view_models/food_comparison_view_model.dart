import '../app/routing/app_navigator.dart';
import '../core/base_view_model.dart';
import '../domain_model/food_comparison.dart';
import '../domain_model/local_food.dart';
import '../model/business_logic/food_logic_facade.dart';

/// ViewModel for `FoodComparisonView`.
///
/// Side-by-side comparison of the selected dishes, plus the "quick switch"
/// bar that swaps a dish in and out of either slot.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class FoodComparisonViewModel extends BaseViewModel {
  FoodComparisonViewModel();

  final FoodLogicFacade foodLogic = FoodLogicFacade();

  static const int _minimumSelection = 2;

  List<int> _selectedFoodIds = const <int>[];
  List<LocalFood> _catalogue = const <LocalFood>[];
  FoodComparison? _comparison;
  ComparisonSide _replacementSide = ComparisonSide.left;
  bool _isSwitching = false;

  /// Minimum dishes needed before a comparison can be built.
  int get minimumSelection => _minimumSelection;

  FoodComparison? get comparison => _comparison;
  ComparisonSide get replacementSide => _replacementSide;

  /// True while a quick-switch replacement is being fetched.
  bool get isSwitching => _isSwitching;

  /// Best dietary match for the tourist's restrictions, if any.
  LocalFood? get recommendedFood {
    final FoodComparison? current = _comparison;
    return current == null ? null : foodLogic.bestDietaryMatch(current);
  }

  /// Best-priced dish - no restaurant price data yet, so always `null` and
  /// the UI shows "Not enough price data".
  LocalFood? get bestValueFood {
    final FoodComparison? current = _comparison;
    return current == null ? null : foodLogic.bestValueFood(current);
  }

  /// The remaining selected dishes beyond the two side-by-side slots (A7.1) -
  /// these appear in the quick-switcher bar for swapping into a slot.
  List<LocalFood> get quickSwitcherFoods {
    if (_selectedFoodIds.length <= 2) return const <LocalFood>[];
    final Map<int, LocalFood> byId = <int, LocalFood>{
      for (final LocalFood food in _catalogue) food.id: food,
    };
    return _selectedFoodIds
        .skip(2)
        .map((int id) => byId[id])
        .whereType<LocalFood>()
        .toList(growable: false);
  }

  /// Loads the dishes picked by the caller (route arguments) and builds the
  /// comparison. With fewer than [minimumSelection] dishes the screen lands
  /// in the "select at least N" state.
  Future<void> loadSelectedFoodIds(List<int> foodIds) async {
    _selectedFoodIds = List<int>.from(foodIds);
    await _loadCatalogue();
    if (_selectedFoodIds.length < _minimumSelection) {
      _comparison = null;
      setError(
        Exception('Select at least $_minimumSelection local foods to compare.'),
      );
      return;
    }
    await _buildComparison();
  }

  /// Which slot a quick-switch replacement targets.
  void chooseReplacementSide(ComparisonSide side) {
    if (_replacementSide == side) return;
    _replacementSide = side;
    safeNotifyListeners();
  }

  /// Swaps the dish in the current slot with [foodId] from the quick-switcher
  /// bar and rebuilds the comparison (A7.1).
  Future<void> replaceWith(int foodId) async {
    if (_selectedFoodIds.length < 2) return;
    final int foodIndex = _selectedFoodIds.indexOf(foodId);
    if (foodIndex < 2) return; // Already in a slot.
    final int slotIndex = _replacementSide == ComparisonSide.left ? 0 : 1;
    final List<int> next = List<int>.from(_selectedFoodIds);
    next[slotIndex] = foodId;
    next[foodIndex] = _selectedFoodIds[slotIndex];
    _selectedFoodIds = next;
    _isSwitching = true;
    safeNotifyListeners();
    await _buildComparison();
    _isSwitching = false;
    safeNotifyListeners();
  }

  /// Back to the local-food list.
  void goBack() => AppNavigator.pop();

  Future<void> _loadCatalogue() async {
    try {
      _catalogue = await foodLogic.getLocalFoods();
      safeNotifyListeners();
    } catch (_) {
      // Catalogue is only needed for the quick-switch bar - a failure here
      // must not block the comparison itself.
    }
  }

  /// The two dishes currently in the side-by-side slots - the first two the
  /// tourist selected (A7.1 assigns the first to the left slot and the second
  /// to the right slot).
  List<int> get _slotIds => _selectedFoodIds.length >= 2
      ? _selectedFoodIds.sublist(0, 2)
      : const <int>[];

  Future<void> _buildComparison() => runGuarded(() async {
    _comparison = await foodLogic.buildComparison(_slotIds);
  });
}
