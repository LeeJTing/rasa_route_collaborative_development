import '../app/routing/app_navigator.dart';
import '../core/base_view_model.dart';
import '../domain_model/food_comparison.dart';
import '../domain_model/local_food.dart';
import '../domain_model/pronunciation_playback_result.dart';
import '../model/business_logic/food_logic_facade.dart';

class FoodComparisonViewModel extends BaseViewModel {
  FoodComparisonViewModel();

  final FoodLogicFacade foodLogic = FoodLogicFacade();

  static const int _minimumSelection = 2;

  List<int> _selectedFoodIds = const <int>[];
  List<LocalFood> _catalogue = const <LocalFood>[];
  FoodComparison? _comparison;
  ComparisonSide _replacementSide = ComparisonSide.left;
  bool _isSwitching = false;
  int? _playingPronunciationFoodId;
  String? _pronunciationMessage;

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

  LocalFood? get bestValueFood {
    final FoodComparison? current = _comparison;
    return current == null ? null : foodLogic.bestValueFood(current);
  }

  /// Whether a pronunciation is currently playing (mirrors the food detail
  /// page's `isStartingPronunciation`).
  bool get isStartingPronunciation => _playingPronunciationFoodId != null;

  /// The food id currently playing pronunciation, so that row shows a spinner.
  Set<int> get playingPronunciationFoodIds =>
      _playingPronunciationFoodId == null
      ? const <int>{}
      : <int>{_playingPronunciationFoodId!};

  /// The one-shot message from the last pronunciation attempt, or null when
  /// there is nothing to show (curated audio played fine).
  String? takePronunciationMessage() {
    final String? message = _pronunciationMessage;
    _pronunciationMessage = null;
    return message;
  }

  /// Plays [food]'s pronunciation - the SAME flow as the food detail page:
  /// one playback at a time guarded by [isStartingPronunciation], a plain
  /// try/finally, and the result mapped to a message for the view.
  Future<void> playPronunciation(LocalFood food) async {
    if (isStartingPronunciation) return;
    _playingPronunciationFoodId = food.id;
    _pronunciationMessage = null;
    safeNotifyListeners();
    try {
      final PronunciationPlaybackResult result = await foodLogic
          .playPronunciation(food);
      _pronunciationMessage = switch (result) {
        PronunciationPlaybackResult.curatedAudio => null,
        PronunciationPlaybackResult.deviceVoice =>
          'Using your device voice for this pronunciation.',
        PronunciationPlaybackResult.unavailable =>
          'Pronunciation audio is unavailable on this device.',
      };
    } finally {
      _playingPronunciationFoodId = null;
      safeNotifyListeners();
    }
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
