import 'dart:developer' as developer;

import '../core/base_view_model.dart';
import '../domain_model/food_pairing.dart';
import '../domain_model/local_food.dart';
import '../model/business_logic/food_logic_facade.dart';

/// Food pairing recommendations for one selected dish (UC406).
///
/// Loads the catalogue so each paired dish's image - resolved from the
/// `local_food_image` table via `LocalFood.imageUrls` - can be looked up by
/// the food id Gemini returns, then asks Gemini for the best pairings.
class FoodRecommendationViewModel extends BaseViewModel {
  FoodRecommendationViewModel({this.foodId = 1});

  final FoodLogicFacade foodLogic = FoodLogicFacade();

  int foodId;
  List<LocalFood> _catalogue = const <LocalFood>[];
  LocalFood? _selectedFood;
  List<LocalFood> _similarFoods = const <LocalFood>[];
  List<FoodPairing> _pairings = const <FoodPairing>[];
  bool _pairingTimedOut = false;
  bool _loadingPairings = false;
  String? _pairingError;
  String? _pairingFallbackModel;

  List<LocalFood> get catalogue => _catalogue;
  LocalFood? get selectedFood => _selectedFood;
  List<LocalFood> get similarFoods => _similarFoods;
  List<FoodPairing> get pairings => _pairings;
  bool get pairingTimedOut => _pairingTimedOut;
  bool get loadingPairings => _loadingPairings;
  String? get pairingError => _pairingError;

  /// The Gemini model that served the current pairings when the primary model
  /// was unavailable (HTTP 429/5xx) and the request rotated to one of the
  /// env-configured fallbacks (`GEMINI_FALLBACK_MODELS`). Null when the
  /// primary model handled the request or no request ran yet.
  String? get pairingFallbackModel => _pairingFallbackModel;

  LocalFood? pairedFood(int id) {
    for (final LocalFood food in _catalogue) {
      if (food.id == id) return food;
    }
    return null;
  }

  @override
  Future<void> onInit() => load(foodId);

  Future<void> load(int id) => runGuarded(() async {
    foodId = id;
    _pairingTimedOut = false;
    _similarFoods = const <LocalFood>[];
    _catalogue = await foodLogic.getLocalFoods();
    LocalFood? selected;
    for (final LocalFood food in _catalogue) {
      if (food.id == id) {
        selected = food;
        break;
      }
    }
    // The cached catalogue can be stale for this dish (e.g. right after
    // navigating from a pairing card). Fetch the dish fresh instead of
    // silently reporting "no suitable pairings" when it isn't in the cache.
    if (selected == null) {
      developer.log(
        'Food #$id not in cached catalogue - fetching fresh detail.',
        name: 'FoodRecommendationViewModel',
      );
      try {
        selected = await foodLogic.getFoodDetails(id);
      } catch (_) {
        selected = null;
      }
      if (selected != null) {
        _catalogue = <LocalFood>[selected, ..._catalogue];
      }
    }
    _selectedFood = selected;
    if (selected == null) {
      _pairings = const <FoodPairing>[];
    } else {
      _similarFoods = await foodLogic.getSimilarFoods(id);
      await _loadPairings();
    }
  });

  Future<void> retryPairings() => runGuarded(_loadPairings, silent: true);

  Future<void> _loadPairings() async {
    _loadingPairings = true;
    _pairingTimedOut = false;
    _pairingError = null;
    _pairingFallbackModel = null;
    _pairings = const <FoodPairing>[];
    safeNotifyListeners();
    try {
      _pairings = await foodLogic.getFoodPairingRecommendations(
        foodId,
        onFallbackModel: (String model) => _pairingFallbackModel = model,
      );
      if (_pairings.isEmpty) {
        developer.log(
          'Pairings for food #$foodId came back empty.',
          name: 'FoodRecommendationViewModel',
        );
      }
    } catch (error) {
      _pairings = const <FoodPairing>[];
      _pairingTimedOut = true;
      _pairingError = error.toString();
    } finally {
      _loadingPairings = false;
    }
    safeNotifyListeners();
  }
}
