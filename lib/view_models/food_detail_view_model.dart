import 'package:meta/meta.dart' show protected;

import '../core/base_view_model.dart';
import '../domain_model/food_pairing.dart';
import '../domain_model/local_food.dart';
import '../domain_model/pronunciation_playback_result.dart';
import '../model/business_logic/food_logic_facade.dart';

/// Presentation state for one local-food detail page.
class FoodDetailViewModel extends BaseViewModel {
  FoodDetailViewModel();

  @protected
  FoodLogicFacade createFoodLogic() => FoodLogicFacade();

  late final FoodLogicFacade foodLogic = createFoodLogic();

  int foodId = 0;
  int _loadGeneration = 0;
  int _pairingGeneration = 0;
  LocalFood? _food;
  bool _isLiked = false;
  List<LocalFood> _similarFoods = const <LocalFood>[];
  List<LocalFood> _catalogue = const <LocalFood>[];
  List<FoodPairing> _pairings = const <FoodPairing>[];
  bool _loadingPairings = false;
  String? _pairingError;
  String? _allergyWarning;
  LocalFood? _collidedFood;
  bool _isFoodInformationExpanded = false;
  bool _isStartingPronunciation = false;
  bool _isUpdatingFavourite = false;
  String? _pronunciationMessage;

  LocalFood? get food => _food;
  bool get isLiked => _isLiked;
  List<LocalFood> get similarFoods => _similarFoods;
  List<FoodPairing> get pairings => _pairings;
  bool get loadingPairings => _loadingPairings;
  String? get pairingError => _pairingError;
  String? get allergyWarning => _allergyWarning;
  LocalFood? get collidedFood => _collidedFood;
  bool get isFoodInformationExpanded => _isFoodInformationExpanded;
  bool get isStartingPronunciation => _isStartingPronunciation;
  bool get isUpdatingFavourite => _isUpdatingFavourite;
  String? get pronunciationMessage => _pronunciationMessage;

  @override
  Future<void> onInit() => loadFood(foodId);

  Future<void> loadFood(int id) async {
    final int generation = ++_loadGeneration;
    ++_pairingGeneration;
    foodId = id;
    _food = null;
    _isLiked = false;
    _collidedFood = null;
    _allergyWarning = null;
    _similarFoods = const <LocalFood>[];
    _catalogue = const <LocalFood>[];
    _loadingPairings = false;
    _isFoodInformationExpanded = false;
    _pairings = const <FoodPairing>[];
    _pairingError = null;
    setBusy();
    try {
      final LocalFood food = await foodLogic.getFoodDetails(id);
      final List<Object?> related =
          await Future.wait<Object?>(<Future<Object?>>[
            _orDefault<LocalFood?>(foodLogic.detectNameCollision(id), null),
            _dietaryWarningOrCaution(id),
            _orDefault<List<LocalFood>>(
              foodLogic.getSimilarFoods(id),
              const <LocalFood>[],
            ),
            _orDefault<List<LocalFood>>(
              foodLogic.getLocalFoods(),
              const <LocalFood>[],
            ),
          ]);
      if (generation != _loadGeneration) return;

      _food = food;
      _isLiked = food.isFavourite;
      _collidedFood = related[0] as LocalFood?;
      _allergyWarning = related[1] as String?;
      _similarFoods = related[2] as List<LocalFood>;
      _catalogue = related[3] as List<LocalFood>;
      setReady();
      await loadPairings(expectedFoodId: id);
    } catch (error, stackTrace) {
      if (generation == _loadGeneration) setError(error, stackTrace);
    }
  }

  Future<T> _orDefault<T>(Future<T> request, T fallback) async {
    try {
      return await request;
    } catch (_) {
      return fallback;
    }
  }

  Future<String?> _dietaryWarningOrCaution(int id) async {
    try {
      return await foodLogic.dietaryWarning(id);
    } catch (_) {
      return 'Dietary information is unavailable. Check with the restaurant '
          'before ordering.';
    }
  }

  Future<void> loadPairings({int? expectedFoodId}) async {
    final int requestedFoodId = expectedFoodId ?? foodId;
    if (_food?.id != requestedFoodId) return;
    final int generation = ++_pairingGeneration;
    _loadingPairings = true;
    _pairingError = null;
    safeNotifyListeners();
    try {
      final List<FoodPairing> pairings = await foodLogic
          .getFoodPairingRecommendations(requestedFoodId);
      if (generation != _pairingGeneration || foodId != requestedFoodId) {
        return;
      }
      _pairings = pairings;
    } catch (error) {
      if (generation != _pairingGeneration || foodId != requestedFoodId) {
        return;
      }
      _pairings = const <FoodPairing>[];
      _pairingError = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (generation == _pairingGeneration) {
        _loadingPairings = false;
        safeNotifyListeners();
      }
    }
  }

  LocalFood? pairedFood(int id) {
    for (final LocalFood food in _catalogue) {
      if (food.id == id) return food;
    }
    return null;
  }

  Future<String?> toggleLike() async {
    if (_isUpdatingFavourite) return null;
    final int requestedFoodId = foodId;
    _isUpdatingFavourite = true;
    safeNotifyListeners();
    try {
      final bool isLiked = await foodLogic.toggleFavouriteFood(requestedFoodId);
      if (_food != null && _food!.id != requestedFoodId) return null;
      _isLiked = isLiked;
      _food = _food?.copyWith(isFavourite: isLiked);
      return null;
    } catch (error) {
      final String message = error.toString();
      return message.startsWith('Exception: ')
          ? message.substring('Exception: '.length)
          : message;
    } finally {
      _isUpdatingFavourite = false;
      safeNotifyListeners();
    }
  }

  void toggleFoodInformation() {
    _isFoodInformationExpanded = !_isFoodInformationExpanded;
    safeNotifyListeners();
  }

  Future<void> playPronunciation() async {
    final LocalFood? currentFood = _food;
    if (currentFood == null || _isStartingPronunciation) return;
    _isStartingPronunciation = true;
    _pronunciationMessage = null;
    safeNotifyListeners();
    try {
      final PronunciationPlaybackResult result = await foodLogic
          .playPronunciation(currentFood);
      if (_food?.id != currentFood.id) return;
      _pronunciationMessage = switch (result) {
        PronunciationPlaybackResult.curatedAudio => null,
        PronunciationPlaybackResult.deviceVoice =>
          'Using your device voice for this pronunciation.',
        PronunciationPlaybackResult.unavailable =>
          'Pronunciation audio is unavailable on this device.',
      };
    } finally {
      _isStartingPronunciation = false;
      safeNotifyListeners();
    }
  }

  String? takePronunciationMessage() {
    final String? message = _pronunciationMessage;
    _pronunciationMessage = null;
    return message;
  }
}
